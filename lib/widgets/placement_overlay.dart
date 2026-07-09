import 'package:flutter/material.dart';

import '../models/placement.dart';
import '../services/export_service.dart';

/// A placed signature / stamp / note rendered above the document.
///
/// Lives in the same transformed coordinate space as the pages (inside the
/// zoomable document Stack), positioned in document coordinates via
/// [pageRect]. Drag / pinch gestures start on the overlay and win the arena
/// against the InteractiveViewer; drag deltas are divided by the current zoom
/// scale so the overlay tracks the finger 1:1.
///
/// Tap selects the item, showing delete (✕) and resize (+/−) handles.
class PlacementOverlay extends StatefulWidget {
  const PlacementOverlay({
    super.key,
    required this.placement,
    required this.pageRect,
    required this.transformation,
    required this.onChanged,
    required this.onDelete,
  });

  final Placement placement;
  final Rect pageRect;
  final TransformationController transformation;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  State<PlacementOverlay> createState() => _PlacementOverlayState();
}

class _PlacementOverlayState extends State<PlacementOverlay> {
  bool _selected = false;
  double _startWidthFraction = 0;

  static const double _minWidthFraction = 0.05;
  static const double _maxWidthFraction = 0.95;
  static const double _resizeStep = 1.15;

  Placement get p => widget.placement;

  double get _zoom => widget.transformation.value.getMaxScaleOnAxis();

  void _onScaleStart(ScaleStartDetails details) {
    _startWidthFraction = p.widthFraction;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final delta = details.focalPointDelta / _zoom;
    p.nx = (p.nx + delta.dx / widget.pageRect.width).clamp(0.0, 1.0);
    p.ny = (p.ny + delta.dy / widget.pageRect.height).clamp(0.0, 1.0);
    if (details.pointerCount > 1) {
      p.widthFraction = (_startWidthFraction * details.scale)
          .clamp(_minWidthFraction, _maxWidthFraction);
    }
    widget.onChanged();
  }

  void _resize(double factor) {
    p.widthFraction =
        (p.widthFraction * factor).clamp(_minWidthFraction, _maxWidthFraction);
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

    return Positioned(
      left: cx - width / 2,
      top: cy - height / 2,
      width: width,
      height: height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onLongPress: () => setState(() => _selected = true),
        onTap: () => setState(() => _selected = !_selected),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _selected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: isNote ? _noteContent(noteStyle!) : _imageContent(),
              ),
            ),
            if (_selected) ...[
              PositionedDirectional(
                top: -16,
                start: -16,
                child: _Handle(
                  color: Theme.of(context).colorScheme.error,
                  icon: Icons.close,
                  onTap: widget.onDelete,
                ),
              ),
              PositionedDirectional(
                bottom: -16,
                end: -16,
                child: _Handle(
                  color: Theme.of(context).colorScheme.primary,
                  icon: Icons.add,
                  onTap: () => _resize(_resizeStep),
                ),
              ),
              PositionedDirectional(
                bottom: -16,
                start: -16,
                child: _Handle(
                  color: Theme.of(context).colorScheme.primary,
                  icon: Icons.remove,
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
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}
