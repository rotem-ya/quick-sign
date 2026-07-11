import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/document_session.dart';
import 'document_metrics.dart';
import 'pdf_render_service.dart';

/// Brings documents into the app — system share sheet, "Open with…", or the
/// file picker — and normalizes everything to a single internal format: PDF
/// bytes. Byte-based so the same pipeline runs on mobile and web.
class ImportService {
  ImportService(this._renderService);

  final PdfRenderService _renderService;

  static const List<String> supportedExtensions = [
    'pdf',
    'jpg',
    'jpeg',
    'png',
  ];

  /// Channel for ACTION_VIEW intents ("Open with…"), handled natively in
  /// MainActivity. Share-sheet intents come through receive_sharing_intent.
  static const MethodChannel _viewChannel =
      MethodChannel('quick_sign/view_intent');

  /// The file shared into the app while it was closed, if any.
  /// Must be called once at startup; resets the native intent afterwards.
  /// Mobile only — on the web this resolves to null.
  Future<String?> getInitialSharedFile() async {
    if (kIsWeb) return null;
    final files = await ReceiveSharingIntent.instance.getInitialMedia();
    ReceiveSharingIntent.instance.reset();
    final shared = _firstSupportedPath(files);
    if (shared != null) return shared;
    try {
      return await _viewChannel.invokeMethod<String>('getInitialViewFile');
    } catch (_) {
      return null; // iOS / tests: channel not implemented.
    }
  }

  /// Files shared into the app while it is running. Mobile only.
  Stream<String> sharedFileStream() {
    if (kIsWeb) return const Stream.empty();
    return ReceiveSharingIntent.instance
        .getMediaStream()
        .map(_firstSupportedPath)
        .where((p) => p != null)
        .cast<String>();
  }

  /// Registers a callback for files opened via "Open with…" while the app is
  /// already running. Mobile only.
  void setViewFileListener(void Function(String path) onFile) {
    if (kIsWeb) return;
    _viewChannel.setMethodCallHandler((call) async {
      if (call.method == 'viewFile' && call.arguments is String) {
        onFile(call.arguments as String);
      }
    });
  }

  String? _firstSupportedPath(List<SharedMediaFile> files) {
    for (final f in files) {
      if (isSupported(f.path)) return f.path;
    }
    return null;
  }

  static bool isSupported(String path) {
    final ext = path.split('.').last.toLowerCase();
    return supportedExtensions.contains(ext);
  }

  /// Manual selection via the system file picker. Returns a ready session,
  /// or null when the user cancels. Works on mobile and web (bytes-based).
  Future<DocumentSession?> pickAndOpen() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: supportedExtensions,
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return null;
    return openBytes(bytes, fileName: file.name);
  }

  /// Opens a file that arrived as a path (share / "Open with…"). Mobile only.
  Future<DocumentSession> openPath(String path) async {
    final bytes = await File(path).readAsBytes();
    final name = path.split(Platform.pathSeparator).last;
    return openBytes(bytes, fileName: name);
  }

  /// Opens raw file bytes (PDF or image) and returns a ready
  /// [DocumentSession]. Images are wrapped as a single-page PDF so the rest
  /// of the app deals with exactly one format.
  Future<DocumentSession> openBytes(
    Uint8List bytes, {
    required String fileName,
  }) async {
    final ext = fileName.split('.').last.toLowerCase();
    if (!supportedExtensions.contains(ext)) {
      throw const FormatException('Unsupported file type');
    }
    final pdfBytes = ext == 'pdf'
        ? bytes
        : Uint8List.fromList(wrapImageAsPdf(bytes));
    final info = await _renderService.open(pdfBytes);
    final session = DocumentSession(
      pdfBytes: pdfBytes,
      fileName: ext == 'pdf' ? fileName : '$fileName.pdf',
      pageCount: info.pageCount,
      pageSizes: info.pageSizes,
    );
    // Measure the document's text size in the background — placement
    // defaults pick it up once available.
    unawaited(compute(medianTextLineHeightEntry, pdfBytes)
        .then<void>((height) => session.bodyTextHeightPts = height)
        .catchError((_) {}));
    return session;
  }

  /// Pure helper: appends a blank page (sized like the document's last page)
  /// and returns the new PDF bytes.
  static Uint8List appendBlankPage(Uint8List pdfBytes) {
    final document = PdfDocument(inputBytes: pdfBytes);
    try {
      final last = document.pages[document.pages.count - 1];
      // insert() honors an explicit size even on loaded documents (add()
      // falls back to A4 there).
      document.pages
          .insert(document.pages.count, last.size, PdfMargins()..all = 0);
      return Uint8List.fromList(document.saveSync());
    } finally {
      document.dispose();
    }
  }

  /// Pure helper: appends an image as a full-bleed page and returns the new
  /// PDF bytes.
  static Uint8List appendImagePage(Uint8List pdfBytes, Uint8List imageBytes) {
    final document = PdfDocument(inputBytes: pdfBytes);
    try {
      final bitmap = PdfBitmap(imageBytes);
      final width = bitmap.width * 72.0 / 96.0;
      final height = bitmap.height * 72.0 / 96.0;
      final page = document.pages.insert(
          document.pages.count, Size(width, height), PdfMargins()..all = 0);
      page.graphics.drawImage(
        bitmap,
        Rect.fromLTWH(
            0, 0, page.getClientSize().width, page.getClientSize().height),
      );
      return Uint8List.fromList(document.saveSync());
    } finally {
      document.dispose();
    }
  }

  /// Rebuilds a PDF containing only [keepIndices] (0-based), in the given
  /// order. Vector content is preserved via PDF page templates — not
  /// rasterized — so this is the single primitive behind "delete pages" (and
  /// could back reordering later, since the order is caller-controlled).
  static Uint8List rebuildWithPages(Uint8List pdfBytes, List<int> keepIndices) {
    final source = PdfDocument(inputBytes: pdfBytes);
    final target = PdfDocument();
    try {
      // insert() relies on catalog structure only a loaded document has —
      // on a brand-new PdfDocument, add() (driven by pageSettings, like
      // wrapImageAsPdf) is the technique that supports a per-page size.
      target.pageSettings.margins.all = 0;
      for (final index in keepIndices) {
        final sourcePage = source.pages[index];
        final template = sourcePage.createTemplate();
        target.pageSettings.size = sourcePage.size;
        target.pageSettings.orientation = sourcePage.size.width > sourcePage.size.height
            ? PdfPageOrientation.landscape
            : PdfPageOrientation.portrait;
        final newPage = target.pages.add();
        newPage.graphics.drawPdfTemplate(template, Offset.zero, sourcePage.size);
      }
      return Uint8List.fromList(target.saveSync());
    } finally {
      source.dispose();
      target.dispose();
    }
  }

  /// Appends every page of [otherPdfBytes] onto [baseBytes] — merging in
  /// another PDF's pages, preserving their vector content via PDF templates.
  static Uint8List mergePdfPages(Uint8List baseBytes, Uint8List otherPdfBytes) {
    final base = PdfDocument(inputBytes: baseBytes);
    final other = PdfDocument(inputBytes: otherPdfBytes);
    try {
      for (var i = 0; i < other.pages.count; i++) {
        final sourcePage = other.pages[i];
        final template = sourcePage.createTemplate();
        final newPage = base.pages.insert(
            base.pages.count, sourcePage.size, PdfMargins()..all = 0);
        newPage.graphics.drawPdfTemplate(template, Offset.zero, sourcePage.size);
      }
      return Uint8List.fromList(base.saveSync());
    } finally {
      base.dispose();
      other.dispose();
    }
  }

  /// Appends each image in [images] as its own full-bleed page, in order.
  static Uint8List appendImagePages(Uint8List pdfBytes, List<Uint8List> images) {
    var bytes = pdfBytes;
    for (final image in images) {
      bytes = appendImagePage(bytes, image);
    }
    return bytes;
  }

  /// Manual image selection (for "add page from image").
  Future<Uint8List?> pickImageBytes() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png'],
      withData: true,
    );
    return result?.files.single.bytes;
  }

  /// Manual multi-image selection (for "add several pages from images").
  Future<List<Uint8List>> pickImageBytesMultiple() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png'],
      withData: true,
      allowMultiple: true,
    );
    if (result == null) return const [];
    return [for (final f in result.files) if (f.bytes != null) f.bytes!];
  }

  /// Manual PDF selection (for "add pages from another PDF").
  Future<Uint8List?> pickPdfBytes() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    return result?.files.single.bytes;
  }

  /// Page count of arbitrary PDF bytes — cheap (no rendering), used to label
  /// a staged merge before it's actually applied.
  static int pdfPageCount(Uint8List pdfBytes) {
    final document = PdfDocument(inputBytes: pdfBytes);
    try {
      return document.pages.count;
    } finally {
      document.dispose();
    }
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
