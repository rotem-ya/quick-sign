import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'package:quick_sign/models/history_entry.dart';
import 'package:quick_sign/models/placement.dart';
import 'package:quick_sign/models/saved_mark.dart';
import 'package:quick_sign/models/stamp_design.dart';
import 'package:quick_sign/screens/stamp_designer_screen.dart';
import 'package:quick_sign/services/document_metrics.dart';
import 'package:quick_sign/services/export_service.dart';
import 'package:quick_sign/services/history_service.dart';
import 'package:quick_sign/services/import_service.dart';
import 'package:quick_sign/services/marks_service.dart';
import 'package:quick_sign/services/stamp_service.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.documentsPath);

  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

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

  group('ImportService.appendBlankPage / appendImagePage', () {
    test('appends a blank page with the same size', () {
      final base = Uint8List.fromList(
          ImportService.wrapImageAsPdf(_pngOf(400, 600, img.ColorRgba8(250, 250, 250, 255))));
      final out = ImportService.appendBlankPage(base);

      final doc = PdfDocument(inputBytes: out);
      expect(doc.pages.count, 2);
      final s0 = doc.pages[0].getClientSize();
      final s1 = doc.pages[1].getClientSize();
      expect(s1.width, closeTo(s0.width, 1));
      expect(s1.height, closeTo(s0.height, 1));
      doc.dispose();
    });

    test('appends an image page sized to the image', () {
      final base = Uint8List.fromList(
          ImportService.wrapImageAsPdf(_pngOf(400, 600, img.ColorRgba8(250, 250, 250, 255))));
      final landscape = _pngOf(800, 400, img.ColorRgba8(30, 90, 200, 255));
      final out = ImportService.appendImagePage(base, landscape);

      final doc = PdfDocument(inputBytes: out);
      expect(doc.pages.count, 2);
      final s1 = doc.pages[1].getClientSize();
      expect(s1.width / s1.height, closeTo(2.0, 0.02));
      doc.dispose();
    });
  });

  group('ImportService.rebuildWithPages', () {
    Uint8List threePagePdf() {
      final sizes = [
        _pngOf(400, 600, img.ColorRgba8(250, 250, 250, 255)),
        _pngOf(800, 400, img.ColorRgba8(30, 90, 200, 255)),
        _pngOf(300, 300, img.ColorRgba8(200, 30, 30, 255)),
      ];
      var bytes = Uint8List.fromList(ImportService.wrapImageAsPdf(sizes[0]));
      bytes = ImportService.appendImagePage(bytes, sizes[1]);
      bytes = ImportService.appendImagePage(bytes, sizes[2]);
      return bytes;
    }

    test('keeps only the requested pages, in order', () {
      final source = threePagePdf();
      final out = ImportService.rebuildWithPages(source, [2, 0]);

      final doc = PdfDocument(inputBytes: out);
      expect(doc.pages.count, 2);
      // Page 0 of the result is original page 2 (square, ~1:1).
      final s0 = doc.pages[0].getClientSize();
      expect(s0.width / s0.height, closeTo(1.0, 0.02));
      // Page 1 of the result is original page 0 (portrait, 400x600).
      final s1 = doc.pages[1].getClientSize();
      expect(s1.width / s1.height, closeTo(400 / 600, 0.02));
      doc.dispose();
    });

    test('dropping all but one page yields a single-page document', () {
      final source = threePagePdf();
      final out = ImportService.rebuildWithPages(source, [1]);

      final doc = PdfDocument(inputBytes: out);
      expect(doc.pages.count, 1);
      final s0 = doc.pages[0].getClientSize();
      expect(s0.width / s0.height, closeTo(2.0, 0.02));
      doc.dispose();
    });
  });

  group('ImportService.mergePdfPages', () {
    test('appends every page of the other PDF, preserving sizes', () {
      final base = Uint8List.fromList(
          ImportService.wrapImageAsPdf(_pngOf(400, 600, img.ColorRgba8(250, 250, 250, 255))));
      var other = Uint8List.fromList(
          ImportService.wrapImageAsPdf(_pngOf(800, 400, img.ColorRgba8(30, 90, 200, 255))));
      other = ImportService.appendImagePage(
          other, _pngOf(300, 300, img.ColorRgba8(200, 30, 30, 255)));

      final out = ImportService.mergePdfPages(base, other);

      final doc = PdfDocument(inputBytes: out);
      expect(doc.pages.count, 3);
      final s1 = doc.pages[1].getClientSize();
      expect(s1.width / s1.height, closeTo(2.0, 0.02));
      final s2 = doc.pages[2].getClientSize();
      expect(s2.width / s2.height, closeTo(1.0, 0.02));
      doc.dispose();
    });
  });

  group('ImportService.appendImagePages', () {
    test('appends each image as its own page, in order', () {
      final base = Uint8List.fromList(
          ImportService.wrapImageAsPdf(_pngOf(400, 600, img.ColorRgba8(250, 250, 250, 255))));
      final out = ImportService.appendImagePages(base, [
        _pngOf(800, 400, img.ColorRgba8(30, 90, 200, 255)),
        _pngOf(300, 300, img.ColorRgba8(200, 30, 30, 255)),
      ]);

      final doc = PdfDocument(inputBytes: out);
      expect(doc.pages.count, 3);
      final s1 = doc.pages[1].getClientSize();
      expect(s1.width / s1.height, closeTo(2.0, 0.02));
      final s2 = doc.pages[2].getClientSize();
      expect(s2.width / s2.height, closeTo(1.0, 0.02));
      doc.dispose();
    });
  });

  group('ImportService.pdfPageCount', () {
    test('reports the number of pages', () {
      final base = Uint8List.fromList(
          ImportService.wrapImageAsPdf(_pngOf(400, 600, img.ColorRgba8(250, 250, 250, 255))));
      final withExtra = ImportService.appendBlankPage(base);
      expect(ImportService.pdfPageCount(base), 1);
      expect(ImportService.pdfPageCount(withExtra), 2);
    });
  });

  group('StampService.removeWhiteBackground (adaptive)', () {
    test('removes a grayish photographed-page background, keeps the stamp',
        () {
      // Gray page background with a blue stamp square.
      final source = img.Image(width: 120, height: 120, numChannels: 4);
      img.fill(source, color: img.ColorRgba8(196, 192, 185, 255));
      img.fillRect(source,
          x1: 40, y1: 40, x2: 79, y2: 79,
          color: img.ColorRgba8(30, 60, 170, 255));
      final input = Uint8List.fromList(img.encodePng(source));

      final output = img.decodePng(StampService.removeWhiteBackground(input))!;

      // Cropped near the stamp, and the gray page is gone.
      expect(output.width, lessThan(60));
      var opaque = 0;
      for (final pixel in output) {
        if (pixel.a > 200) opaque++;
      }
      expect(opaque, greaterThan(1500)); // the 40x40 stamp survived
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

  group('StampDesignerScreen.renderStamp', () {
    Future<int> countOpaquePixels(Uint8List png) async {
      final decoded = img.decodePng(png)!;
      var count = 0;
      for (final pixel in decoded) {
        if (pixel.a > 10) count++;
      }
      return count;
    }

    test('border=none paints no border, only text', () async {
      final png = await StampDesignerScreen.renderStamp(
        lines: ['שם העסק'],
        color: const ui.Color(0xFF1B4C9C),
        shape: StampShape.rectangle,
        border: StampBorder.none,
      );
      final decoded = img.decodePng(png)!;
      // The frame area (near the very edge) must stay fully transparent —
      // no border stroke drawn there.
      final corner = decoded.getPixel(2, 2);
      expect(corner.a, 0);
      // But there is ink somewhere (the text).
      expect(await countOpaquePixels(png), greaterThan(0));
    });

    test('single vs double border draw a different amount of ink', () async {
      final single = await StampDesignerScreen.renderStamp(
        lines: const [],
        color: const ui.Color(0xFF1B4C9C),
        shape: StampShape.rectangle,
        border: StampBorder.single,
      );
      final double_ = await StampDesignerScreen.renderStamp(
        lines: const [],
        color: const ui.Color(0xFF1B4C9C),
        shape: StampShape.rectangle,
        border: StampBorder.double_,
      );
      // Double border draws an extra inner ring, so it has strictly more
      // opaque pixels than a single outer border alone.
      expect(await countOpaquePixels(double_),
          greaterThan(await countOpaquePixels(single)));
      expect(await countOpaquePixels(single), greaterThan(0));
    });

    test('canvas outside the ink is fully transparent — no background fill',
        () async {
      final png = await StampDesignerScreen.renderStamp(
        lines: ['A'],
        color: const ui.Color(0xFF1B4C9C),
        shape: StampShape.rectangle,
        border: StampBorder.double_,
      );
      final decoded = img.decodePng(png)!;
      // Sample a point known to sit between the outer and inner border
      // rings (never touched by either stroke or by the centered text).
      final between = decoded.getPixel(decoded.width ~/ 2, 30);
      expect(between.a, 0);
    });
  });

  group('HistoryEntry.toJson/fromJson', () {
    test('round-trips all fields', () {
      final entry = HistoryEntry(
        id: '123',
        fileName: 'contract-signed.pdf',
        savedAt: DateTime.utc(2026, 1, 15, 10, 30),
        pageCount: 3,
        sizeBytes: 45000,
        filePath: '/tmp/history/123-contract-signed.pdf',
      );
      final restored = HistoryEntry.fromJson(entry.toJson())!;
      expect(restored.id, entry.id);
      expect(restored.fileName, entry.fileName);
      expect(restored.savedAt, entry.savedAt);
      expect(restored.pageCount, entry.pageCount);
      expect(restored.sizeBytes, entry.sizeBytes);
      expect(restored.filePath, entry.filePath);
    });

    test('returns null instead of throwing on malformed data', () {
      expect(HistoryEntry.fromJson({'id': 'only-id'}), isNull);
    });
  });

  group('HistoryService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('quicksign_history_');
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('record → list round-trips a permanent copy, newest first',
        () async {
      final service = HistoryService();
      final first = await service.record(
        bytes: Uint8List.fromList([1, 2, 3]),
        fileName: 'a-signed.pdf',
        pageCount: 1,
      );
      final second = await service.record(
        bytes: Uint8List.fromList([4, 5, 6, 7]),
        fileName: 'b-signed.pdf',
        pageCount: 2,
      );

      final entries = await service.list();
      expect(entries.map((e) => e.id), [second.id, first.id]);
      expect(entries.first.fileName, 'b-signed.pdf');
      expect(entries.first.sizeBytes, 4);
      expect(await File(first.filePath).exists(), isTrue);
    });

    test('readBytes returns exactly what was recorded', () async {
      final service = HistoryService();
      final bytes = Uint8List.fromList(List.generate(50, (i) => i));
      final entry = await service.record(
        bytes: bytes,
        fileName: 'doc.pdf',
        pageCount: 1,
      );
      expect(await service.readBytes(entry), bytes);
    });

    test('delete removes the file and the index entry', () async {
      final service = HistoryService();
      final entry = await service.record(
        bytes: Uint8List.fromList([9, 9, 9]),
        fileName: 'doc.pdf',
        pageCount: 1,
      );
      await service.delete(entry);
      expect(await File(entry.filePath).exists(), isFalse);
      expect(await service.list(), isEmpty);
    });

    test('restore brings a deleted entry back with its bytes', () async {
      final service = HistoryService();
      final bytes = Uint8List.fromList([7, 7, 7]);
      final entry = await service.record(
        bytes: bytes,
        fileName: 'doc.pdf',
        pageCount: 1,
      );
      await service.delete(entry);
      expect(await service.list(), isEmpty);

      await service.restore(entry, bytes);
      final entries = await service.list();
      expect(entries.single.id, entry.id);
      expect(await service.readBytes(entry), bytes);
    });

    test('list prunes entries whose file vanished outside the app',
        () async {
      final service = HistoryService();
      final entry = await service.record(
        bytes: Uint8List.fromList([1]),
        fileName: 'doc.pdf',
        pageCount: 1,
      );
      await File(entry.filePath).delete(); // simulate storage cleared
      expect(await service.list(), isEmpty);
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

  group('StampDesign.toJson/fromJson', () {
    test('round-trips all fields', () {
      final design = StampDesign(
        lines: const ['שורה 1', 'שורה 2'],
        colorValue: const ui.Color(0xFF3355AA).toARGB32(),
        shape: StampShape.ellipse,
        border: StampBorder.double_,
      );
      final restored = StampDesign.fromJson(design.toJson());
      expect(restored, isNotNull);
      expect(restored!.lines, design.lines);
      expect(restored.colorValue, design.colorValue);
      expect(restored.shape, StampShape.ellipse);
      expect(restored.border, StampBorder.double_);
    });

    test('returns null for malformed data', () {
      expect(StampDesign.fromJson(const {'lines': 'not a list'}), isNull);
    });
  });

  group('SavedMark.toJson/fromJson', () {
    test('round-trips a signature (no design)', () {
      final mark = SavedMark(
        id: 'abc123',
        type: MarkType.signature,
        name: 'החתימה שלי',
        imageBytes: _pngOf(40, 20, img.ColorRgba8(0, 0, 0, 255)),
      );
      final restored = SavedMark.fromJson(mark.toJson());
      expect(restored, isNotNull);
      expect(restored!.id, mark.id);
      expect(restored.type, MarkType.signature);
      expect(restored.name, mark.name);
      expect(restored.imageBytes, mark.imageBytes);
      expect(restored.design, isNull);
    });

    test('round-trips a stamp with a design', () {
      final design = StampDesign(
        lines: const ['שם החברה'],
        colorValue: const ui.Color(0xFF117733).toARGB32(),
        shape: StampShape.rectangle,
        border: StampBorder.single,
      );
      final mark = SavedMark(
        id: 'xyz789',
        type: MarkType.stamp,
        name: 'חותמת 1',
        imageBytes: _pngOf(120, 60, img.ColorRgba8(0, 100, 0, 255)),
        design: design,
      );
      final restored = SavedMark.fromJson(mark.toJson());
      expect(restored, isNotNull);
      expect(restored!.type, MarkType.stamp);
      expect(restored.design, isNotNull);
      expect(restored.design!.lines, design.lines);
    });

    test('returns null for malformed data', () {
      expect(SavedMark.fromJson(const {'id': 'a'}), isNull);
    });
  });

  group('MarksService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('add/list/update/delete/restore round-trip', () async {
      final service = MarksService();
      final signatureBytes = _pngOf(40, 20, img.ColorRgba8(0, 0, 0, 255));
      final added = await service.add(
        type: MarkType.signature,
        name: 'חתימה 1',
        imageBytes: signatureBytes,
      );

      var signatures = await service.list(type: MarkType.signature);
      expect(signatures, hasLength(1));
      expect(signatures.single.id, added.id);
      expect(signatures.single.name, 'חתימה 1');

      final newBytes = _pngOf(50, 25, img.ColorRgba8(10, 10, 10, 255));
      await service.update(added.id, name: 'חתימה מעודכנת', imageBytes: newBytes);
      signatures = await service.list(type: MarkType.signature);
      expect(signatures.single.name, 'חתימה מעודכנת');
      expect(signatures.single.imageBytes, newBytes);

      await service.delete(added.id);
      signatures = await service.list(type: MarkType.signature);
      expect(signatures, isEmpty);

      await service.restore(signatures.isEmpty ? added : signatures.single);
      signatures = await service.list(type: MarkType.signature);
      expect(signatures, hasLength(1));
    });

    test('supports multiple signatures and stamps independently', () async {
      final service = MarksService();
      await service.add(
        type: MarkType.signature,
        name: 'חתימה א',
        imageBytes: _pngOf(10, 10, img.ColorRgba8(1, 1, 1, 255)),
      );
      await service.add(
        type: MarkType.signature,
        name: 'חתימה ב',
        imageBytes: _pngOf(10, 10, img.ColorRgba8(2, 2, 2, 255)),
      );
      await service.add(
        type: MarkType.stamp,
        name: 'חותמת א',
        imageBytes: _pngOf(10, 10, img.ColorRgba8(3, 3, 3, 255)),
      );

      final signatures = await service.list(type: MarkType.signature);
      final stamps = await service.list(type: MarkType.stamp);
      expect(signatures, hasLength(2));
      expect(stamps, hasLength(1));

      final all = await service.list();
      expect(all, hasLength(3));
    });

    test('update can clear a design', () async {
      final service = MarksService();
      final design = StampDesign(
        lines: const ['A'],
        colorValue: const ui.Color(0xFF000000).toARGB32(),
        shape: StampShape.rectangle,
        border: StampBorder.none,
      );
      final added = await service.add(
        type: MarkType.stamp,
        name: 'חותמת',
        imageBytes: _pngOf(10, 10, img.ColorRgba8(1, 1, 1, 255)),
        design: design,
      );
      var stamps = await service.list(type: MarkType.stamp);
      expect(stamps.single.design, isNotNull);

      await service.update(added.id,
          imageBytes: _pngOf(10, 10, img.ColorRgba8(2, 2, 2, 255)),
          clearDesign: true);
      stamps = await service.list(type: MarkType.stamp);
      expect(stamps.single.design, isNull);
    });
  });
}
