import 'dart:io';
import 'dart:ui';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/placement.dart';

/// Flattens all placements onto the original PDF and writes the signed copy.
///
/// All math happens in normalized page coordinates (0..1) converted to real
/// PDF points per page, so the result matches what the user saw on screen.
class ExportService {
  static const String fontAsset = 'assets/fonts/Heebo-Regular.ttf';

  /// Note text size as a fraction of the page width. Must match the on-screen
  /// note overlay so the export is WYSIWYG.
  static const double noteFontWidthFraction = 0.03;

  /// Flattens [placements] onto the PDF at [pdfPath] and returns the path of
  /// the signed copy in the temporary directory.
  Future<String> exportSigned({
    required String pdfPath,
    required List<Placement> placements,
  }) async {
    final pdfBytes = await File(pdfPath).readAsBytes();
    final fontBytes = (await rootBundle.load(fontAsset)).buffer.asUint8List();
    final signed = flatten(
      pdfBytes: pdfBytes,
      placements: placements,
      fontBytes: fontBytes,
    );
    final dir = await getTemporaryDirectory();
    final out = File(
      '${dir.path}/signed_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await out.writeAsBytes(signed, flush: true);
    return out.path;
  }

  /// Pure flattening step — kept side-effect free so it is unit-testable.
  static List<int> flatten({
    required List<int> pdfBytes,
    required List<Placement> placements,
    required List<int> fontBytes,
  }) {
    final document = PdfDocument(inputBytes: pdfBytes);
    try {
      for (final placement in placements) {
        if (placement.pageIndex < 0 ||
            placement.pageIndex >= document.pages.count) {
          continue;
        }
        final page = document.pages[placement.pageIndex];
        switch (placement.type) {
          case PlacementType.signature:
          case PlacementType.stamp:
            _drawImage(page, placement);
          case PlacementType.note:
            _drawNote(page, placement, fontBytes);
        }
      }
      return document.saveSync();
    } finally {
      document.dispose();
    }
  }

  static void _drawImage(PdfPage page, Placement placement) {
    final bytes = placement.imageBytes;
    if (bytes == null) return;
    final pageSize = page.getClientSize();
    final bitmap = PdfBitmap(bytes);
    final width = placement.widthFraction * pageSize.width;
    final height = width * bitmap.height / bitmap.width;
    final x = placement.nx * pageSize.width - width / 2;
    final y = placement.ny * pageSize.height - height / 2;
    page.graphics.drawImage(bitmap, Rect.fromLTWH(x, y, width, height));
  }

  static void _drawNote(PdfPage page, Placement placement, List<int> fontBytes) {
    final text = placement.text;
    if (text == null || text.isEmpty) return;
    final pageSize = page.getClientSize();
    final fontSize = noteFontWidthFraction * pageSize.width;
    final font = PdfTrueTypeFont(fontBytes, fontSize);
    final rtl = isRtlText(text);
    final format = PdfStringFormat(
      alignment: rtl ? PdfTextAlignment.right : PdfTextAlignment.left,
      textDirection:
          rtl ? PdfTextDirection.rightToLeft : PdfTextDirection.leftToRight,
      lineAlignment: PdfVerticalAlignment.top,
    );
    final width = placement.widthFraction * pageSize.width;
    final height = _measureNoteHeight(font, text, width, format);
    final x = placement.nx * pageSize.width - width / 2;
    final y = placement.ny * pageSize.height - height / 2;
    page.graphics.drawString(
      text,
      font,
      brush: PdfSolidBrush(PdfColor(20, 20, 20)),
      bounds: Rect.fromLTWH(x, y, width, height),
      format: format,
    );
  }

  static double _measureNoteHeight(
    PdfTrueTypeFont font,
    String text,
    double width,
    PdfStringFormat format,
  ) {
    final size = font.measureString(
      text,
      layoutArea: Size(width, 0),
      format: format,
    );
    // A little slack so the last line is never clipped.
    return size.height + font.height * 0.5;
  }

  /// True when [text] contains Hebrew/Arabic characters.
  static bool isRtlText(String text) =>
      RegExp(r'[֐-׿؀-ۿ]').hasMatch(text);
}
