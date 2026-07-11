import 'package:flutter/material.dart';

/// The standard image-editor "transparent" indicator — a light/dark checker
/// grid — so a preview never gets mistaken for "has a white background".
/// Used behind any preview of a stamp/signature PNG, which are always
/// rendered with a fully transparent background.
class TransparencyCheckerboard extends StatelessWidget {
  const TransparencyCheckerboard({super.key, this.child, this.tile = 10});

  final Widget? child;
  final double tile;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CheckerboardPainter(tile: tile),
      child: child,
    );
  }
}

class _CheckerboardPainter extends CustomPainter {
  _CheckerboardPainter({required this.tile});

  final double tile;

  static const _light = Color(0xFFE4E4E4);
  static const _dark = Color(0xFFC7C7C7);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _light);
    final paint = Paint()..color = _dark;
    final cols = (size.width / tile).ceil();
    final rows = (size.height / tile).ceil();
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        if ((row + col).isEven) continue;
        canvas.drawRect(
          Rect.fromLTWH(col * tile, row * tile, tile, tile),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerboardPainter oldDelegate) =>
      oldDelegate.tile != tile;
}
