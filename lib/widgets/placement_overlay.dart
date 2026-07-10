import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/placement.dart';
import '../services/export_service.dart';

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
  static const double _resizeStep = 1.15;
  static const double _rotateStep = math.pi / 12; // 15°

  /// Padding around the content that hosts the handles.
  static const double _handlePad = 22;

  Placement get p => widget.placement;

  double get _zoom => widget.transformation.value.getMaxScaleOnAxis();

  void _onScaleStart(ScaleStartDetails details) {
    _startWidthFraction = p.widthFraction;
    _startRotation = p.rotation;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final delta = details.focalPointDelta / _zoom;
    p.nx = (p.nx + delta.dx / widget.pageRect.width).clamp(0.0, 1.0);
    p.ny = (p.ny + delta.dy / widget.pageRect.height).clamp(0.0, 1.0);
    if (details.pointerCount > 1) {
      p.widthFraction = (_startWidthFraction * details.scale)
          .clamp(_minWidthFraction, _maxWidthFraction);
      p.rotation = _startRotation + details.rotation;
    }
    widget.onChanged();
  }

  void _resize(double factor) {
    p.widthFraction =
        (p.widthFraction * factor).clamp(_minWidthFraction, _maxWidthFraction);
    widget.onChanged();
  }

  void _rotate() {
    p.rotation = (p.rotation + _rotateStep) % (2 * math.pi);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final rect = widget.pageRect;
    final width = p.widthFraction * rect.width;
    final isNote = p.type == PlacementType.note;
    final noteStyle = isNote ? _noteStyle(rect.width) : null;
    final height = isNote
        ? _measureNoteHeight(p.text ?? '', width, noteStyle!)
        : width / p.aspectRatio;
    final cx = rect.left + p.nx * rect.width;
    final cy = rect.top + p.ny * rect.height;
    final scheme = Theme.of(context).colorScheme;

    return Positioned(
      left: cx - width / 2 - _handlePad,
      top: cy - height / 2 - _handlePad,
      width: width + 2 * _handlePad,
      height: height + 2 * _handlePad,
      child: GestureDetector(
        behavior: _selected ? HitTestBehavior.opaque : HitTestBehavior.deferToChild,
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
                      color:
                          _selected ? scheme.primary : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: isNote ? _noteContent(noteStyle!) : _imageContent(),
                ),
              ),
            ),
            if (_selected) ...[
              PositionedDirectional(
                top: 0,
                start: 0,
                child: _Handle(
                  color: scheme.error,
                  icon: Icons.close,
                  label: S.of(context)['deleteItem'],
                  onTap: widget.onDelete,
                ),
              ),
              PositionedDirectional(
                top: 0,
                end: 0,
                child: _Handle(
                  color: scheme.secondary,
                  icon: Icons.rotate_right,
                  label: S.of(context)['rotate'],
                  onTap: _rotate,
                ),
              ),
              if (widget.onEdit != null)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _Handle(
                      color: scheme.tertiary,
                      icon: Icons.edit,
                      label: S.of(context)['editText'],
                      onTap: widget.onEdit!,
                    ),
                  ),
                ),
              PositionedDirectional(
                bottom: 0,
                end: 0,
                child: _Handle(
                  color: scheme.primary,
                  icon: Icons.add,
                  label: S.of(context)['resizeBigger'],
                  onTap: () => _resize(_resizeStep),
                ),
              ),
              PositionedDirectional(
                bottom: 0,
                start: 0,
                child: _Handle(
                  color: scheme.primary,
                  icon: Icons.remove,
                  label: S.of(context)['resizeSmaller'],
                  onTap: () => _resize(1 / _resizeStep),
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

  double _measureNoteHeight(String text, double width, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection:
          ExportService.isRtlText(text) ? TextDirection.rtl : TextDirection.ltr,
    )..layout(minWidth: width, maxWidth: width);
    final height = painter.height;
    painter.dispose();
    return height;
  }
}

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
              padding: const EdgeInsets.all(8),
              child: Icon(icon, size: 20, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
