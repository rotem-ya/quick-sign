import 'package:flutter/material.dart';

import '../models/placement.dart';
import '../services/export_service.dart';

/// A placed signature / stamp / note rendered above the document.
///
/// Lives in a screen-level Stack *above* the page list (not inside it), so its
/// drag / pinch gestures never compete with the list's scroll gestures — the
/// opaque hit test simply swallows the pointer.
///
/// [pageRect] is the on-screen rectangle of the placement's page; all
/// normalized coordinates are resolved against it.
class PlacementOverlay extends StatefulWidget {
  const PlacementOverlay({
    super.key,
    required this.placement,
    required this.pageRect,
    required this.onChanged,
    required this.onDelete,
  });

  final Placement placement;
  final Rect pageRect;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  State<PlacementOverlay> createState() => _PlacementOverlayState();
}

class _PlacementOverlayState extends State<PlacementOverlay> {
  bool _selected = false;
  double _startWidthFraction = 0;

  Placement get p => widget.placement;

  void _onScaleStart(ScaleStartDetails details) {
    _startWidthFraction = p.widthFraction;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    p.nx = (p.nx + details.focalPointDelta.dx / widget.pageRect.width)
        .clamp(0.0, 1.0);
    p.ny = (p.ny + details.focalPointDelta.dy / widget.pageRect.height)
        .clamp(0.0, 1.0);
    if (details.pointerCount > 1) {
      p.widthFraction =
          (_startWidthFraction * details.scale).clamp(0.05, 0.95);
    }
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final rect = widget.pageRect;
    final width = p.widthFraction * rect.width;
    final isNote = p.type == PlacementType.note;
    final noteStyle = isNote ? _noteStyle(rect.width) : null;
    final height = isNote
        ? _measureNoteHeight(context, p.text ?? '', width, noteStyle!)
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
            if (_selected)
              PositionedDirectional(
                top: -14,
                start: -14,
                child: Material(
                  color: Theme.of(context).colorScheme.error,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: widget.onDelete,
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.close, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ),
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
      // Must match ExportService.noteFontWidthFraction for WYSIWYG export.
      fontSize: ExportService.noteFontWidthFraction * pageWidth,
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

  double _measureNoteHeight(
    BuildContext context,
    String text,
    double width,
    TextStyle style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection:
          ExportService.isRtlText(text) ? TextDirection.rtl : TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: width);
    final height = painter.height;
    painter.dispose();
    return height;
  }
}
