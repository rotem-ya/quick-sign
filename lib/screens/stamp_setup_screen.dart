import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/saved_mark.dart';
import '../models/stamp_design.dart';
import '../services/marks_service.dart';
import '../services/stamp_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/transparency_checkerboard.dart';
import 'stamp_designer_screen.dart';

/// Stamp capture: photograph the stamp or pick any image / photographed
/// document, mark the stamp region, the background is removed automatically,
/// preview, save into the marks library.
///
/// Pass [editingMark] to replace an existing stamp's image instead of adding
/// a new one (used from the marks library in Settings). Pops with the
/// resulting [SavedMark] when the user confirms.
class StampSetupScreen extends StatefulWidget {
  const StampSetupScreen({super.key, this.editingMark});

  final SavedMark? editingMark;

  @override
  State<StampSetupScreen> createState() => _StampSetupScreenState();
}

class _StampSetupScreenState extends State<StampSetupScreen> {
  final StampService _service = StampService();
  final MarksService _marksService = MarksService();

  Uint8List? _raw;
  double _rawAspect = 1;
  Rect _crop = const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9);
  Uint8List? _processed;
  StampDesign? _pendingDesign;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final editing = widget.editingMark;
    if (editing != null) {
      // Show the current stamp right away — Retake / Redesign / confirm.
      _processed = editing.imageBytes;
      _pendingDesign = editing.design;
    }
  }

  Future<void> _capture({required bool fromCamera}) async {
    setState(() => _busy = true);
    try {
      final raw = await _service.captureImage(fromCamera: fromCamera);
      if (raw == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final image = await decodeImageFromList(raw);
      final aspect = image.width / image.height;
      image.dispose();
      if (!mounted) return;
      setState(() {
        _raw = raw;
        _rawAspect = aspect;
        _crop = const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9);
        _processed = null;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snackError();
    }
  }

  Future<void> _applyCrop() async {
    final raw = _raw;
    if (raw == null) return;
    setState(() => _busy = true);
    try {
      final processed = await compute(
        StampService.cropAndClean,
        StampCropRequest(
          bytes: raw,
          left: _crop.left,
          top: _crop.top,
          right: _crop.right,
          bottom: _crop.bottom,
        ),
      );
      if (!mounted) return;
      setState(() {
        _processed = processed;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snackError();
    }
  }

  Future<void> _openDesigner() async {
    final result = await Navigator.of(context).push<StampDesignResult>(
      MaterialPageRoute(
        builder: (_) => StampDesignerScreen(initialDesign: _pendingDesign),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _raw = null;
      _processed = result.bytes;
      _pendingDesign = result.design;
    });
  }

  Future<void> _confirm() async {
    final bytes = _processed;
    if (bytes == null) return;
    setState(() => _busy = true);
    final editing = widget.editingMark;
    final SavedMark mark;
    if (editing != null) {
      await _marksService.update(
        editing.id,
        imageBytes: bytes,
        design: _pendingDesign,
        clearDesign: _pendingDesign == null,
      );
      mark = SavedMark(
        id: editing.id,
        type: editing.type,
        name: editing.name,
        imageBytes: bytes,
        design: _pendingDesign,
      );
    } else {
      final existingCount = (await _marksService.list(type: MarkType.stamp))
          .length;
      if (!mounted) return;
      mark = await _marksService.add(
        type: MarkType.stamp,
        name: '${S.of(context)['stamp']} ${existingCount + 1}',
        imageBytes: bytes,
        design: _pendingDesign,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop(mark);
  }

  void _snackError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(S.of(context)['importError'])),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editingMark != null
            ? s['editStampTitle']
            : s['stampSetupTitle']),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: DesignTokens.surfaceMuted,
                    borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                    boxShadow: DesignTokens.shadowSm,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _busy
                      ? const Center(child: CircularProgressIndicator())
                      : _buildPreviewArea(s, scheme),
                ),
              ),
              const SizedBox(height: 16),
              _buildActions(s),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewArea(S s, ColorScheme scheme) {
    if (_processed != null) {
      // Checkerboard, not a solid fill — makes it visually obvious the
      // stamp's background was actually removed, not just painted white.
      return TransparencyCheckerboard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Image.memory(_processed!, fit: BoxFit.contain),
        ),
      );
    }
    if (_raw != null) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Text(
              s['cropHint'],
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 16, color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _CropView(
                imageBytes: _raw!,
                imageAspect: _rawAspect,
                crop: _crop,
                onChanged: (rect) => setState(() => _crop = rect),
              ),
            ),
          ),
        ],
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          s['stampHint'],
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 17, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _buildActions(S s) {
    if (_processed != null) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _processed = null;
                        _pendingDesign = null;
                      }),
              icon: const Icon(Icons.replay),
              label: Text(s['retake']),
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 56)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : _confirm,
              icon: const Icon(Icons.check),
              label: Text(s['useStamp']),
              style: ElevatedButton.styleFrom(minimumSize: const Size(48, 56)),
            ),
          ),
        ],
      );
    }
    if (_raw != null) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => setState(() => _raw = null),
              icon: const Icon(Icons.replay),
              label: Text(s['retake']),
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 56)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : _applyCrop,
              icon: const Icon(Icons.crop),
              label: Text(s['done']),
              style: ElevatedButton.styleFrom(minimumSize: const Size(48, 56)),
            ),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _capture(fromCamera: false),
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(s['fromGallery']),
                style:
                    OutlinedButton.styleFrom(minimumSize: const Size(48, 56)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : () => _capture(fromCamera: true),
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(s['captureStamp']),
                style: ElevatedButton.styleFrom(minimumSize: const Size(48, 56)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _openDesigner,
          icon: const Icon(Icons.design_services_outlined),
          label: Text(s['designStamp']),
          style: OutlinedButton.styleFrom(minimumSize: const Size(48, 56)),
        ),
      ],
    );
  }
}

/// Interactive crop-region selector: drag inside the rect to move it, drag a
/// corner to resize. All coordinates normalized to the displayed image.
class _CropView extends StatefulWidget {
  const _CropView({
    required this.imageBytes,
    required this.imageAspect,
    required this.crop,
    required this.onChanged,
  });

  final Uint8List imageBytes;
  final double imageAspect;
  final Rect crop;
  final ValueChanged<Rect> onChanged;

  @override
  State<_CropView> createState() => _CropViewState();
}

enum _DragMode { none, move, topLeft, topRight, bottomLeft, bottomRight }

class _CropViewState extends State<_CropView> {
  _DragMode _mode = _DragMode.none;

  static const double _cornerHitRadius = 28;
  static const double _minSize = 0.08;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fit-contain display size.
        var w = constraints.maxWidth;
        var h = w / widget.imageAspect;
        if (h > constraints.maxHeight) {
          h = constraints.maxHeight;
          w = h * widget.imageAspect;
        }
        return Center(
          child: SizedBox(
            width: w,
            height: h,
            child: GestureDetector(
              onPanStart: (d) => _onPanStart(d.localPosition, Size(w, h)),
              onPanUpdate: (d) => _onPanUpdate(d.delta, Size(w, h)),
              onPanEnd: (_) => _mode = _DragMode.none,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(widget.imageBytes, fit: BoxFit.fill),
                  CustomPaint(
                    painter: _CropPainter(
                      crop: widget.crop,
                      accent: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _onPanStart(Offset local, Size size) {
    final crop = widget.crop;
    Offset corner(double x, double y) =>
        Offset(x * size.width, y * size.height);
    final corners = {
      _DragMode.topLeft: corner(crop.left, crop.top),
      _DragMode.topRight: corner(crop.right, crop.top),
      _DragMode.bottomLeft: corner(crop.left, crop.bottom),
      _DragMode.bottomRight: corner(crop.right, crop.bottom),
    };
    for (final entry in corners.entries) {
      if ((local - entry.value).distance <= _cornerHitRadius) {
        _mode = entry.key;
        return;
      }
    }
    final rectPx = Rect.fromLTRB(
      crop.left * size.width,
      crop.top * size.height,
      crop.right * size.width,
      crop.bottom * size.height,
    );
    _mode = rectPx.contains(local) ? _DragMode.move : _DragMode.none;
  }

  void _onPanUpdate(Offset delta, Size size) {
    if (_mode == _DragMode.none) return;
    final dx = delta.dx / size.width;
    final dy = delta.dy / size.height;
    var c = widget.crop;
    switch (_mode) {
      case _DragMode.move:
        final shiftX = dx.clamp(-c.left, 1 - c.right);
        final shiftY = dy.clamp(-c.top, 1 - c.bottom);
        c = c.shift(Offset(shiftX, shiftY));
      case _DragMode.topLeft:
        c = Rect.fromLTRB(
          (c.left + dx).clamp(0.0, c.right - _minSize),
          (c.top + dy).clamp(0.0, c.bottom - _minSize),
          c.right,
          c.bottom,
        );
      case _DragMode.topRight:
        c = Rect.fromLTRB(
          c.left,
          (c.top + dy).clamp(0.0, c.bottom - _minSize),
          (c.right + dx).clamp(c.left + _minSize, 1.0),
          c.bottom,
        );
      case _DragMode.bottomLeft:
        c = Rect.fromLTRB(
          (c.left + dx).clamp(0.0, c.right - _minSize),
          c.top,
          c.right,
          (c.bottom + dy).clamp(c.top + _minSize, 1.0),
        );
      case _DragMode.bottomRight:
        c = Rect.fromLTRB(
          c.left,
          c.top,
          (c.right + dx).clamp(c.left + _minSize, 1.0),
          (c.bottom + dy).clamp(c.top + _minSize, 1.0),
        );
      case _DragMode.none:
        return;
    }
    widget.onChanged(c);
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter({required this.crop, required this.accent});

  final Rect crop;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
      crop.left * size.width,
      crop.top * size.height,
      crop.right * size.width,
      crop.bottom * size.height,
    );

    // Dim everything outside the crop rect.
    final scrim = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRect(rect),
    );
    canvas.drawPath(scrim, Paint()..color = const Color(0x88000000));

    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );

    final cornerPaint = Paint()..color = accent;
    const r = 10.0;
    for (final corner in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      canvas.drawCircle(corner, r, cornerPaint);
      canvas.drawCircle(
        corner,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) =>
      oldDelegate.crop != crop || oldDelegate.accent != accent;
}
