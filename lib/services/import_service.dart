import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/document_session.dart';
import 'pdf_render_service.dart';

/// Brings documents into the app (share intent / manual pick) and normalizes
/// everything to a single internal format: PDF.
class ImportService {
  ImportService(this._renderService);

  final PdfRenderService _renderService;

  static const List<String> supportedExtensions = [
    'pdf',
    'jpg',
    'jpeg',
    'png',
  ];

  /// The file shared into the app while it was closed, if any.
  /// Must be called once at startup; resets the native intent afterwards.
  Future<String?> getInitialSharedFile() async {
    final files = await ReceiveSharingIntent.instance.getInitialMedia();
    ReceiveSharingIntent.instance.reset();
    return _firstSupportedPath(files);
  }

  /// Files shared into the app while it is running.
  Stream<String> sharedFileStream() {
    return ReceiveSharingIntent.instance
        .getMediaStream()
        .map(_firstSupportedPath)
        .where((p) => p != null)
        .cast<String>();
  }

  String? _firstSupportedPath(List<SharedMediaFile> files) {
    for (final f in files) {
      if (isSupported(f.path)) return f.path;
    }
    return null;
  }

  /// Manual selection via the system file picker.
  Future<String?> pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: supportedExtensions,
    );
    return result?.files.single.path;
  }

  static bool isSupported(String path) {
    final ext = path.split('.').last.toLowerCase();
    return supportedExtensions.contains(ext);
  }

  /// Opens [path] (PDF or image) and returns a ready [DocumentSession].
  /// Images are wrapped as a single-page PDF so the rest of the app deals
  /// with exactly one format.
  Future<DocumentSession> openDocument(String path) async {
    final pdfPath = await _normalizeToPdf(path);
    final info = await _renderService.open(pdfPath);
    return DocumentSession(
      pdfPath: pdfPath,
      pageCount: info.pageCount,
      pageSizes: info.pageSizes,
    );
  }

  Future<String> _normalizeToPdf(String path) async {
    if (path.split('.').last.toLowerCase() == 'pdf') return path;
    final bytes = await File(path).readAsBytes();
    final pdfBytes = wrapImageAsPdf(bytes);
    final dir = await getTemporaryDirectory();
    final out = File(
      '${dir.path}/import_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await out.writeAsBytes(pdfBytes, flush: true);
    return out.path;
  }

  /// Pure helper: wraps JPG/PNG bytes as a single-page PDF whose page exactly
  /// fits the image (96dpi pixels → 72dpi points).
  static List<int> wrapImageAsPdf(Uint8List imageBytes) {
    final document = PdfDocument();
    try {
      final bitmap = PdfBitmap(imageBytes);
      final width = bitmap.width * 72.0 / 96.0;
      final height = bitmap.height * 72.0 / 96.0;
      document.pageSettings.margins.all = 0;
      // Orientation must match, otherwise syncfusion swaps the dimensions to
      // fit its default portrait orientation.
      document.pageSettings.orientation = width > height
          ? PdfPageOrientation.landscape
          : PdfPageOrientation.portrait;
      document.pageSettings.size = Size(width, height);
      final page = document.pages.add();
      page.graphics.drawImage(
        bitmap,
        Rect.fromLTWH(0, 0, page.getClientSize().width,
            page.getClientSize().height),
      );
      return document.saveSync();
    } finally {
      document.dispose();
    }
  }
}
