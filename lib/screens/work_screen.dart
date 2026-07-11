import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:intl/intl.dart';

import '../l10n/strings.dart';
import '../models/document_session.dart';
import '../models/placement.dart';
import '../services/default_folder_service.dart';
import '../services/export_service.dart';
import '../services/history_service.dart';
import '../services/import_service.dart';
import '../services/pdf_render_service.dart';
import '../services/print_service.dart';
import '../services/settings_service.dart';
import '../services/share_service.dart';
import '../services/stamp_service.dart';
import '../widgets/ad_banner.dart';
import '../widgets/bottom_toolbar.dart';
import '../widgets/note_sheet.dart';
import '../widgets/placement_overlay.dart';
import '../widgets/signature_sheet.dart';
import 'history_screen.dart';
import 'settings_screen.dart';
import 'stamp_setup_screen.dart';

/// The single work screen: zoomable document pages, placement overlays,
/// bottom toolbar with the ad banner underneath.
class WorkScreen extends StatefulWidget {
  const WorkScreen({super.key});

  @override
  State<WorkScreen> createState() => _WorkScreenState();
}

class _WorkScreenState extends State<WorkScreen> {
  static const double _pagePadding = 12;
  static const double _pageGap = 10;

  /// Standard placed sizes relative to the page width — a signature lands at
  /// a fixed, real-world standard size (~4cm on A4) and is resizable after.
  static const double _signatureWidthFraction = 0.22;
  static const double _stampWidthFraction = 0.2;
  static const double _comboWidthFraction = 0.24;
  static const double _noteWidthFraction = 0.5;

  /// Note text follows the document's measured text-line height.
  static const double _noteLineHeights = 1.1;

  /// Group ids for whole-booklet placements (edit-one-edits-all).
  int _nextGroupId = 1;

  final PdfRenderService _renderService = PdfRenderService();
  late final ImportService _importService = ImportService(_renderService);
  final ExportService _exportService = ExportService();
  final StampService _stampService = StampService();
  final ShareService _shareService = ShareService();
  final DefaultFolderService _folderService = DefaultFolderService();
  final PrintService _printService = PrintService();
  final SettingsService _settingsService = SettingsService();
  final HistoryService _historyService = HistoryService();

  final TransformationController _transformation = TransformationController();

  DocumentSession? _session;
  ToolbarTool _armedTool = ToolbarTool.signature;
  bool _busy = false;
  StreamSubscription<String>? _shareSub;

  // Long-press area marking (normalized page coordinates).
  int? _markPageIndex;
  Offset? _markStartN;
  Offset? _markCurrentN;

  // Document layout captured for programmatic zoom.
  Size _viewportSize = Size.zero;
  double _docHeight = 0;

  @override
  void initState() {
    super.initState();
    _initSharing();
  }

  Future<void> _initSharing() async {
    _shareSub = _importService.sharedFileStream().listen(_openSharedPath);
    _importService.setViewFileListener(_openSharedPath);
    final initial = await _importService.getInitialSharedFile();
    if (initial != null) {
      await _openSharedPath(initial);
    }
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    _transformation.dispose();
    _session?.dispose();
    _renderService.close();
    super.dispose();
  }

  // ── Import ────────────────────────────────────────────────────────────────

  Future<void> _pickAndOpen() =>
      _openWith(() => _importService.pickAndOpen());

  Future<void> _openSharedPath(String path) async {
    if (!ImportService.isSupported(path)) {
      _snack(S.of(context)['importError']);
      return;
    }
    await _openWith(() => _importService.openPath(path));
  }

  Future<void> _openWith(Future<DocumentSession?> Function() open) async {
    setState(() => _busy = true);
    try {
      final session = await open();
      if (!mounted) return;
      if (session == null) {
        setState(() => _busy = false);
        return; // user cancelled the picker
      }
      _session?.dispose();
      setState(() {
        _session = session;
        _armedTool = ToolbarTool.signature;
        _busy = false;
      });
      _transformation.value = Matrix4.identity();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(S.of(context)['importError']);
    }
  }

  // ── Page geometry (document coordinates) ──────────────────────────────────

  List<double> _pageHeights(double contentWidth) {
    final session = _session!;
    return [
      for (final size in session.pageSizes)
        contentWidth * size.height / size.width,
    ];
  }

  List<double> _pageTops(List<double> heights) {
    final tops = <double>[];
    var y = _pagePadding;
    for (final h in heights) {
      tops.add(y);
      y += h + _pageGap;
    }
    return tops;
  }

  // ── Long-press area marking ───────────────────────────────────────────────

  void _onMarkStart(int pageIndex, Offset local, Size pageSize) {
    if (_busy) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _markPageIndex = pageIndex;
      _markStartN = Offset(
          local.dx / pageSize.width, local.dy / pageSize.height);
      _markCurrentN = _markStartN;
    });
  }

  void _onMarkUpdate(int pageIndex, Offset local, Size pageSize) {
    if (_markPageIndex != pageIndex) return;
    setState(() {
      _markCurrentN = Offset(
        (local.dx / pageSize.width).clamp(0.0, 1.0),
        (local.dy / pageSize.height).clamp(0.0, 1.0),
      );
    });
  }

  Future<void> _onMarkEnd(int pageIndex) async {
    final start = _markStartN;
    final current = _markCurrentN;
    setState(() {
      _markPageIndex = null;
      _markStartN = null;
      _markCurrentN = null;
    });
    if (start == null || current == null) return;

    final rect = Rect.fromPoints(start, current);
    final nx = rect.center.dx;
    final ny = rect.center.dy;
    // A meaningful drag (≥ 4% of page width) sets the placement size;
    // a plain long-press uses the proportional defaults.
    final double? widthOverride =
        rect.width >= 0.04 ? rect.width.clamp(0.05, 0.95) : null;

    switch (_armedTool) {
      case ToolbarTool.signature:
        await _placeSignature(pageIndex, nx, ny, widthOverride);
      case ToolbarTool.stamp:
        await _placeStamp(pageIndex, nx, ny, widthOverride);
      case ToolbarTool.note:
        await _placeNote(pageIndex, nx, ny, widthOverride);
    }
  }

  // ── Placement ─────────────────────────────────────────────────────────────

  double _noteWidthFractionFor(int pageIndex) {
    final session = _session!;
    final lineH = session.bodyTextHeightPts;
    if (lineH == null || lineH <= 0) return _noteWidthFraction;
    final pageSize = session.pageSizes[pageIndex];
    final fontPts = _noteLineHeights * lineH;
    // Inverse of ExportService.noteFontSize (0.04 * wf * pageWidth).
    return (fontPts / (0.04 * pageSize.width)).clamp(0.2, 0.9);
  }

  Future<void> _placeSignature(
      int pageIndex, double nx, double ny, double? widthOverride) async {
    final session = _session!;
    final savedSignature = await _stampService.getSignatureBytes();
    final savedStamp = await _stampService.getStampBytes();
    if (!mounted) return;
    final result = await showSignatureSheet(
      context,
      savedSignature: savedSignature,
      savedStamp: savedStamp,
      showAllPagesOption: session.pageCount > 1,
    );
    if (result == null) return;

    if (result.isNewDrawing) {
      // Remember the raw drawing (without the stamp) for the one-tap shortcut.
      unawaited(_stampService.saveSignature(result.bytes));
    }
    var bytes = result.bytes;
    if (result.withStamp && savedStamp != null) {
      bytes =
          await StampService.compositeSignatureOverStamp(bytes, savedStamp);
    }
    final pages = result.allPages
        ? List.generate(session.pageCount, (i) => i)
        : [pageIndex];
    await _addImagePlacement(
      type: PlacementType.signature,
      bytes: bytes,
      pages: pages,
      nx: nx,
      ny: ny,
      widthFraction: widthOverride ??
          (result.withStamp
              ? _comboWidthFraction
              : _signatureWidthFraction),
    );
  }

  Future<void> _placeStamp(
      int pageIndex, double nx, double ny, double? widthOverride) async {
    final session = _session!;
    var bytes = await _stampService.getStampBytes();
    if (bytes == null) {
      if (!mounted) return;
      bytes = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(builder: (_) => const StampSetupScreen()),
      );
      if (bytes == null) return;
    }
    final placed = await _addImagePlacement(
      type: PlacementType.stamp,
      bytes: bytes,
      pages: [pageIndex],
      nx: nx,
      ny: ny,
      widthFraction: widthOverride ?? _stampWidthFraction,
    );
    // One tap replicates the stamp at the same spot on every page.
    if (session.pageCount > 1 && placed.isNotEmpty && mounted) {
      final s = S.of(context);
      final original = placed.first;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content:
              Text(s['stampPlaced'], style: const TextStyle(fontSize: 16)),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: s['copyToAllPages'],
            onPressed: () {
              final gid = _nextGroupId++;
              original.groupId = gid;
              final copies = <Placement>[];
              for (var page = 0; page < session.pageCount; page++) {
                if (page == original.pageIndex) continue;
                copies.add(Placement(
                  type: PlacementType.stamp,
                  pageIndex: page,
                  nx: original.nx,
                  ny: original.ny,
                  widthFraction: original.widthFraction,
                  aspectRatio: original.aspectRatio,
                  imageBytes: original.imageBytes,
                  groupId: gid,
                ));
              }
              session.addAll(copies);
            },
          ),
        ));
    }
  }

  Future<void> _placeNote(
      int pageIndex, double nx, double ny, double? widthOverride) async {
    final s = S.of(context);
    final name = await _settingsService.getName();
    if (!mounted) return;
    final text = await showNoteSheet(
      context,
      suggestions: [
        DateFormat('d.M.yyyy').format(DateTime.now()),
        s['approved'],
        s['received'],
        ?name,
      ],
    );
    if (text == null || text.isEmpty) return;
    _session?.addPlacement(Placement(
      type: PlacementType.note,
      pageIndex: pageIndex,
      nx: nx,
      ny: ny,
      widthFraction: widthOverride ?? _noteWidthFractionFor(pageIndex),
      text: text,
    ));
  }

  Future<void> _editNote(Placement placement) async {
    final session = _session;
    if (session == null) return;
    final text = await showNoteSheet(context, initialText: placement.text);
    if (text == null || text.isEmpty) return;
    placement.text = text;
    session.touch();
  }

  Future<List<Placement>> _addImagePlacement({
    required PlacementType type,
    required Uint8List bytes,
    required List<int> pages,
    required double nx,
    required double ny,
    required double widthFraction,
  }) async {
    final image = await decodeImageFromList(bytes);
    final aspect = image.width / image.height;
    image.dispose();
    unawaited(HapticFeedback.mediumImpact());
    // A multi-page placement is one editable group.
    final gid = pages.length > 1 ? _nextGroupId++ : null;
    final placed = <Placement>[];
    for (final page in pages) {
      placed.add(Placement(
        type: type,
        pageIndex: page,
        nx: nx,
        ny: ny,
        widthFraction: widthFraction,
        aspectRatio: aspect,
        imageBytes: bytes,
        groupId: gid,
      ));
    }
    _session?.addAll(placed);
    return placed;
  }

  // ── Add pages ─────────────────────────────────────────────────────────────

  Future<void> _addBlankPage() =>
      _appendPage((bytes) async => ImportService.appendBlankPage(bytes));

  Future<void> _addImagePage() => _appendPage((bytes) async {
        final image = await _importService.pickImageBytes();
        if (image == null) return null;
        return ImportService.appendImagePage(bytes, image);
      });

  Future<void> _appendPage(
      Future<Uint8List?> Function(Uint8List) transform) async {
    final session = _session;
    if (session == null || _busy) return;
    setState(() => _busy = true);
    try {
      final newBytes = await transform(session.pdfBytes);
      if (newBytes == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final newSession =
          await _importService.openBytes(newBytes, fileName: session.fileName);
      // Pages are appended at the end, so existing placements keep their
      // page indices.
      newSession.placements.value = session.placements.value;
      session.dispose();
      if (!mounted) return;
      setState(() {
        _session = newSession;
        _busy = false;
      });
      _snack(S.of(context)['pageAdded']);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(S.of(context)['importError']);
    }
  }

  // ── Zoom ──────────────────────────────────────────────────────────────────

  void _zoomBy(double factor) {
    final matrix = _transformation.value;
    final scale = matrix.getMaxScaleOnAxis();
    final target = (scale * factor).clamp(1.0, 6.0);
    if (target == scale) return;
    final f = target / scale;
    final center =
        Offset(_viewportSize.width / 2, _viewportSize.height / 2);
    final t = matrix.getTranslation();
    var tx = center.dx - (center.dx - t.x) * f;
    var ty = center.dy - (center.dy - t.y) * f;
    // Keep the document inside the viewport.
    tx = tx.clamp(_viewportSize.width * (1 - target), 0.0);
    final minY =
        math.min(0.0, _viewportSize.height - _docHeight * target);
    ty = ty.clamp(minY, 0.0);
    _transformation.value = Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(target, target, 1, 1);
  }

  void _onToolSelected(ToolbarTool tool) {
    setState(() => _armedTool = tool);
    _snack(S.of(context)['tapToPlace']);
  }

  void _deletePlacement(Placement placement) {
    final session = _session;
    if (session == null) return;
    // Whole-booklet placements delete (and restore) as one group.
    final removed = session.removeWithGroup(placement);
    final s = S.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(s['deleted'], style: const TextStyle(fontSize: 16)),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: s['undo'],
          onPressed: () => session.addAll(removed),
        ),
      ));
  }

  // ── Export ────────────────────────────────────────────────────────────────

  Future<bool> _confirmPermanentEmbedding() async {
    final s = S.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.lock_outline, size: 32),
        title: Text(s['permanentTitle']),
        content: Text(
          s['permanentBody'],
          style: const TextStyle(fontSize: 16, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(s['cancel']),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(s['continue']),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _send() async {
    final session = _session;
    if (session == null || _busy) return;
    if (session.placements.value.isEmpty) {
      // Nothing to flatten yet — this is also how "just save/share the
      // document as opened" works: the same sheet (Share / quick save to
      // the default folder / Save to… / Print), just skipping the
      // permanent-embedding step since nothing is being embedded.
      await _showSendSheet(session.pdfBytes, session.fileName);
      return;
    }
    if (!await _confirmPermanentEmbedding()) return;

    setState(() => _busy = true);
    try {
      final signedBytes = await _exportService.exportSigned(
        session: session,
        renderService: _renderService,
      );
      // Permanent local copy, independent of the transient share/print file
      // — kept in History until the user deletes it themselves.
      if (HistoryService.isSupported) {
        unawaited(_historyService.record(
          bytes: signedBytes,
          fileName: session.signedFileName,
          pageCount: session.pageCount,
        ));
      }
      if (!mounted) return;
      setState(() => _busy = false);
      await _showSendSheet(signedBytes, session.signedFileName);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(S.of(context)['exportError']);
    }
  }

  Future<void> _showSendSheet(Uint8List signedBytes, String fileName) async {
    final s = S.of(context);
    final defaultFolder = await _folderService.folderName();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // One-tap save into the folder chosen in Settings — the
            // practical "connect to Drive/OneDrive" the field team asked
            // for, without any account sign-in inside the app.
            if (defaultFolder != null)
              ListTile(
                leading: Icon(Icons.bolt, size: 28, color: Colors.amber[800]),
                title: Text(s['saveToDefaultFolder'],
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600)),
                subtitle: Text(defaultFolder,
                    style: const TextStyle(fontSize: 13)),
                minTileHeight: 56,
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final ok =
                      await _folderService.saveFile(signedBytes, fileName);
                  _snack(ok ? '${s['savedToDefaultFolder']} — $defaultFolder'
                      : s['exportError']);
                },
              ),
            if (ShareService.canShare)
              ListTile(
                leading: const Icon(Icons.share, size: 28),
                title: Text(s['share'], style: const TextStyle(fontSize: 18)),
                minTileHeight: 56,
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _shareService.shareBytes(signedBytes, fileName);
                },
              ),
            // System save dialog — Drive / OneDrive / shared folders /
            // device storage. On the web this becomes a browser download.
            ListTile(
              leading: Icon(
                ShareService.canShare
                    ? Icons.drive_folder_upload_outlined
                    : Icons.download,
                size: 28,
              ),
              title: Text(
                ShareService.canShare ? s['saveTo'] : s['download'],
                style: const TextStyle(fontSize: 18),
              ),
              minTileHeight: 56,
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final saved =
                    await _shareService.saveAs(signedBytes, fileName);
                if (saved) _snack(s['copySaved']);
              },
            ),
            ListTile(
              leading: const Icon(Icons.print_outlined, size: 28),
              title: Text(s['print'], style: const TextStyle(fontSize: 18)),
              minTileHeight: 56,
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _printService.printPdf(signedBytes, fileName);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 16)),
        duration: const Duration(seconds: 2),
      ));
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final session = _session;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerHighest,
      appBar: AppBar(
        title: session == null
            ? Text(s['appTitle'])
            : Column(
                children: [
                  Text(s['appTitle']),
                  Text(
                    session.fileName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
        actions: [
          if (session != null)
            PopupMenuButton<String>(
              tooltip: s['addPage'],
              iconSize: 26,
              icon: const Icon(Icons.post_add_outlined),
              onSelected: (value) => value == 'blank'
                  ? _addBlankPage()
                  : _addImagePage(),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'blank',
                  child: ListTile(
                    leading: const Icon(Icons.insert_drive_file_outlined),
                    title: Text(s['blankPage']),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'image',
                  child: ListTile(
                    leading: const Icon(Icons.image_outlined),
                    title: Text(s['imagePage']),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          if (session != null)
            IconButton(
              tooltip: s['newDocument'],
              iconSize: 26,
              onPressed: _busy ? null : _pickAndOpen,
              icon: const Icon(Icons.note_add_outlined),
            ),
          if (HistoryService.isSupported)
            IconButton(
              tooltip: s['history'],
              iconSize: 26,
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const HistoryScreen()),
                      ),
              icon: const Icon(Icons.history),
            ),
          IconButton(
            tooltip: s['settings'],
            iconSize: 26,
            onPressed: _busy
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const SettingsScreen()),
                    ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: session == null ? _buildEmptyState(s) : _buildDocument(),
          ),
          Material(
            color: scheme.surfaceContainer,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BottomToolbar(
                    armedTool: _armedTool,
                    enabled: session != null && !_busy,
                    onToolSelected: _onToolSelected,
                    onSend: _send,
                  ),
                  // Ads pinned at the very bottom, below the toolbar.
                  const AdBanner(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(S s) {
    if (_busy) return const Center(child: CircularProgressIndicator());
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.draw_outlined,
                  size: 52, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 22),
            Text(
              s['emptyTitle'],
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w600, height: 1.2),
            ),
            const SizedBox(height: 6),
            Text(
              s['emptySubtitle'],
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 26),
            FilledButton.icon(
              onPressed: _pickAndOpen,
              icon: const Icon(Icons.file_open_outlined, size: 28),
              label:
                  Text(s['openDocument'], style: const TextStyle(fontSize: 19)),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 30, vertical: 18),
              ),
            ),
            if (ShareService.canShare) ...[
              const SizedBox(height: 18),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.ios_share,
                      size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    s['shareHint'],
                    style: TextStyle(
                        fontSize: 15, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDocument() {
    final session = _session!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        final contentWidth = viewportWidth - 2 * _pagePadding;
        final heights = _pageHeights(contentWidth);
        final tops = _pageTops(heights);
        final docHeight = tops.last + heights.last + _pagePadding;
        _viewportSize = Size(viewportWidth, constraints.maxHeight);
        _docHeight = docHeight;

        return Stack(
          children: [
            // One zoomable surface holding pages AND overlays, so they share
            // a coordinate space at every zoom level (comfortable reading +
            // consistent placement).
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _transformation,
                constrained: false,
                minScale: 1,
                maxScale: 6,
                child: SizedBox(
                  width: viewportWidth,
                  height: math.max(docHeight, constraints.maxHeight),
                  child: Stack(
                    children: [
                      // Only pages inside the viewport (+ a preload buffer)
                      // actually render — a 53-page CAD-drawing PDF used to
                      // kick off all 53 renders the instant it opened. Pages
                      // outside the range show a cheap blank placeholder and
                      // cost nothing until they're scrolled into view.
                      AnimatedBuilder(
                        animation: _transformation,
                        builder: (context, _) {
                          final visible = _visiblePageIndices(
                              tops, heights, constraints.maxHeight);
                          return Stack(
                            children: [
                              for (var i = 0; i < session.pageCount; i++)
                                Positioned(
                                  left: _pagePadding,
                                  top: tops[i],
                                  width: contentWidth,
                                  height: heights[i],
                                  child: visible.contains(i)
                                      ? _PageItem(
                                          renderService: _renderService,
                                          pageIndex: i,
                                          width: contentWidth,
                                          height: heights[i],
                                          onMarkStart: (local, size) =>
                                              _onMarkStart(i, local, size),
                                          onMarkUpdate: (local, size) =>
                                              _onMarkUpdate(i, local, size),
                                          onMarkEnd: () => _onMarkEnd(i),
                                        )
                                      : const _PagePlaceholder(),
                                ),
                            ],
                          );
                        },
                      ),
                      // Live selection rectangle while long-press marking.
                      if (_markPageIndex != null &&
                          _markStartN != null &&
                          _markCurrentN != null)
                        _buildMarkRect(contentWidth, tops, heights),
                      ValueListenableBuilder<List<Placement>>(
                        valueListenable: session.placements,
                        builder: (context, placements, _) => Stack(
                          clipBehavior: Clip.none,
                          children: [
                            for (final placement in placements)
                              PlacementOverlay(
                                key: ObjectKey(placement),
                                placement: placement,
                                pageRect: Rect.fromLTWH(
                                  _pagePadding,
                                  tops[placement.pageIndex],
                                  contentWidth,
                                  heights[placement.pageIndex],
                                ),
                                transformation: _transformation,
                                onChanged: () {
                                  // Whole-booklet groups stay in sync.
                                  session.syncGroup(placement);
                                  session.touch();
                                },
                                onDelete: () => _deletePlacement(placement),
                                onEdit: placement.type == PlacementType.note
                                    ? () => _editNote(placement)
                                    : null,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Zoom controls — mouse/keyboard friendly and accessible.
            PositionedDirectional(
              bottom: 14,
              end: 14,
              child: Column(
                children: [
                  _ZoomButton(
                    icon: Icons.add,
                    label: S.of(context)['zoomIn'],
                    onTap: () => _zoomBy(1.4),
                  ),
                  const SizedBox(height: 8),
                  _ZoomButton(
                    icon: Icons.remove,
                    label: S.of(context)['zoomOut'],
                    onTap: () => _zoomBy(1 / 1.4),
                  ),
                ],
              ),
            ),
            // Current page indicator (multi-page documents only).
            if (session.pageCount > 1)
              Positioned(
                top: 10,
                left: 0,
                right: 0,
                child: Center(
                  child: AnimatedBuilder(
                    animation: _transformation,
                    builder: (context, _) {
                      final page = _currentPage(
                          tops, heights, constraints.maxHeight);
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xB3000000),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${page + 1} / ${session.pageCount}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                        ),
                      );
                    },
                  ),
                ),
              ),
            if (_busy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x66000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        );
      },
    );
  }

  /// The translucent rectangle drawn while the user long-press-drags to mark
  /// where (and how big) the placement should be.
  Widget _buildMarkRect(
      double contentWidth, List<double> tops, List<double> heights) {
    final page = _markPageIndex!;
    final rect = Rect.fromPoints(_markStartN!, _markCurrentN!);
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      left: _pagePadding + rect.left * contentWidth,
      top: tops[page] + rect.top * heights[page],
      width: math.max(rect.width * contentWidth, 4),
      height: math.max(rect.height * heights[page], 4),
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.15),
            border: Border.all(color: scheme.primary, width: 2),
          ),
        ),
      ),
    );
  }

  /// The page whose content is at the viewport center, derived from the
  /// InteractiveViewer transform.
  int _currentPage(
      List<double> tops, List<double> heights, double viewportHeight) {
    final matrix = _transformation.value;
    final scale = matrix.getMaxScaleOnAxis();
    final translationY = matrix.getTranslation().y;
    final centerDocY = (viewportHeight / 2 - translationY) / scale;
    for (var i = 0; i < tops.length; i++) {
      if (centerDocY < tops[i] + heights[i] + _pageGap / 2) return i;
    }
    return tops.length - 1;
  }

  /// Pages that overlap the current viewport, expanded by one screen's worth
  /// of preload buffer above and below so scrolling stays smooth. Only these
  /// pages are actually rendered — the rest cost nothing until they scroll
  /// into range, which is what keeps a 50+ page document fast to open.
  Set<int> _visiblePageIndices(
      List<double> tops, List<double> heights, double viewportHeight) {
    final matrix = _transformation.value;
    final scale = matrix.getMaxScaleOnAxis();
    final translationY = matrix.getTranslation().y;
    final visibleTop = (0 - translationY) / scale;
    final visibleBottom = (viewportHeight - translationY) / scale;
    final buffer = viewportHeight / scale;
    final rangeTop = visibleTop - buffer;
    final rangeBottom = visibleBottom + buffer;

    final result = <int>{};
    for (var i = 0; i < tops.length; i++) {
      final pageTop = tops[i];
      final pageBottom = tops[i] + heights[i];
      if (pageBottom >= rangeTop && pageTop <= rangeBottom) {
        result.add(i);
      }
    }
    return result;
  }
}

/// Cheap stand-in for a page that is outside the render range — a blank
/// sheet with no image decode, no isolate call, nothing async.
class _PagePlaceholder extends StatelessWidget {
  const _PagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: Colors.white),
    );
  }
}

/// One rendered PDF page. Placement starts with a long-press: hold to anchor,
/// drag to mark the area, release to place.
class _PageItem extends StatelessWidget {
  const _PageItem({
    required this.renderService,
    required this.pageIndex,
    required this.width,
    required this.height,
    required this.onMarkStart,
    required this.onMarkUpdate,
    required this.onMarkEnd,
  });

  final PdfRenderService renderService;
  final int pageIndex;
  final double width;
  final double height;
  final void Function(Offset local, Size renderedSize) onMarkStart;
  final void Function(Offset local, Size renderedSize) onMarkUpdate;
  final VoidCallback onMarkEnd;

  @override
  Widget build(BuildContext context) {
    final size = Size(width, height);
    return GestureDetector(
      onLongPressStart: (details) =>
          onMarkStart(details.localPosition, size),
      onLongPressMoveUpdate: (details) =>
          onMarkUpdate(details.localPosition, size),
      onLongPressEnd: (_) => onMarkEnd(),
      onLongPressCancel: onMarkEnd,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: FutureBuilder<Uint8List>(
          future: renderService.renderPage(pageIndex),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              );
            }
            return Image.memory(
              snapshot.data!,
              fit: BoxFit.fill,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
            );
          },
        ),
      ),
    );
  }
}

/// Small round zoom button, tooltip'd and screen-reader friendly.
class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: scheme.surfaceContainerHigh.withValues(alpha: 0.92),
          shape: const CircleBorder(),
          elevation: 2,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(icon, size: 24, color: scheme.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}
