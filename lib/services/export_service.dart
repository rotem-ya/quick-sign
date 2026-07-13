import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/document_session.dart';
import '../models/placement.dart';
import 'pdf_render_service.dart';

/// Produces the signed PDF by **rasterizing** every page: the page is rendered
/// to an image, all placements are painted onto it, and the flat image becomes
/// the page of the output PDF.
///
/// This makes signatures, stamps and notes an inseparable part of the page —
/// nothing can be selected, copied or extracted from the exported document.
class ExportService {
  /// Note text size relative to the page width, scaled by the placement's
  /// widthFraction (default 0.5 → 2% of the page width, roughly like body
  /// text). The on-screen overlay uses the same formula, so what you see is
  /// what gets exported.
  static double noteFontSize(double pageWidth, double widthFraction) =>
      0.04 * widthFraction * pageWidth;

  static const String noteFontFamily = 'Heebo';
  static const int jpegQuality = 88;

  /// Renders and flattens the signed document; returns the PDF bytes.
  Future<Uint8List> exportSigned({
    required DocumentSession session,
    required PdfRenderService renderService,
  }) async {
    final byPage = <int, List<Placement>>{};
    for (final p in session.placements.value) {
      byPage.putIfAbsent(p.pageIndex, () => []).add(p);
    }

    final pageJpegs = <Uint8List>[];
    for (var i = 0; i < session.pageCount; i++) {
      final basePng = await renderService.renderPage(i);
      final flatPng = await rasterizePage(
        basePng: basePng,
        placements: byPage[i] ?? const [],
      );
      pageJpegs.add(await compute(_pngToJpeg, flatPng));
    }

    return Uint8List.fromList(assembleRasterPdf(
      pageJpegs: pageJpegs,
      pageSizes: session.pageSizes,
    ));
  }

  /// Paints [placements] onto the rendered page image. Returns PNG bytes.
  static Future<Uint8List> rasterizePage({
    required Uint8List basePng,
    required List<Placement> placements,
  }) async {
    final base = await _decodeUiImage(basePng);
    final w = base.width.toDouble();
    final h = base.height.toDouble();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.high;
    canvas.drawImage(base, ui.Offset.zero, paint);

    for (final placement in placements) {
      canvas.save();
      // Rotate the canvas around the placement center so images and notes
      // land exactly like their on-screen overlay.
      canvas.translate(placement.nx * w, placement.ny * h);
      canvas.rotate(placement.rotation);
      switch (placement.type) {
        case PlacementType.signature:
        case PlacementType.stamp:
          final bytes = placement.imageBytes;
          if (bytes == null) break;
          final image = await _decodeUiImage(bytes);
          final width = placement.widthFraction * w;
          final height = width * image.height / image.width;
          canvas.drawImageRect(
            image,
            ui.Rect.fromLTWH(
                0, 0, image.width.toDouble(), image.height.toDouble()),
            ui.Rect.fromCenter(
                center: ui.Offset.zero, width: width, height: height),
            paint,
          );
          image.dispose();
        case PlacementType.note:
          _paintNote(canvas, placement, w);
      }
      canvas.restore();
    }

    final picture = recorder.endRecording();
    final flat = await picture.toImage(base.width, base.height);
    base.dispose();
    picture.dispose();
    final data = await flat.toByteData(format: ui.ImageByteFormat.png);
    flat.dispose();
    return data!.buffer.asUint8List();
  }

  /// Paints the note centered on the canvas origin (the canvas is already
  /// translated to the placement center and rotated). Matches the on-screen
  /// overlay exactly: the box hugs the text's actual width (capped at
  /// [maxWidth], so long text still wraps) instead of always spanning the
  /// full configured width — otherwise short notes paint with a lot of
  /// empty space on one side.
  static void _paintNote(ui.Canvas canvas, Placement placement, double w) {
    final text = placement.text;
    if (text == null || text.isEmpty) return;
    final rtl = isRtlText(text);
    final maxWidth = placement.widthFraction * w;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: noteFontFamily,
          fontSize: noteFontSize(w, placement.widthFraction),
          height: 1.2,
          color: const ui.Color(0xFF141414),
        ),
      ),
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      textAlign: rtl ? TextAlign.right : TextAlign.left,
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, ui.Offset(-painter.width / 2, -painter.height / 2));
    painter.dispose();
  }

  /// Builds the output PDF: one full-bleed image page per input page, sized
  /// exactly like the original pages (in PDF points).
  static List<int> assembleRasterPdf({
    required List<Uint8List> pageJpegs,
    required List<ui.Size> pageSizes,
  }) {
    final document = PdfDocument();
    try {
      document.pageSettings.margins.all = 0;
      for (var i = 0; i < pageJpegs.length; i++) {
        final size = pageSizes[i];
        final section = document.sections!.add();
        section.pageSettings.margins.all = 0;
        section.pageSettings.orientation = size.width > size.height
            ? PdfPageOrientation.landscape
            : PdfPageOrientation.portrait;
        section.pageSettings.size = ui.Size(size.width, size.height);
        final page = section.pages.add();
        page.graphics.drawImage(
          PdfBitmap(pageJpegs[i]),
          ui.Rect.fromLTWH(0, 0, page.getClientSize().width,
              page.getClientSize().height),
        );
      }
      return document.saveSync();
    } finally {
      document.dispose();
    }
  }

  static Future<ui.Image> _decodeUiImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  /// True when [text] contains Hebrew/Arabic characters.
  static bool isRtlText(String text) => RegExp(r'[֐-׿؀-ۿ]').hasMatch(text);
}

/// Isolate entry: transcode the flattened PNG page to JPEG to keep the output
/// PDF small.
Uint8List _pngToJpeg(Uint8List png) {
  final decoded = img.decodePng(png)!;
  // White background under any remaining transparency.
  final flat = img.Image(
      width: decoded.width, height: decoded.height, numChannels: 3);
  img.fill(flat, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(flat, decoded);
  return Uint8List.fromList(
      img.encodeJpg(flat, quality: ExportService.jpegQuality));
}
