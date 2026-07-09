import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Measures the document's own typography so placements can default to sizes
/// proportional to the writing on the page.
class DocumentMetrics {
  /// Median text-line height in PDF points, or null when the document has no
  /// extractable text. Bounds are filtered to plausible body-text heights so
  /// headlines and page-number artifacts don't skew the result.
  static double? medianTextLineHeightPts(Uint8List pdfBytes) {
    PdfDocument? document;
    try {
      document = PdfDocument(inputBytes: pdfBytes);
      final lines = PdfTextExtractor(document).extractTextLines();
      final heights = <double>[
        for (final line in lines)
          if (line.text.trim().length > 1 &&
              line.bounds.height > 4 &&
              line.bounds.height < 60)
            line.bounds.height,
      ]..sort();
      if (heights.isEmpty) return null;
      return heights[heights.length ~/ 2];
    } catch (_) {
      return null;
    } finally {
      document?.dispose();
    }
  }
}

/// Isolate entry for `compute`.
double? medianTextLineHeightEntry(Uint8List pdfBytes) =>
    DocumentMetrics.medianTextLineHeightPts(pdfBytes);
