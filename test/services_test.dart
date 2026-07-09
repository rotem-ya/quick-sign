import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'package:quick_sign/models/placement.dart';
import 'package:quick_sign/services/export_service.dart';
import 'package:quick_sign/services/import_service.dart';
import 'package:quick_sign/services/stamp_service.dart';

Uint8List _pngOf(int width, int height, img.ColorRgba8 color) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  img.fill(image, color: color);
  return Uint8List.fromList(img.encodePng(image));
}

List<int> _blankPdf({double width = 595, double height = 842}) {
  final doc = PdfDocument();
  doc.pageSettings.margins.all = 0;
  doc.pageSettings.size = Size(width, height);
  doc.pages.add();
  final bytes = doc.saveSync();
  doc.dispose();
  return bytes;
}

void main() {
  final fontBytes = File('assets/fonts/Heebo-Regular.ttf').readAsBytesSync();

  group('ImportService.wrapImageAsPdf', () {
    test('wraps an image as a single-page PDF matching the image aspect', () {
      final png = _pngOf(960, 480, img.ColorRgba8(200, 30, 30, 255));
      final pdfBytes = ImportService.wrapImageAsPdf(png);

      final doc = PdfDocument(inputBytes: pdfBytes);
      expect(doc.pages.count, 1);
      final size = doc.pages[0].getClientSize();
      expect(size.width / size.height, closeTo(2.0, 0.01));
      doc.dispose();
    });
  });

  group('ExportService.flatten', () {
    test('draws an image placement without corrupting the PDF', () {
      final signature = _pngOf(300, 150, img.ColorRgba8(20, 20, 120, 255));
      final placement = Placement(
        type: PlacementType.signature,
        pageIndex: 0,
        nx: 0.5,
        ny: 0.75,
        widthFraction: 0.3,
        imageBytes: signature,
      );

      final out = ExportService.flatten(
        pdfBytes: _blankPdf(),
        placements: [placement],
        fontBytes: fontBytes,
      );

      final reloaded = PdfDocument(inputBytes: out);
      expect(reloaded.pages.count, 1);
      reloaded.dispose();
    });

    test('draws a Hebrew note with the embedded font', () {
      final placement = Placement(
        type: PlacementType.note,
        pageIndex: 0,
        nx: 0.5,
        ny: 0.9,
        widthFraction: 0.5,
        text: 'אושר על ידי — 9.7.2026',
      );

      final out = ExportService.flatten(
        pdfBytes: _blankPdf(),
        placements: [placement],
        fontBytes: fontBytes,
      );

      final reloaded = PdfDocument(inputBytes: out);
      expect(reloaded.pages.count, 1);
      reloaded.dispose();
    });

    test('ignores placements pointing at nonexistent pages', () {
      final placement = Placement(
        type: PlacementType.note,
        pageIndex: 7,
        nx: 0.5,
        ny: 0.5,
        text: 'off the map',
      );

      final out = ExportService.flatten(
        pdfBytes: _blankPdf(),
        placements: [placement],
        fontBytes: fontBytes,
      );
      expect(out, isNotEmpty);
    });
  });

  group('ExportService.isRtlText', () {
    test('detects Hebrew', () {
      expect(ExportService.isRtlText('שלום'), isTrue);
      expect(ExportService.isRtlText('hello'), isFalse);
      expect(ExportService.isRtlText('note 42'), isFalse);
    });
  });

  group('StampService.removeWhiteBackground', () {
    test('turns white pixels transparent and keeps ink', () {
      // Dark square in the middle of a white image.
      final source = img.Image(width: 100, height: 100, numChannels: 4);
      img.fill(source, color: img.ColorRgba8(255, 255, 255, 255));
      img.fillRect(source,
          x1: 40, y1: 40, x2: 59, y2: 59,
          color: img.ColorRgba8(30, 30, 160, 255));
      final input = Uint8List.fromList(img.encodePng(source));

      final output = img.decodePng(StampService.removeWhiteBackground(input))!;

      // Cropped to the ink bounding box (plus a small margin).
      expect(output.width, lessThan(40));
      expect(output.height, lessThan(40));

      var transparent = 0;
      var ink = 0;
      for (final pixel in output) {
        if (pixel.a == 0) transparent++;
        if (pixel.a == 255 && pixel.b > 100) ink++;
      }
      expect(ink, 400); // the 20x20 square survived
      expect(transparent, output.width * output.height - 400);
    });
  });
}
