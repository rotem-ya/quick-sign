import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Interactive crop-region selector: drag inside the rect to move it, drag a
/// corner to resize. All coordinates normalized to the displayed image.
///
/// Shared between the stamp capture flow (crop a photo/gallery image) and
/// [StampFromPageScreen] (crop a region straight off a rendered PDF page) —
/// same gesture handling either way, just a different source image.
class CropView extends StatefulWidget {
  const CropView({
    super.key,
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
  State<CropView> createState() => _CropViewState();
}

enum _DragMode { none, move, topLeft, topRight, bottomLeft, bottomRight }

class _CropViewState extends State<CropView> {
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
