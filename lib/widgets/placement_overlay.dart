import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/placement.dart';
import '../services/export_service.dart';
import '../theme/design_tokens.dart';
import '../utils/matrix4_scale.dart';

/// A placed signature / stamp / note rendered above the document.
///
/// Lives in the same transformed coordinate space as the pages (inside the
/// zoomable document Stack), positioned in document coordinates via
/// [pageRect].
///
/// Tap selects the item, showing handles: ✕ delete, ⟳ rotate, +/− resize.
/// The handles sit INSIDE the widget's bounds — Flutter does not hit-test
/// children painted outside their parent's rect, so the box is padded and the
/// content inset, keeping every handle tappable.
class PlacementOverlay extends StatefulWidget {
  const PlacementOverlay({
    super.key,
    required this.placement,
    required this.pageRect,
    required this.transformation,
    required this.onChanged,
    required this.onDelete,
    this.onEdit,
  });

  final Placement placement;
  final Rect pageRect;
  final TransformationController transformation;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  /// Present only for text placements — opens the text editor.
  final VoidCallback? onEdit;

  @override
  State<PlacementOverlay> createState() => _PlacementOverlayState();
}

class _PlacementOverlayState extends State<PlacementOverlay> {
  bool _selected = false;
  double _startWidthFraction = 0;
  double _startRotation = 0;

  static const double _minWidthFraction = 0.05;
  static const double _maxWidthFraction = 0.95;
  static const double _rotateStep = math.pi / 12; // 15°

  /// Padding around the content that hosts the handles.
  static const double _handlePad = 22;

  Placement get p => widget.placement;

  double get _zoom => widget.transformation.value.scale2D;

  void _onScaleStart(ScaleStartDetails details) {
    _startWidthFraction = p.widthFraction;
    _startRotation = p.rotation;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final delta = details.focalPointDelta / _zoom;
    p.nx = (p.nx + delta.dx / widget.pageRect.width).clamp(0.0, 1.0);
    p.ny = (p.ny + delta.dy / widget.pageRect.height).clamp(0.0, 1.0);
    if (details.pointerCount > 1) {
      p.widthFraction = (_startWidthFraction * details.scale).clamp(
        _minWidthFraction,
        _maxWidthFraction,
      );
      p.rotation = _startRotation + details.rotation;
    }
    widget.onChanged();
  }

  /// Continuous corner-drag resize — drag outward (down/right) to grow.
  void _onResizeDrag(DragUpdateDetails details) {
    final delta = details.delta / _zoom;
    final widthPx = p.widthFraction * widget.pageRect.width;
    final newWidthPx = widthPx + delta.dx + delta.dy;
    p.widthFraction = (newWidthPx / widget.pageRect.width).clamp(
      _minWidthFraction,
      _maxWidthFraction,
    );
    widget.onChanged();
  }

  void _rotate() {
    p.rotation = (p.rotation + _rotateStep) % (2 * math.pi);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final rect = widget.pageRect;
    final configuredWidth = p.widthFraction * rect.width;
    final isNote = p.type == PlacementType.note;
    final noteStyle = isNote ? _noteStyle(rect.width) : null;
    double width;
    double height;
    if (isNote) {
      final size = _measureNoteSize(p.text ?? '', configuredWidth, noteStyle!);
      width = size.width;
      height = size.height;
    } else {
      width = configuredWidth;
      height = configuredWidth / p.aspectRatio;
    }
    final cx = rect.left + p.nx * rect.width;
    final cy = rect.top + p.ny * rect.height;
    final scheme = Theme.of(context).colorScheme;

    return Positioned(
      left: cx - width / 2 - _handlePad,
      top: cy - height / 2 - _handlePad,
      width: width + 2 * _handlePad,
      height: height + 2 * _handlePad,
      child: GestureDetector(
        behavior: _selected
            ? HitTestBehavior.opaque
            : HitTestBehavior.deferToChild,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onLongPress: () => setState(() => _selected = true),
        onTap: () => setState(() => _selected = !_selected),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: _handlePad,
              top: _handlePad,
              width: width,
              height: height,
              child: Transform.rotate(
                angle: p.rotation,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _selected ? scheme.primary : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: isNote ? _noteContent(noteStyle!) : _imageContent(),
                ),
              ),
            ),
            if (_selected) ...[
              // Dashed selection frame + soft fill, matching the hi-fi
              // handoff, drawn just inside the handle padding.
              Positioned(
                left: _handlePad - 11,
                top: _handlePad - 13,
                width: width + 22,
                height: height + 26,
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _DashedSelectionPainter(
                      color: DesignTokens.primary,
                    ),
                  ),
                ),
              ),
              // Rotate handle — top center, connected to the item by a
              // short line, matching the handoff. Tap rotates 15°; the
              // GestureDetector above already handles two-finger rotation.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Dot(
                        diameter: 15,
                        fillColor: DesignTokens.primary,
                        borderColor: Colors.white,
                        label: S.of(context)['rotate'],
                        onTap: _rotate,
                      ),
                      Container(
                        width: 1.5,
                        height: 11,
                        color: DesignTokens.primary,
                      ),
                    ],
                  ),
                ),
              ),
              // Physical corners (not directional) so the resize handle is
              // always bottom-right — dragging down/right grows, intuitive
              // in both RTL and LTR.
              Positioned(
                top: 0,
                left: 0,
                child: _Handle(
                  color: scheme.error,
                  icon: Icons.close,
                  label: S.of(context)['deleteItem'],
                  onTap: widget.onDelete,
                ),
              ),
              if (widget.onEdit != null)
                Positioned(
                  bottom: 0,
                  left: 0,
                  child: _Handle(
                    color: scheme.tertiary,
                    icon: Icons.edit,
                    label: S.of(context)['editText'],
                    onTap: widget.onEdit!,
                  ),
                ),
              Positioned(
                bottom: -7,
                right: -7,
                child: _Dot(
                  diameter: 15,
                  fillColor: Colors.white,
                  borderColor: DesignTokens.primary,
                  label: S.of(context)['resizeDrag'],
                  onPanUpdate: _onResizeDrag,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _imageContent() {
    return Image.memory(
      p.imageBytes!,
      fit: BoxFit.contain,
      gaplessPlayback: true,
    );
  }

  TextStyle _noteStyle(double pageWidth) {
    return TextStyle(
      // Same family + size formula as the export, so it's WYSIWYG.
      fontFamily: ExportService.noteFontFamily,
      fontSize: ExportService.noteFontSize(pageWidth, p.widthFraction),
      height: 1.2,
      color: const Color(0xFF141414),
    );
  }

  Widget _noteContent(TextStyle style) {
    final text = p.text ?? '';
    final rtl = ExportService.isRtlText(text);
    return Text(
      text,
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      textAlign: rtl ? TextAlign.right : TextAlign.left,
      style: style,
    );
  }

  /// The box hugs the text's actual (single-line, unless it needs to wrap)
  /// width instead of always spanning [maxWidth] — a short note used to
  /// leave a wide, mostly-empty selection frame with the text stuck at one
  /// edge. [maxWidth] still caps it, so long text wraps exactly as before.
  Size _measureNoteSize(String text, double maxWidth, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: ExportService.isRtlText(text)
          ? TextDirection.rtl
          : TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    final size = Size(painter.width, painter.height);
    painter.dispose();
    return size;
  }
}

/// Compact corner handle with a tap action — used for delete/edit, which
/// aren't part of the redesign spec and keep their original, clearly
/// recognizable icon treatment.
class _Handle extends StatelessWidget {
  const _Handle({
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Color color;
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
        child: Material(
          color: color,
          shape: const CircleBorder(),
          elevation: 2,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(icon, size: 16, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

/// Plain colored dot — the resize/rotate handle style from the hi-fi
/// handoff (no icon, just a filled or outlined circle). The visible circle
/// is tiny, but the tap target is padded out to a comfortable size.
class _Dot extends StatelessWidget {
  const _Dot({
    required this.diameter,
    required this.fillColor,
    required this.borderColor,
    required this.label,
    this.onTap,
    this.onPanUpdate,
  });

  final double diameter;
  final Color fillColor;
  final Color borderColor;
  final String label;
  final VoidCallback? onTap;
  final GestureDragUpdateCallback? onPanUpdate;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: fillColor,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: DesignTokens.ink.withValues(alpha: 0.3),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: onPanUpdate == null
              ? GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  child: dot,
                )
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: onPanUpdate,
                  child: dot,
                ),
        ),
      ),
    );
  }
}

/// Dashed rounded-rect outline + soft fill — the selection frame from the
/// hi-fi handoff. Flutter has no built-in dashed border, so this walks the
/// perimeter drawing short strokes.
class _DashedSelectionPainter extends CustomPainter {
  const _DashedSelectionPainter({required this.color});

  final Color color;

  static const double _dash = 5;
  static const double _gap = 4;
  static const double _radius = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(_radius),
    );
    canvas.drawRRect(rrect, Paint()..color = color.withValues(alpha: 0.05));

    final path = Path()..addRRect(rrect);
    final dashed = Path();
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + _dash, metric.length);
        dashed.addPath(metric.extractPath(distance, next), Offset.zero);
        distance = next + _gap;
      }
    }
    canvas.drawPath(
      dashed,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _DashedSelectionPainter oldDelegate) =>
      oldDelegate.color != color;
}
