import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/document_session.dart';
import '../models/placement.dart';
import '../services/export_service.dart';
import '../services/import_service.dart';
import '../services/pdf_render_service.dart';
import '../services/share_service.dart';
import '../services/stamp_service.dart';
import '../widgets/ad_banner.dart';
import '../widgets/bottom_toolbar.dart';
import '../widgets/note_sheet.dart';
import '../widgets/placement_overlay.dart';
import '../widgets/signature_sheet.dart';
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

  /// Default placed sizes relative to the page width — proportional to
  /// typical document text (a signature ≈ 4cm on an A4 page).
  static const double _signatureWidthFraction = 0.22;
  static const double _stampWidthFraction = 0.2;
  static const double _noteWidthFraction = 0.5;

  final PdfRenderService _renderService = PdfRenderService();
  late final ImportService _importService = ImportService(_renderService);
  final ExportService _exportService = ExportService();
  final StampService _stampService = StampService();
  final ShareService _shareService = ShareService();

  final TransformationController _transformation = TransformationController();

  DocumentSession? _session;
  ToolbarTool _armedTool = ToolbarTool.signature;
  bool _busy = false;
  StreamSubscription<String>? _shareSub;

  @override
  void initState() {
    super.initState();
    _initSharing();
  }

  Future<void> _initSharing() async {
    _shareSub = _importService.sharedFileStream().listen(_openPath);
    final initial = await _importService.getInitialSharedFile();
    if (initial != null) {
      await _openPath(initial);
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

  Future<void> _pickAndOpen() async {
    final path = await _importService.pickFile();
    if (path != null) await _openPath(path);
  }

  Future<void> _openPath(String path) async {
    if (!ImportService.isSupported(path)) {
      _snack(S.of(context)['importError']);
      return;
    }
    setState(() => _busy = true);
    try {
      final session = await _importService.openDocument(path);
      if (!mounted) return;
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

  // ── Placement ─────────────────────────────────────────────────────────────

  Future<void> _handlePageTap(
      int pageIndex, Offset local, Size renderedSize) async {
    final session = _session;
    if (session == null || _busy) return;
    final nx = (local.dx / renderedSize.width).clamp(0.0, 1.0);
    final ny = (local.dy / renderedSize.height).clamp(0.0, 1.0);

    switch (_armedTool) {
      case ToolbarTool.signature:
        await _placeSignature(pageIndex, nx, ny);
      case ToolbarTool.stamp:
        await _placeStamp(pageIndex, nx, ny);
      case ToolbarTool.note:
        await _placeNote(pageIndex, nx, ny);
    }
  }

  Future<void> _placeSignature(int pageIndex, double nx, double ny) async {
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
      widthFraction: result.withStamp
          ? _stampWidthFraction * 1.2
          : _signatureWidthFraction,
    );
  }

  Future<void> _placeStamp(int pageIndex, double nx, double ny) async {
    var bytes = await _stampService.getStampBytes();
    if (bytes == null) {
      if (!mounted) return;
      bytes = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(builder: (_) => const StampSetupScreen()),
      );
      if (bytes == null) return;
    }
    await _addImagePlacement(
      type: PlacementType.stamp,
      bytes: bytes,
      pages: [pageIndex],
      nx: nx,
      ny: ny,
      widthFraction: _stampWidthFraction,
    );
  }

  Future<void> _placeNote(int pageIndex, double nx, double ny) async {
    final text = await showNoteSheet(context);
    if (text == null || text.isEmpty) return;
    _session?.addPlacement(Placement(
      type: PlacementType.note,
      pageIndex: pageIndex,
      nx: nx,
      ny: ny,
      widthFraction: _noteWidthFraction,
      text: text,
    ));
  }

  Future<void> _addImagePlacement({
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
    for (final page in pages) {
      _session?.addPlacement(Placement(
        type: type,
        pageIndex: page,
        nx: nx,
        ny: ny,
        widthFraction: widthFraction,
        aspectRatio: aspect,
        imageBytes: bytes,
      ));
    }
  }

  void _onToolSelected(ToolbarTool tool) {
    setState(() => _armedTool = tool);
    _snack(S.of(context)['tapToPlace']);
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
      _snack(S.of(context)['nothingToExport']);
      return;
    }
    if (!await _confirmPermanentEmbedding()) return;

    setState(() => _busy = true);
    try {
      final signedPath = await _exportService.exportSigned(
        session: session,
        renderService: _renderService,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      await _showSendSheet(signedPath);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(S.of(context)['exportError']);
    }
  }

  Future<void> _showSendSheet(String signedPath) async {
    final s = S.of(context);
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share, size: 28),
              title: Text(s['share'], style: const TextStyle(fontSize: 18)),
              minTileHeight: 56,
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _shareService.shareFile(signedPath);
              },
            ),
            ListTile(
              leading: const Icon(Icons.save_alt, size: 28),
              title: Text(s['saveCopy'], style: const TextStyle(fontSize: 18)),
              minTileHeight: 56,
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _shareService.saveCopy(signedPath);
                _snack(s['copySaved']);
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
        title: Text(s['appTitle']),
        actions: [
          if (session != null)
            IconButton(
              tooltip: s['newDocument'],
              iconSize: 26,
              onPressed: _busy ? null : _pickAndOpen,
              icon: const Icon(Icons.note_add_outlined),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.tonalIcon(
            onPressed: _pickAndOpen,
            icon: const Icon(Icons.file_open_outlined, size: 32),
            label: Text(s['openDocument'], style: const TextStyle(fontSize: 20)),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.ios_share, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                s['shareHint'],
                style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
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
                      for (var i = 0; i < session.pageCount; i++)
                        Positioned(
                          left: _pagePadding,
                          top: tops[i],
                          width: contentWidth,
                          height: heights[i],
                          child: _PageItem(
                            renderService: _renderService,
                            pageIndex: i,
                            width: contentWidth,
                            height: heights[i],
                            onTapUp: (local, size) =>
                                _handlePageTap(i, local, size),
                          ),
                        ),
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
                                onChanged: session.touch,
                                onDelete: () =>
                                    session.removePlacement(placement),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
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
}

/// One rendered PDF page with a tap detector for placement.
class _PageItem extends StatelessWidget {
  const _PageItem({
    required this.renderService,
    required this.pageIndex,
    required this.width,
    required this.height,
    required this.onTapUp,
  });

  final PdfRenderService renderService;
  final int pageIndex;
  final double width;
  final double height;
  final void Function(Offset local, Size renderedSize) onTapUp;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapUp: (details) =>
          onTapUp(details.localPosition, Size(width, height)),
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
