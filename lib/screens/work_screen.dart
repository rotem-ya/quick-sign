import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show kMiddleMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
        HapticFeedback,
        HardwareKeyboard,
        KeyDownEvent,
        KeyEvent,
        KeyRepeatEvent,
        LogicalKeyboardKey,
        SystemChrome,
        SystemUiMode;
import 'package:intl/intl.dart';

import '../app.dart';
import '../l10n/strings.dart';
import '../models/document_session.dart';
import '../models/placement.dart';
import '../models/saved_mark.dart';
import '../services/default_folder_service.dart';
import '../services/export_service.dart';
import '../services/folder_library_service.dart';
import '../services/history_service.dart';
import '../services/import_service.dart';
import '../services/marks_service.dart';
import '../services/pdf_render_service.dart';
import '../services/print_service.dart';
import '../services/settings_service.dart';
import '../services/share_service.dart';
import '../services/stamp_service.dart';
import '../theme/design_tokens.dart';
import '../utils/matrix4_scale.dart';
import '../widgets/action_sheet.dart';
import '../widgets/ad_banner.dart';
import '../widgets/bottom_toolbar.dart';
import '../widgets/drag_drop_stub.dart'
    if (dart.library.js_interop) '../widgets/drag_drop_web.dart'
    as drag_drop;
import '../widgets/note_sheet.dart';
import '../widgets/placement_overlay.dart';
import '../widgets/signature_sheet.dart';
import '../widgets/toolbox_panel.dart';
import '../widgets/wheel_scroll_stub.dart'
    if (dart.library.js_interop) '../widgets/wheel_scroll_web.dart'
    as wheel_scroll;
import 'folder_browser_screen.dart';
import 'history_screen.dart';
import 'page_manager_screen.dart';
import 'settings_screen.dart';

/// The single work screen: zoomable document pages, placement overlays,
/// bottom toolbar with the ad banner underneath.
class WorkScreen extends StatefulWidget {
  const WorkScreen({super.key});

  @override
  State<WorkScreen> createState() => _WorkScreenState();
}

class _WorkScreenState extends State<WorkScreen> with RouteAware {
  static const double _pagePadding = 12;
  static const double _pageGap = 10;

  /// Standard placed sizes relative to the page width, calibrated for a
  /// standard A4 page (595pt) — a signature lands at a fixed, real-world
  /// standard size (~4cm on A4) and is resizable after. Used as-is only
  /// when the document's text height can't be measured; otherwise
  /// [_markWidthFractionFor] scales these to the document's actual scale.
  static const double _signatureWidthFraction = 0.22;
  static const double _stampWidthFraction = 0.2;
  static const double _comboWidthFraction = 0.24;
  static const double _noteWidthFraction = 0.5;

  /// Reference page width (A4, pt) and body-line-height (pt) the fractions
  /// above were calibrated against.
  static const double _referencePageWidthPts = 595.0;
  static const double _referenceLineHeightPts = 13.0;

  /// Small, natural-looking crookedness for a stamped impression — not a
  /// perfectly axis-aligned digital sticker.
  static const double _maxStampRotationDegrees = 6.0;

  /// Note text follows the document's measured text-line height.
  static const double _noteLineHeights = 1.1;

  /// Deep zoom — up to 3000%.
  static const double _maxZoomScale = 30.0;

  /// Zoom out below fit-width, e.g. to see a multi-page document's overall
  /// shape or several pages at once.
  static const double _minZoomScale = 0.3;

  /// Immersive chrome show/hide animation.
  static const Duration _chromeAnimationDuration = Duration(milliseconds: 220);

  /// Group ids for whole-booklet placements (edit-one-edits-all).
  int _nextGroupId = 1;

  final PdfRenderService _renderService = PdfRenderService();
  late final ImportService _importService = ImportService(_renderService);
  final ExportService _exportService = ExportService();
  final MarksService _marksService = MarksService();
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

  // Long-press placement preview: a temporary frame at the standard size
  // for the armed tool, which follows the finger while held — so the exact
  // drop point can be fine-tuned before committing, the same way the
  // placed item can still be dragged afterward. (Normalized page coords.)
  int? _markPageIndex;
  Offset? _markCenterN;
  Size? _markPreviewSizeN;

  // Document layout captured for programmatic zoom.
  Size _viewportSize = Size.zero;
  double _docHeight = 0;

  // Web only: whether this screen is the visible, topmost route — scopes
  // the mouse-wheel-pan override so it never steals scroll from another
  // screen (Settings, History, a sheet, a dialog…).
  bool _isTopRoute = true;
  Object? _wheelHandle;

  // Web only: dragging a file over the window shows a "drop to open" overlay.
  Object? _dragHandle;
  bool _isDragActive = false;

  // Immersive reading: the app bar + bottom toolbar hide on open and toggle
  // with a short tap, like a normal document reader (Foxit et al).
  bool _chromeVisible = true;

  // Desktop/web mouse feedback: Ctrl held → zoom cursor (matches Ctrl+wheel
  // zoom); middle button held → grab cursor (matches middle-drag pan, which
  // InteractiveViewer already performs for any mouse button — this only
  // adds the visual affordance).
  bool _ctrlPressed = false;
  bool _middleButtonDown = false;

  // Drives the header's page pill — kept in sync (deferred to the next
  // frame, since it's updated from inside the document canvas's own build)
  // by the same scroll-position math that used to draw a floating badge.
  final ValueNotifier<int> _currentPageNotifier = ValueNotifier<int>(0);

  // Web only: docked toolbox panel (settings + history) alongside the
  // document, instead of navigating away to a full-screen route.
  bool _toolboxOpen = false;

  /// The docked side panel is a fixed 380px wide (see ToolboxPanel) — fine
  /// alongside a document on a desktop-width browser window, but on a
  /// narrow mobile-web viewport it doesn't fit and cuts off content past
  /// the screen edge. Below this width, fall back to the same full-screen
  /// Settings/History navigation the native app already uses everywhere.
  static const double _dockedToolboxMinWidth = 760;

  bool _dockedToolboxAvailable(BuildContext context) =>
      kIsWeb && MediaQuery.sizeOf(context).width >= _dockedToolboxMinWidth;

  @override
  void initState() {
    super.initState();
    _initSharing();
    _wheelHandle = wheel_scroll.attachWheelPan(
      shouldIntercept: () => _isTopRoute && _session != null && _docHeight > 0,
      onPan: _panByWheel,
    );
    _dragHandle = drag_drop.attachFileDrop(
      onFile: _handleDroppedFile,
      onDragStateChanged: (active) {
        if (!mounted || !_isTopRoute) return;
        setState(() => _isDragActive = active);
      },
    );
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  bool _handleKeyEvent(KeyEvent event) {
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.controlLeft &&
        key != LogicalKeyboardKey.controlRight &&
        key != LogicalKeyboardKey.metaLeft &&
        key != LogicalKeyboardKey.metaRight) {
      return false;
    }
    final pressed = event is KeyDownEvent || event is KeyRepeatEvent;
    if (pressed != _ctrlPressed && mounted) {
      setState(() => _ctrlPressed = pressed);
    }
    return false; // Never consume — this only observes key state.
  }

  void _toggleChrome() {
    if (_session == null) return;
    setState(() => _chromeVisible = !_chromeVisible);
    _applyImmersiveMode(!_chromeVisible);
  }

  /// Hides the OS status/nav bars too on Android/iOS, so "full screen"
  /// means the whole physical screen, not just the in-app toolbars. No-op
  /// on web, where the browser owns its own chrome.
  void _applyImmersiveMode(bool hidden) {
    if (kIsWeb) return;
    SystemChrome.setEnabledSystemUIMode(
      hidden ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  Future<void> _handleDroppedFile(Uint8List bytes, String fileName) async {
    if (!_isTopRoute || _busy) return;
    if (!ImportService.isSupported(fileName)) {
      _snack(S.of(context)['importError']);
      return;
    }
    await _openWith(() => _importService.openBytes(bytes, fileName: fileName));
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) routeObserver.subscribe(this, route);
  }

  @override
  void didPushNext() {
    setState(() => _isTopRoute = false);
    // Restore normal system bars for whatever screen is now on top
    // (Settings/History) — immersive mode is only for reading a document.
    if (!kIsWeb) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void didPopNext() {
    setState(() => _isTopRoute = true);
    _applyImmersiveMode(!_chromeVisible);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    wheel_scroll.detachWheelPan(_wheelHandle);
    drag_drop.detachFileDrop(_dragHandle);
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _shareSub?.cancel();
    _currentPageNotifier.dispose();
    _transformation.dispose();
    _session?.dispose();
    _renderService.close();
    super.dispose();
  }

  /// Keeps the document inside the viewport — pinned to fully cover it on
  /// an axis where it's bigger than the viewport (the usual case), centered
  /// on an axis where zooming out has made it smaller than the viewport.
  Offset _clampPan(double tx, double ty, double scale) {
    final contentWidth = _viewportSize.width * scale;
    // Matches the child SizedBox, which pads short documents up to the
    // viewport height so they still fill the screen at scale 1.
    final contentHeight = math.max(_docHeight, _viewportSize.height) * scale;
    final clampedTx = contentWidth <= _viewportSize.width
        ? (_viewportSize.width - contentWidth) / 2
        : tx.clamp(_viewportSize.width - contentWidth, 0.0);
    final clampedTy = contentHeight <= _viewportSize.height
        ? (_viewportSize.height - contentHeight) / 2
        : ty.clamp(_viewportSize.height - contentHeight, 0.0);
    return Offset(clampedTx, clampedTy);
  }

  /// Plain mouse wheel pans the document like a normal page/PDF reader —
  /// InteractiveViewer itself hard-codes wheel as zoom with no way to opt
  /// out (see wheel_scroll_web.dart), so this mirrors _zoomBy's clamp math
  /// for a pure translation instead of a scale change.
  void _panByWheel(double dx, double dy) {
    final matrix = _transformation.value;
    final scale = matrix.scale2D;
    final t = matrix.getTranslation();
    final clamped = _clampPan(t.x - dx, t.y - dy, scale);
    _transformation.value = Matrix4.identity()
      ..translateByDouble(clamped.dx, clamped.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  // ── Import ────────────────────────────────────────────────────────────────

  Future<void> _pickAndOpen() => _openWith(() => _importService.pickAndOpen());

  /// Loads a History entry's bytes for viewing — same path as opening any
  /// other document, so it's fully interactive (zoom, and if it wasn't a
  /// signed/flattened copy, still editable) rather than a static preview.
  Future<void> _openHistoryEntry(Uint8List bytes, String fileName) {
    return _openWith(() => _importService.openBytes(bytes, fileName: fileName));
  }

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
        // Full-screen, immersive reading as soon as a document loads —
        // a short tap brings the toolbars back.
        _chromeVisible = false;
      });
      _applyImmersiveMode(true);
      _transformation.value = Matrix4.identity();
      // Every opened document goes into History too, not just ones that
      // get signed and sent — easy to find again even if you never finish.
      if (HistoryService.isSupported) {
        unawaited(
          _historyService.record(
            bytes: session.pdfBytes,
            fileName: session.fileName,
            pageCount: session.pageCount,
            signed: false,
          ),
        );
      }
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

  /// Roughly how the preview frame's height relates to its width for each
  /// tool — nothing more than a visual guide before the real content (a
  /// specific saved signature/stamp image, or typed text) picks its own
  /// exact aspect ratio at placement time.
  static const double _signaturePreviewAspect = 0.42;
  static const double _stampPreviewAspect = 0.6;
  static const double _notePreviewAspect = 0.35;

  void _onMarkStart(int pageIndex, Offset local, Size pageSize) {
    if (_busy) return;
    unawaited(HapticFeedback.selectionClick());
    final widthFraction = switch (_armedTool) {
      ToolbarTool.signature => _markWidthFractionFor(
        pageIndex,
        _signatureWidthFraction,
      ),
      ToolbarTool.stamp => _markWidthFractionFor(pageIndex, _stampWidthFraction),
      ToolbarTool.note => _noteWidthFractionFor(pageIndex),
    };
    final aspect = switch (_armedTool) {
      ToolbarTool.signature => _signaturePreviewAspect,
      ToolbarTool.stamp => _stampPreviewAspect,
      ToolbarTool.note => _notePreviewAspect,
    };
    setState(() {
      _markPageIndex = pageIndex;
      _markCenterN = Offset(
        (local.dx / pageSize.width).clamp(0.0, 1.0),
        (local.dy / pageSize.height).clamp(0.0, 1.0),
      );
      _markPreviewSizeN = Size(
        widthFraction,
        widthFraction * aspect * pageSize.width / pageSize.height,
      );
    });
  }

  void _onMarkUpdate(int pageIndex, Offset local, Size pageSize) {
    if (_markPageIndex != pageIndex) return;
    setState(() {
      _markCenterN = Offset(
        (local.dx / pageSize.width).clamp(0.0, 1.0),
        (local.dy / pageSize.height).clamp(0.0, 1.0),
      );
    });
  }

  Future<void> _onMarkEnd(int pageIndex) async {
    final center = _markCenterN;
    setState(() {
      _markPageIndex = null;
      _markCenterN = null;
      _markPreviewSizeN = null;
    });
    if (center == null) return;

    switch (_armedTool) {
      case ToolbarTool.signature:
        await _placeSignature(pageIndex, center.dx, center.dy, null);
      case ToolbarTool.stamp:
        await _placeStamp(pageIndex, center.dx, center.dy, null);
      case ToolbarTool.note:
        await _placeNote(pageIndex, center.dx, center.dy, null);
    }
  }

  // ── Placement ─────────────────────────────────────────────────────────────

  /// Scales a standard-calibrated fraction (signature/stamp/combo) to the
  /// document's actual scale, using its measured body-text height as the
  /// cue — the same idea as [_noteWidthFractionFor], generalized. A large-
  /// format drawing with big text gets a proportionally bigger signature
  /// instead of always the same fixed sliver of page width; a dense small-
  /// print contract gets a smaller one. Falls back to [baseFraction]
  /// unchanged when the document has no extractable text to measure.
  double _markWidthFractionFor(int pageIndex, double baseFraction) {
    final session = _session!;
    final lineH = session.bodyTextHeightPts;
    if (lineH == null || lineH <= 0) return baseFraction;
    final pageWidth = session.pageSizes[pageIndex].width;
    final scale =
        (lineH / _referenceLineHeightPts) *
        (_referencePageWidthPts / pageWidth);
    return (baseFraction * scale).clamp(0.08, 0.6);
  }

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
    int pageIndex,
    double nx,
    double ny,
    double? widthOverride,
  ) async {
    final session = _session!;
    final savedSignatures = await _marksService.list(type: MarkType.signature);
    final savedCombos = await _marksService.list(type: MarkType.combo);
    // A combo default wins — it's the more specific, deliberately-chosen
    // pick — otherwise fall back to a plain-signature default.
    final defaultMark =
        await _marksService.getDefault(MarkType.combo) ??
        await _marksService.getDefault(MarkType.signature);
    if (!mounted) return;

    SavedMark chosen;
    var allPages = false;
    if (defaultMark != null) {
      chosen = defaultMark;
    } else if (savedSignatures.isEmpty && savedCombos.isEmpty) {
      await _drawAndPlaceSignature(pageIndex, nx, ny, widthOverride);
      return;
    } else {
      final result = await showMarkPickerSheet(
        context,
        marks: [...savedSignatures, ...savedCombos],
        showAllPagesOption: session.pageCount > 1,
      );
      if (result == null || !mounted) return;
      chosen = result.mark;
      allPages = result.allPages;
    }

    final isCombo = chosen.type == MarkType.combo;
    final pages = allPages
        ? List.generate(session.pageCount, (i) => i)
        : [pageIndex];
    await _addImagePlacement(
      type: PlacementType.signature,
      bytes: chosen.imageBytes,
      pages: pages,
      nx: nx,
      ny: ny,
      widthFraction:
          widthOverride ??
          _markWidthFractionFor(
            pageIndex,
            isCombo ? _comboWidthFraction : _signatureWidthFraction,
          ),
    );
  }

  /// No saved signature exists yet — rather than send the user away to
  /// Settings mid-document, let them draw one right here and place it
  /// immediately, then offer to keep it in the library for next time.
  Future<void> _drawAndPlaceSignature(
    int pageIndex,
    double nx,
    double ny,
    double? widthOverride,
  ) async {
    final bytes = await showDrawCanvasSheet(context);
    if (bytes == null || !mounted) return;
    final placed = await _addImagePlacement(
      type: PlacementType.signature,
      bytes: bytes,
      pages: [pageIndex],
      nx: nx,
      ny: ny,
      widthFraction:
          widthOverride ??
          _markWidthFractionFor(pageIndex, _signatureWidthFraction),
    );
    if (placed.isEmpty || !mounted) return;
    _offerToSaveSignature(bytes);
  }

  void _offerToSaveSignature(Uint8List bytes) {
    final s = S.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            s['saveSignaturePrompt'],
            style: const TextStyle(fontSize: 16),
          ),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: s['save'],
            onPressed: () {
              unawaited(
                _marksService.add(
                  type: MarkType.signature,
                  name: s['sign'],
                  imageBytes: bytes,
                ),
              );
            },
          ),
        ),
      );
  }

  /// Small random tilt, in radians — only ever applied to stamps, never
  /// signatures, so each impression looks hand-stamped instead of a
  /// perfectly axis-aligned digital sticker.
  double _randomStampRotation() {
    final degrees =
        (math.Random().nextDouble() * 2 - 1) * _maxStampRotationDegrees;
    return degrees * math.pi / 180;
  }

  Future<void> _placeStamp(
    int pageIndex,
    double nx,
    double ny,
    double? widthOverride,
  ) async {
    final session = _session!;
    final stamps = await _marksService.list(type: MarkType.stamp);
    final defaultStamp = await _marksService.getDefault(MarkType.stamp);
    if (!mounted) return;
    Uint8List? cleanBytes = defaultStamp?.imageBytes;
    if (cleanBytes == null) {
      if (stamps.isEmpty) {
        _promptAddStamp();
        return;
      } else if (stamps.length == 1) {
        cleanBytes = stamps.single.imageBytes;
      } else {
        final result = await showMarkPickerSheet(context, marks: stamps);
        if (result == null || !mounted) return;
        cleanBytes = result.mark.imageBytes;
      }
    }
    final widthFraction =
        widthOverride ?? _markWidthFractionFor(pageIndex, _stampWidthFraction);
    final placed = await _addImagePlacement(
      type: PlacementType.stamp,
      bytes: StampService.addRandomImperfections(cleanBytes, math.Random()),
      pages: [pageIndex],
      nx: nx,
      ny: ny,
      widthFraction: widthFraction,
    );
    if (placed.isNotEmpty) placed.first.rotation = _randomStampRotation();

    // One tap replicates the stamp at the same spot on every page — each
    // copy gets its own independent random tilt/imperfections, like
    // genuinely separate impressions of the same physical stamp.
    if (session.pageCount > 1 && placed.isNotEmpty && mounted) {
      final s = S.of(context);
      final original = placed.first;
      final baseBytes = cleanBytes;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              s['stampPlaced'],
              style: const TextStyle(fontSize: 16),
            ),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: s['copyToAllPages'],
              onPressed: () {
                final gid = _nextGroupId++;
                original.groupId = gid;
                final copies = <Placement>[];
                for (var page = 0; page < session.pageCount; page++) {
                  if (page == original.pageIndex) continue;
                  copies.add(
                    Placement(
                      type: PlacementType.stamp,
                      pageIndex: page,
                      nx: original.nx,
                      ny: original.ny,
                      widthFraction: original.widthFraction,
                      aspectRatio: original.aspectRatio,
                      imageBytes: StampService.addRandomImperfections(
                        baseBytes,
                        math.Random(),
                      ),
                      groupId: gid,
                    )..rotation = _randomStampRotation(),
                  );
                }
                session.addAll(copies);
              },
            ),
          ),
        );
    }
  }

  /// No saved stamp yet — unlike a signature, there's no quick "draw it
  /// here" alternative for a stamp (it needs a photo/crop/background
  /// removal, or the designer), so this still points to Settings.
  void _promptAddStamp() {
    final s = S.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(s['noSavedStamps'], style: const TextStyle(fontSize: 16)),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: s['settings'],
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ),
      );
  }

  Future<void> _placeNote(
    int pageIndex,
    double nx,
    double ny,
    double? widthOverride,
  ) async {
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
    _session?.addPlacement(
      Placement(
        type: PlacementType.note,
        pageIndex: pageIndex,
        nx: nx,
        ny: ny,
        widthFraction: widthOverride ?? _noteWidthFractionFor(pageIndex),
        text: text,
      ),
    );
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
      placed.add(
        Placement(
          type: type,
          pageIndex: page,
          nx: nx,
          ny: ny,
          widthFraction: widthFraction,
          aspectRatio: aspect,
          imageBytes: bytes,
          groupId: gid,
        ),
      );
    }
    _session?.addAll(placed);
    return placed;
  }

  // ── Manage pages (delete / append from image or PDF) ────────────────────────

  Future<void> _managePages() async {
    final session = _session;
    if (session == null || _busy) return;
    final newSession = await Navigator.of(context).push<DocumentSession>(
      MaterialPageRoute(
        builder: (_) => PageManagerScreen(
          session: session,
          renderService: _renderService,
          importService: _importService,
        ),
      ),
    );
    if (newSession == null || !mounted) return;
    session.dispose();
    setState(() => _session = newSession);
  }

  // ── Zoom ──────────────────────────────────────────────────────────────────

  void _zoomBy(double factor) {
    final matrix = _transformation.value;
    final scale = matrix.scale2D;
    final target = (scale * factor).clamp(_minZoomScale, _maxZoomScale);
    if (target == scale) return;
    final f = target / scale;
    final center = Offset(_viewportSize.width / 2, _viewportSize.height / 2);
    final t = matrix.getTranslation();
    final tx = center.dx - (center.dx - t.x) * f;
    final ty = center.dy - (center.dy - t.y) * f;
    final clamped = _clampPan(tx, ty, target);
    _transformation.value = Matrix4.identity()
      ..translateByDouble(clamped.dx, clamped.dy, 0, 1)
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
      ..showSnackBar(
        SnackBar(
          content: Text(s['deleted'], style: const TextStyle(fontSize: 16)),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: s['undo'],
            onPressed: () => session.addAll(removed),
          ),
        ),
      );
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
          ElevatedButton(
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
        unawaited(
          _historyService.record(
            bytes: signedBytes,
            fileName: session.signedFileName,
            pageCount: session.pageCount,
            signed: true,
          ),
        );
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
    await showActionSheet(context, [
      // One-tap save into the folder chosen in Settings — the practical
      // "connect to Drive/OneDrive" the field team asked for, without any
      // account sign-in inside the app.
      if (defaultFolder != null)
        ActionSheetItem(
          icon: Icons.bolt,
          iconColor: DesignTokens.warning,
          iconBg: DesignTokens.warningSoft,
          title: s['saveToDefaultFolder'],
          subtitle: defaultFolder,
          onTap: () async {
            final ok = await _folderService.saveFile(signedBytes, fileName);
            _snack(
              ok
                  ? '${s['savedToDefaultFolder']} — $defaultFolder'
                  : s['exportError'],
            );
          },
        ),
      if (ShareService.canShare)
        ActionSheetItem(
          icon: Icons.share_outlined,
          title: s['share'],
          onTap: () => _shareService.shareBytes(signedBytes, fileName),
        ),
      // System save dialog — Drive / OneDrive / shared folders / device
      // storage. On the web this becomes a browser download.
      ActionSheetItem(
        icon: ShareService.canShare
            ? Icons.drive_folder_upload_outlined
            : Icons.download_outlined,
        title: ShareService.canShare ? s['saveTo'] : s['download'],
        onTap: () async {
          final saved = await _shareService.saveAs(signedBytes, fileName);
          if (saved) _snack(s['copySaved']);
        },
      ),
      ActionSheetItem(
        icon: Icons.print_outlined,
        title: s['print'],
        onTap: () => _printService.printPdf(signedBytes, fileName),
      ),
    ]);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(fontSize: 16)),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final session = _session;
    return Scaffold(
      backgroundColor: DesignTokens.canvasBg,
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRect(
                child: AnimatedSize(
                  duration: _chromeAnimationDuration,
                  curve: Curves.easeInOutCubic,
                  alignment: Alignment.topCenter,
                  child: _chromeVisible
                      ? _buildTopBar(s, session)
                      : const SizedBox(width: double.infinity),
                ),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: session == null
                          ? _buildEmptyState(s)
                          : _buildDocument(),
                    ),
                    if (_dockedToolboxAvailable(context) && _toolboxOpen)
                      ToolboxPanel(
                        onClose: () => setState(() => _toolboxOpen = false),
                        onViewDocument: (bytes, name) {
                          setState(() => _toolboxOpen = false);
                          _openHistoryEntry(bytes, name);
                        },
                      ),
                  ],
                ),
              ),
              ClipRect(
                child: AnimatedSize(
                  duration: _chromeAnimationDuration,
                  curve: Curves.easeInOutCubic,
                  alignment: Alignment.bottomCenter,
                  child: _chromeVisible
                      ? _buildBottomBar(session)
                      : const SizedBox(width: double.infinity),
                ),
              ),
            ],
          ),
          // Web only: shown while a file is dragged over the window.
          if (_isDragActive) _buildDropOverlay(s),
        ],
      ),
    );
  }

  /// Replaces the Scaffold's AppBar so it can collapse to full-screen —
  /// two rows per the hi-fi handoff: logo/name + nav icons, then file name +
  /// current-page pill. Height-animatable, unlike a real AppBar.
  Widget _buildTopBar(S s, DocumentSession? session) {
    return Material(
      color: DesignTokens.surfaceHeader,
      child: SafeArea(
        bottom: false,
        child: DecoratedBox(
          decoration: BoxDecoration(boxShadow: DesignTokens.shadowSm),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _buildLogo(),
                    const SizedBox(width: 9),
                    Text(
                      s['appTitle'],
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: DesignTokens.ink,
                      ),
                    ),
                    const Spacer(),
                    if (session != null)
                      _HeaderIconButton(
                        icon: Icons.post_add_outlined,
                        tooltip: s['managePages'],
                        onTap: _busy ? null : _managePages,
                      ),
                    if (session != null)
                      _HeaderIconButton(
                        icon: Icons.note_add_outlined,
                        tooltip: s['newDocument'],
                        onTap: _busy ? null : _pickAndOpen,
                      ),
                    if (_dockedToolboxAvailable(context))
                      _HeaderIconButton(
                        icon: Icons.dashboard_customize_outlined,
                        tooltip: s['toolbox'],
                        onTap: () =>
                            setState(() => _toolboxOpen = !_toolboxOpen),
                      )
                    else ...[
                      if (HistoryService.isSupported)
                        _HeaderIconButton(
                          icon: Icons.history,
                          tooltip: s['history'],
                          onTap: _busy
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => HistoryScreen(
                                      onView: (bytes, name) {
                                        Navigator.of(context).pop();
                                        _openHistoryEntry(bytes, name);
                                      },
                                    ),
                                  ),
                                ),
                        ),
                      if (FolderLibraryService.isSupported)
                        _HeaderIconButton(
                          icon: Icons.folder_open_outlined,
                          tooltip: s['folderLibrary'],
                          onTap: _busy
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => FolderBrowserScreen(
                                      onOpen: (bytes, name) {
                                        Navigator.of(context).pop();
                                        _openHistoryEntry(bytes, name);
                                      },
                                    ),
                                  ),
                                ),
                        ),
                      _HeaderIconButton(
                        icon: Icons.settings_outlined,
                        tooltip: s['settings'],
                        onTap: _busy
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const SettingsScreen(),
                                ),
                              ),
                      ),
                    ],
                  ],
                ),
                if (session != null) ...[
                  const SizedBox(height: 11),
                  Row(
                    children: [
                      const Icon(
                        Icons.description_outlined,
                        size: 15,
                        color: DesignTokens.textFaint,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          session.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: DesignTokens.textMuted2,
                          ),
                        ),
                      ),
                      if (session.pageCount > 1) ...[
                        const SizedBox(width: 8),
                        ValueListenableBuilder<int>(
                          valueListenable: _currentPageNotifier,
                          builder: (context, page, _) => _PagePill(
                            text:
                                '${s['page']} ${page + 1} / ${session.pageCount}',
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        gradient: DesignTokens.primaryGradient,
        borderRadius: BorderRadius.circular(11),
        boxShadow: [
          BoxShadow(
            color: DesignTokens.primaryDeep.withValues(alpha: 0.45),
            blurRadius: 12,
            offset: const Offset(0, 4),
            spreadRadius: -4,
          ),
        ],
      ),
      child: const Icon(Icons.draw_outlined, color: Colors.white, size: 18),
    );
  }

  Widget _buildBottomBar(DocumentSession? session) {
    return Material(
      color: DesignTokens.surfaceHeader,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: DesignTokens.ink.withValues(alpha: 0.07),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
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
      ),
    );
  }

  Widget _buildDropOverlay(S s) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: 1,
          duration: const Duration(milliseconds: 120),
          child: Container(
            color: scheme.primary.withValues(alpha: 0.12),
            child: Center(
              child: Container(
                margin: const EdgeInsets.all(28),
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 28,
                ),
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: scheme.primary,
                    width: 2,
                    strokeAlign: BorderSide.strokeAlignOutside,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.file_download_outlined,
                      size: 48,
                      color: scheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      s['dropToOpen'],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(S s) {
    if (_busy) return const Center(child: CircularProgressIndicator());
    // Scrollable + height-constrained rather than a bare Center: on a real
    // device (real ad banner, real browser/system chrome eating vertical
    // space — none of which a desktop-sized test viewport reproduces) this
    // content can be taller than the available height. A bare Center lets
    // it silently overflow past the visible area, hiding the "open
    // document" button — the one thing this screen must never hide. Here
    // it either fits centered, or scrolls; it can't be clipped unreachable.
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeOutBack,
                    builder: (context, value, child) => Transform.scale(
                      scale: value.clamp(0.0, 1.0),
                      child: Opacity(
                        opacity: value.clamp(0.0, 1.0),
                        child: child,
                      ),
                    ),
                    child: Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            DesignTokens.primarySoftStrong,
                            DesignTokens.primarySoft,
                          ],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: DesignTokens.primary.withValues(alpha: 0.16),
                            blurRadius: 32,
                            offset: const Offset(0, 12),
                            spreadRadius: -10,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            gradient: DesignTokens.primaryGradient,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: DesignTokens.primaryDeep.withValues(
                                  alpha: 0.35,
                                ),
                                blurRadius: 14,
                                offset: const Offset(0, 5),
                                spreadRadius: -4,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.draw_outlined,
                            size: 26,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    s['emptyTitle'],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      color: DesignTokens.ink,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    s['emptySubtitle'],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      color: DesignTokens.textMuted,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _GradientCta(
                    icon: Icons.file_open_outlined,
                    label: s['openDocument'],
                    onPressed: _pickAndOpen,
                  ),
                  if (ShareService.canShare || kIsWeb) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        if (ShareService.canShare)
                          _HintPill(
                            icon: Icons.ios_share,
                            label: s['shareHint'],
                          ),
                        if (kIsWeb)
                          _HintPill(
                            icon: Icons.file_download_outlined,
                            label: s['dragDropHint'],
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
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
              child: Listener(
                onPointerDown: (event) {
                  if (event.buttons & kMiddleMouseButton != 0) {
                    setState(() => _middleButtonDown = true);
                  }
                },
                onPointerUp: (_) {
                  if (_middleButtonDown) {
                    setState(() => _middleButtonDown = false);
                  }
                },
                onPointerCancel: (_) {
                  if (_middleButtonDown) {
                    setState(() => _middleButtonDown = false);
                  }
                },
                child: MouseRegion(
                  cursor: _middleButtonDown
                      ? SystemMouseCursors.grabbing
                      : _ctrlPressed
                      ? SystemMouseCursors.zoomIn
                      : MouseCursor.defer,
                  child: InteractiveViewer(
                    transformationController: _transformation,
                    constrained: false,
                    minScale: _minZoomScale,
                    maxScale: _maxZoomScale,
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
                                tops,
                                heights,
                                constraints.maxHeight,
                              );
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
                                              onTap: _toggleChrome,
                                            )
                                          : const _PagePlaceholder(),
                                    ),
                                ],
                              );
                            },
                          ),
                          // Live placement preview while long-press marking.
                          if (_markPageIndex != null &&
                              _markCenterN != null &&
                              _markPreviewSizeN != null)
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
              ),
            ),
            // Zoom controls — mouse/keyboard friendly and accessible.
            PositionedDirectional(
              bottom: 18,
              end: 16,
              child: _ZoomControl(
                transformation: _transformation,
                onZoomIn: () => _zoomBy(1.6),
                onZoomOut: () => _zoomBy(1 / 1.6),
              ),
            ),
            // Invisible: keeps the header's page pill (see _buildTopBar) in
            // sync with scroll position — same math the pill used to be
            // drawn with directly, now just feeding a notifier instead.
            if (session.pageCount > 1)
              AnimatedBuilder(
                animation: _transformation,
                builder: (context, _) {
                  final page = _currentPage(
                    tops,
                    heights,
                    constraints.maxHeight,
                  );
                  if (_currentPageNotifier.value != page) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _currentPageNotifier.value = page;
                    });
                  }
                  return const SizedBox.shrink();
                },
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

  /// The translucent placement-preview frame shown while long-pressing —
  /// fixed at the tool's standard size, following the finger so the drop
  /// point can be fine-tuned before release commits it.
  Widget _buildMarkRect(
    double contentWidth,
    List<double> tops,
    List<double> heights,
  ) {
    final page = _markPageIndex!;
    final center = _markCenterN!;
    final sizeN = _markPreviewSizeN!;
    final pageHeight = heights[page];
    final left = (center.dx - sizeN.width / 2).clamp(0.0, 1.0 - sizeN.width);
    final top = (center.dy - sizeN.height / 2).clamp(0.0, 1.0 - sizeN.height);
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      left: _pagePadding + left * contentWidth,
      top: tops[page] + top * pageHeight,
      width: sizeN.width * contentWidth,
      height: sizeN.height * pageHeight,
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
    List<double> tops,
    List<double> heights,
    double viewportHeight,
  ) {
    final matrix = _transformation.value;
    final scale = matrix.scale2D;
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
    List<double> tops,
    List<double> heights,
    double viewportHeight,
  ) {
    final matrix = _transformation.value;
    final scale = matrix.scale2D;
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
/// Cheap stand-in for a not-yet-rendered page (lazy rendering) — a gentle
/// pulse instead of a flat block, so a large document's placeholders read
/// as "loading" rather than "blank/broken" while scrolling past them.
class _PagePlaceholder extends StatefulWidget {
  const _PagePlaceholder();

  @override
  State<_PagePlaceholder> createState() => _PagePlaceholderState();
}

class _PagePlaceholderState extends State<_PagePlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => DecoratedBox(
        decoration: BoxDecoration(
          color: Color.lerp(
            Colors.white,
            scheme.surfaceContainerHighest,
            0.5 + 0.5 * _controller.value,
          ),
        ),
      ),
    );
  }
}

/// One rendered PDF page. Placement starts with a long-press: hold to anchor,
/// drag to mark the area, release to place.
class _PageItem extends StatefulWidget {
  const _PageItem({
    required this.renderService,
    required this.pageIndex,
    required this.width,
    required this.height,
    required this.onMarkStart,
    required this.onMarkUpdate,
    required this.onMarkEnd,
    required this.onTap,
  });

  final PdfRenderService renderService;
  final int pageIndex;
  final double width;
  final double height;
  final void Function(Offset local, Size renderedSize) onMarkStart;
  final void Function(Offset local, Size renderedSize) onMarkUpdate;
  final VoidCallback onMarkEnd;
  final VoidCallback onTap;

  @override
  State<_PageItem> createState() => _PageItemState();
}

class _PageItemState extends State<_PageItem> {
  void _retry() {
    widget.renderService.evictPage(widget.pageIndex);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final size = Size(widget.width, widget.height);
    return GestureDetector(
      onTap: widget.onTap,
      onLongPressStart: (details) =>
          widget.onMarkStart(details.localPosition, size),
      onLongPressMoveUpdate: (details) =>
          widget.onMarkUpdate(details.localPosition, size),
      onLongPressEnd: (_) => widget.onMarkEnd(),
      onLongPressCancel: widget.onMarkEnd,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: DesignTokens.surfacePaper,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: DesignTokens.ink.withValues(alpha: 0.4),
              blurRadius: 40,
              offset: const Offset(0, 18),
              spreadRadius: -18,
            ),
            BoxShadow(
              color: DesignTokens.ink.withValues(alpha: 0.16),
              blurRadius: 12,
              offset: const Offset(0, 4),
              spreadRadius: -4,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: FutureBuilder<Uint8List>(
            future: widget.renderService.renderPage(widget.pageIndex),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: InkWell(
                    onTap: _retry,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.refresh,
                            size: 28,
                            color: DesignTokens.textFaint,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            S.of(context)['pageRenderFailed'],
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              color: DesignTokens.textFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
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
      ),
    );
  }
}

/// Floating zoom control — a single rounded card with +/− stacked and a
/// hairline divider, matching the hi-fi handoff exactly.
class _ZoomControl extends StatelessWidget {
  const _ZoomControl({
    required this.transformation,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final TransformationController transformation;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DesignTokens.surfacePaper,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        boxShadow: DesignTokens.shadowLg,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ZoomIconButton(
              icon: Icons.add,
              label: s['zoomIn'],
              onTap: onZoomIn,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(color: DesignTokens.hairline3),
              child: SizedBox(width: 40, height: 1),
            ),
            AnimatedBuilder(
              animation: transformation,
              builder: (context, _) => SizedBox(
                width: 40,
                height: 28,
                child: Center(
                  child: Text(
                    '${(transformation.value.scale2D * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: DesignTokens.iconStroke2,
                    ),
                  ),
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(color: DesignTokens.hairline3),
              child: SizedBox(width: 40, height: 1),
            ),
            _ZoomIconButton(
              icon: Icons.remove,
              label: s['zoomOut'],
              onTap: onZoomOut,
            ),
          ],
        ),
      ),
    );
  }
}

/// A single button inside [_ZoomControl] — 40dp square, transparent.
class _ZoomIconButton extends StatelessWidget {
  const _ZoomIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 20, color: DesignTokens.iconStroke2),
          ),
        ),
      ),
    );
  }
}

/// Header nav icon — 38dp transparent rounded button.
class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(
              icon,
              size: 21,
              color: onTap == null
                  ? DesignTokens.iconStroke.withValues(alpha: 0.35)
                  : DesignTokens.iconStroke,
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-width gradient primary action for the empty state, matching the
/// bottom toolbar's send button so the "first" and "last" actions in the
/// flow share one visual language.
class _GradientCta extends StatelessWidget {
  const _GradientCta({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: DesignTokens.primaryGradient,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        boxShadow: [
          BoxShadow(
            color: DesignTokens.primaryDeep.withValues(alpha: 0.32),
            blurRadius: 24,
            offset: const Offset(0, 12),
            spreadRadius: -8,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 24, color: Colors.white),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A quiet secondary hint ("or drag a file here") shown as a soft pill
/// instead of bare icon+text floating on the canvas.
class _HintPill extends StatelessWidget {
  const _HintPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DesignTokens.surfaceCard,
        borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
        boxShadow: DesignTokens.shadowSm,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: DesignTokens.textMuted),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: DesignTokens.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The blue "עמוד X / Y" pill in the header's second row.
class _PagePill extends StatelessWidget {
  const _PagePill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DesignTokens.primarySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: DesignTokens.primaryDeep,
          ),
        ),
      ),
    );
  }
}
