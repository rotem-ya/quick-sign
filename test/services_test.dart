import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'package:quick_sign/models/placement.dart';
import 'package:quick_sign/services/document_metrics.dart';
import 'package:quick_sign/services/export_service.dart';
import 'package:quick_sign/services/import_service.dart';
import 'package:quick_sign/services/stamp_service.dart';

Uint8List _pngOf(int width, int height, img.ColorRgba8 color) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  img.fill(image, color: color);
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('ExportService.rasterizePage', () {
    test('fuses a signature into the page pixels', () async {
      final basePng = _pngOf(400, 600, img.ColorRgba8(255, 255, 255, 255));
      final signature = _pngOf(100, 50, img.ColorRgba8(20, 20, 160, 255));

      final out = await ExportService.rasterizePage(
        basePng: basePng,
        placements: [
          Placement(
            type: PlacementType.signature,
            pageIndex: 0,
            nx: 0.5,
            ny: 0.5,
            widthFraction: 0.5,
            aspectRatio: 2,
            imageBytes: signature,
          ),
        ],
      );

      final decoded = img.decodePng(out)!;
      expect(decoded.width, 400);
      expect(decoded.height, 600);
      // Center pixel is signature ink, corner stays paper-white.
      final center = decoded.getPixel(200, 300);
      expect(center.b, greaterThan(100));
      expect(center.r, lessThan(100));
      final corner = decoded.getPixel(5, 5);
      expect(corner.r, greaterThan(200));
    });

    test('paints note text into the page pixels', () async {
      final basePng = _pngOf(400, 600, img.ColorRgba8(255, 255, 255, 255));

      final out = await ExportService.rasterizePage(
        basePng: basePng,
        placements: [
          Placement(
            type: PlacementType.note,
            pageIndex: 0,
            nx: 0.5,
            ny: 0.5,
            widthFraction: 0.5,
            text: 'אושר לתשלום',
          ),
        ],
      );

      final decoded = img.decodePng(out)!;
      var darkPixels = 0;
      for (final pixel in decoded) {
        if (pixel.r < 100 && pixel.g < 100 && pixel.b < 100) darkPixels++;
      }
      expect(darkPixels, greaterThan(20), reason: 'note glyphs were painted');
    });
  });

  group('ExportService.assembleRasterPdf', () {
    test('builds one image page per input, preserving page size', () {
      final jpeg = Uint8List.fromList(img.encodeJpg(
          img.Image(width: 100, height: 141, numChannels: 3)));

      final bytes = ExportService.assembleRasterPdf(
        pageJpegs: [jpeg, jpeg],
        pageSizes: const [ui.Size(595, 842), ui.Size(842, 595)],
      );

      final doc = PdfDocument(inputBytes: bytes);
      expect(doc.pages.count, 2);
      expect(doc.pages[0].getClientSize().width, closeTo(595, 1));
      expect(doc.pages[0].getClientSize().height, closeTo(842, 1));
      expect(doc.pages[1].getClientSize().width, closeTo(842, 1));
      doc.dispose();
    });
  });

  group('ExportService.noteFontSize', () {
    test('scales with page width and placement width fraction', () {
      expect(ExportService.noteFontSize(1000, 0.5), 20);
      expect(ExportService.noteFontSize(1000, 1.0), 40);
      expect(ExportService.noteFontSize(500, 0.5), 10);
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
      final source = img.Image(width: 100, height: 100, numChannels: 4);
      img.fill(source, color: img.ColorRgba8(255, 255, 255, 255));
      img.fillRect(source,
          x1: 40, y1: 40, x2: 59, y2: 59,
          color: img.ColorRgba8(30, 30, 160, 255));
      final input = Uint8List.fromList(img.encodePng(source));

      final output = img.decodePng(StampService.removeWhiteBackground(input))!;

      expect(output.width, lessThan(40));
      expect(output.height, lessThan(40));

      var transparent = 0;
      var ink = 0;
      for (final pixel in output) {
        if (pixel.a == 0) transparent++;
        if (pixel.a == 255 && pixel.b > 100) ink++;
      }
      expect(ink, 400);
      expect(transparent, output.width * output.height - 400);
    });
  });

  group('ExportService.rasterizePage rotation', () {
    test('rotates the placement around its center', () async {
      final basePng = _pngOf(400, 400, img.ColorRgba8(255, 255, 255, 255));
      // A wide blue bar; rotated 90° it becomes tall.
      final bar = _pngOf(200, 20, img.ColorRgba8(20, 20, 160, 255));

      final placement = Placement(
        type: PlacementType.stamp,
        pageIndex: 0,
        nx: 0.5,
        ny: 0.5,
        widthFraction: 0.5,
        aspectRatio: 10,
        imageBytes: bar,
      )..rotation = 3.14159265 / 2;

      final out = await ExportService.rasterizePage(
        basePng: basePng,
        placements: [placement],
      );
      final decoded = img.decodePng(out)!;
      // Above the center: ink (bar now vertical). Beside the center: paper.
      final above = decoded.getPixel(200, 130);
      expect(above.b, greaterThan(100));
      final beside = decoded.getPixel(130, 200);
      expect(beside.r, greaterThan(200));
    });
  });

  group('StampService.cropAndClean', () {
    test('crops to the marked region before background removal', () {
      // White image with a dark square only in the top-left quadrant.
      final source = img.Image(width: 200, height: 200, numChannels: 4);
      img.fill(source, color: img.ColorRgba8(255, 255, 255, 255));
      img.fillRect(source,
          x1: 20, y1: 20, x2: 59, y2: 59,
          color: img.ColorRgba8(160, 20, 20, 255));
      final bytes = Uint8List.fromList(img.encodePng(source));

      final out = StampService.cropAndClean(StampCropRequest(
        bytes: bytes,
        left: 0,
        top: 0,
        right: 0.5,
        bottom: 0.5,
      ));

      final decoded = img.decodePng(out)!;
      // Content-cropped to the 40px square (plus small margin).
      expect(decoded.width, inInclusiveRange(40, 50));
      expect(decoded.height, inInclusiveRange(40, 50));
    });
  });

  group('DocumentMetrics.medianTextLineHeightPts', () {
    test('measures text height from a generated PDF', () {
      final doc = PdfDocument();
      final page = doc.pages.add();
      final font = PdfStandardFont(PdfFontFamily.helvetica, 12);
      for (var i = 0; i < 5; i++) {
        page.graphics.drawString('Sample body text line $i', font,
            bounds: ui.Rect.fromLTWH(40, 40.0 + i * 20, 400, 16));
      }
      final bytes = Uint8List.fromList(doc.saveSync());
      doc.dispose();

      final height = DocumentMetrics.medianTextLineHeightPts(bytes);
      expect(height, isNotNull);
      expect(height!, inInclusiveRange(8, 20));
    });

    test('returns null for a text-free page', () {
      final doc = PdfDocument();
      doc.pages.add();
      final bytes = Uint8List.fromList(doc.saveSync());
      doc.dispose();
      expect(DocumentMetrics.medianTextLineHeightPts(bytes), isNull);
    });
  });

  group('StampService.compositeSignatureOverStamp', () {
    test('draws the signature centered over the stamp', () async {
      final stamp = _pngOf(200, 100, img.ColorRgba8(200, 40, 40, 255));
      final signature = _pngOf(80, 40, img.ColorRgba8(20, 20, 160, 255));

      final out =
          await StampService.compositeSignatureOverStamp(signature, stamp);
      final decoded = img.decodePng(out)!;

      expect(decoded.width, 200);
      expect(decoded.height, 100);
      // Center is signature ink (blue) over stamp; far edge is stamp red.
      final center = decoded.getPixel(100, 50);
      expect(center.b, greaterThan(100));
      final edge = decoded.getPixel(2, 50);
      expect(edge.r, greaterThan(150));
      expect(edge.b, lessThan(100));
    });
  });
}
