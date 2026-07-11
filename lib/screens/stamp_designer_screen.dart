import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../widgets/transparency_checkerboard.dart';

/// Built-in digital stamp designer: a classic editable template — up to three
/// text lines, an optional border (none / single / double), in traditional
/// stamp ink colors.
///
/// Pops with a transparent PNG of the rendered stamp — the canvas is never
/// filled, so there is no background of any color, not even white.
class StampDesignerScreen extends StatefulWidget {
  const StampDesignerScreen({super.key});

  @override
  State<StampDesignerScreen> createState() => _StampDesignerScreenState();

  /// Renders the stamp to a transparent PNG (1200px wide). The canvas is
  /// never filled with any color, so every pixel outside the ink strokes and
  /// glyphs stays fully transparent — public and pure, so it's directly
  /// testable without pumping a widget tree.
  static Future<Uint8List> renderStamp({
    required List<String> lines,
    required Color color,
    required StampShape shape,
    required StampBorder border,
  }) async {
    const width = 1200.0;
    const height = 500.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    _StampDesignerScreenState._paintStamp(
        canvas, const Size(width, height), lines, color, shape, border);
    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }
}

enum StampShape { rectangle, ellipse }

enum StampBorder { none, single, double_ }

class _StampDesignerScreenState extends State<StampDesignerScreen> {
  final _line1 = TextEditingController();
  final _line2 = TextEditingController();
  final _line3 = TextEditingController();

  static const _inkColors = <Color>[
    Color(0xFF1B4C9C), // classic blue
    Color(0xFFB3261E), // red
    Color(0xFF1E6B3C), // green
    Color(0xFF202124), // black
  ];

  Color _color = _inkColors.first;
  StampShape _shape = StampShape.rectangle;
  StampBorder _border = StampBorder.double_;

  @override
  void dispose() {
    _line1.dispose();
    _line2.dispose();
    _line3.dispose();
    super.dispose();
  }

  List<String> get _lines => [
        for (final c in [_line1, _line2, _line3])
          if (c.text.trim().isNotEmpty) c.text.trim(),
      ];

  Future<void> _save() async {
    final bytes = await StampDesignerScreen.renderStamp(
      lines: _lines,
      color: _color,
      shape: _shape,
      border: _border,
    );
    if (!mounted) return;
    Navigator.of(context).pop(bytes);
  }

  static void _paintStamp(
    Canvas canvas,
    Size size,
    List<String> lines,
    Color color,
    StampShape shape,
    StampBorder border,
  ) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = color
      ..strokeWidth = size.height * 0.028;
    final thin = Paint()
      ..style = PaintingStyle.stroke
      ..color = color
      ..strokeWidth = size.height * 0.012;

    final outer = Rect.fromLTWH(
      stroke.strokeWidth,
      stroke.strokeWidth,
      size.width - 2 * stroke.strokeWidth,
      size.height - 2 * stroke.strokeWidth,
    );
    final inner = outer.deflate(size.height * 0.055);
    // Text still lays out inside where the inner border would sit, whether
    // or not it's actually drawn, so the layout stays stable across border
    // styles as the user switches between them.
    final textBounds = border == StampBorder.none ? outer.deflate(size.height * 0.04) : inner;

    if (border != StampBorder.none) {
      switch (shape) {
        case StampShape.rectangle:
          final r = Radius.circular(size.height * 0.12);
          canvas.drawRRect(RRect.fromRectAndRadius(outer, r), stroke);
          if (border == StampBorder.double_) {
            canvas.drawRRect(
                RRect.fromRectAndRadius(inner, Radius.circular(r.x * 0.8)),
                thin);
          }
        case StampShape.ellipse:
          canvas.drawOval(outer, stroke);
          if (border == StampBorder.double_) {
            canvas.drawOval(inner, thin);
          }
      }
    }

    if (lines.isEmpty) return;
    // First line is the headline — bigger and bold.
    final sizes = switch (lines.length) {
      1 => [0.30],
      2 => [0.24, 0.16],
      _ => [0.20, 0.13, 0.13],
    };
    final painters = <TextPainter>[];
    for (var i = 0; i < lines.length; i++) {
      painters.add(TextPainter(
        text: TextSpan(
          text: lines[i],
          style: TextStyle(
            fontFamily: 'Heebo',
            fontSize: size.height * sizes[i],
            fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w500,
            color: color,
          ),
        ),
        textDirection: TextDirection.rtl,
        textAlign: TextAlign.center,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: textBounds.width * 0.86));
    }
    const gapFactor = 0.035;
    final totalHeight = painters.fold<double>(0, (sum, p) => sum + p.height) +
        (painters.length - 1) * size.height * gapFactor;
    var y = size.height / 2 - totalHeight / 2;
    for (final painter in painters) {
      painter.paint(
          canvas, Offset(size.width / 2 - painter.width / 2, y));
      y += painter.height + size.height * gapFactor;
      painter.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(s['stampDesignerTitle'])),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Live preview — a checkerboard, not a solid color, so it's
            // visually obvious the stamp has no background at all.
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                height: 150,
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: TransparencyCheckerboard(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: CustomPaint(
                      painter: _StampPreviewPainter(
                        lines: _lines,
                        color: _color,
                        shape: _shape,
                        border: _border,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _line1,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                labelText: s['businessName'],
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _line2,
              style: const TextStyle(fontSize: 17),
              decoration: InputDecoration(
                labelText: s['line2'],
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _line3,
              style: const TextStyle(fontSize: 17),
              decoration: InputDecoration(
                labelText: s['line3'],
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Text('${s['color']}:',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(width: 10),
                for (final color in _inkColors)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => setState(() => _color = color),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _color == color
                                ? scheme.primary
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                        child: _color == color
                            ? const Icon(Icons.check,
                                color: Colors.white, size: 20)
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('${s['borderStyle']}:',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<StampBorder>(
              segments: [
                ButtonSegment(
                  value: StampBorder.none,
                  icon: const Icon(Icons.crop_free),
                  label: Text(s['borderNone']),
                ),
                ButtonSegment(
                  value: StampBorder.single,
                  icon: const Icon(Icons.rectangle_outlined),
                  label: Text(s['borderSingle']),
                ),
                ButtonSegment(
                  value: StampBorder.double_,
                  icon: const Icon(Icons.filter_none),
                  label: Text(s['borderDouble']),
                ),
              ],
              selected: {_border},
              onSelectionChanged: (v) => setState(() => _border = v.first),
            ),
            if (_border != StampBorder.none) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Text('${s['shape']}:',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 10),
                  SegmentedButton<StampShape>(
                    segments: [
                      ButtonSegment(
                        value: StampShape.rectangle,
                        icon: const Icon(Icons.crop_16_9),
                        label: Text(s['shapeRect']),
                      ),
                      ButtonSegment(
                        value: StampShape.ellipse,
                        icon: const Icon(Icons.circle_outlined),
                        label: Text(s['shapeEllipse']),
                      ),
                    ],
                    selected: {_shape},
                    onSelectionChanged: (v) =>
                        setState(() => _shape = v.first),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _lines.isEmpty ? null : _save,
              icon: const Icon(Icons.check),
              label: Text(s['useStamp'], style: const TextStyle(fontSize: 17)),
              style: FilledButton.styleFrom(minimumSize: const Size(48, 56)),
            ),
          ],
        ),
      ),
    );
  }
}

class _StampPreviewPainter extends CustomPainter {
  _StampPreviewPainter({
    required this.lines,
    required this.color,
    required this.shape,
    required this.border,
  });

  final List<String> lines;
  final Color color;
  final StampShape shape;
  final StampBorder border;

  @override
  void paint(Canvas canvas, Size size) {
    // Preview at the same 2.4:1 aspect the render uses, centered.
    var w = size.width;
    var h = w / 2.4;
    if (h > size.height) {
      h = size.height;
      w = h * 2.4;
    }
    canvas.save();
    canvas.translate((size.width - w) / 2, (size.height - h) / 2);
    _StampDesignerScreenState._paintStamp(
        canvas, Size(w, h), lines, color, shape, border);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StampPreviewPainter old) =>
      !listEquals(old.lines, lines) ||
      old.color != color ||
      old.shape != shape ||
      old.border != border;
}
