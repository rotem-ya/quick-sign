import 'dart:typed_data';
import 'dart:ui';

import 'package:pdfx/pdfx.dart';

class PdfDocumentInfo {
  PdfDocumentInfo({required this.pageCount, required this.pageSizes});

  final int pageCount;

  /// Page sizes in PDF points (72dpi), zero-indexed.
  final List<Size> pageSizes;
}

/// Renders PDF pages to images for on-screen display (pdfx).
///
/// Pages are rendered on demand and cached, so long documents don't blow up
/// memory at open time.
class PdfRenderService {
  PdfDocument? _document;
  List<Size> _pageSizes = const [];
  final Map<int, Future<Uint8List>> _cache = {};

  /// Render scale relative to the page's point size. 2x ≈ 144dpi — crisp on
  /// phones without huge bitmaps. Long documents render lighter because every
  /// page image stays in memory while the document is open.
  static const double renderScale = 2.0;
  static const double lightRenderScale = 1.4;
  static const int lightModePageThreshold = 12;
  static const double maxRenderWidth = 2048;

  double get _effectiveScale => _pageSizes.length > lightModePageThreshold
      ? lightRenderScale
      : renderScale;

  Future<PdfDocumentInfo> open(String path) async {
    await close();
    final doc = await PdfDocument.openFile(path);
    _document = doc;
    final sizes = <Size>[];
    for (var i = 1; i <= doc.pagesCount; i++) {
      final page = await doc.getPage(i);
      sizes.add(Size(page.width, page.height));
      await page.close();
    }
    _pageSizes = sizes;
    return PdfDocumentInfo(pageCount: doc.pagesCount, pageSizes: sizes);
  }

  /// PNG bytes of the zero-indexed [pageIndex].
  Future<Uint8List> renderPage(int pageIndex) {
    return _cache.putIfAbsent(pageIndex, () => _renderPage(pageIndex));
  }

  Future<Uint8List> _renderPage(int pageIndex) async {
    final doc = _document;
    if (doc == null) {
      throw StateError('No document open');
    }
    final size = _pageSizes[pageIndex];
    final width =
        (size.width * _effectiveScale).clamp(1.0, maxRenderWidth).toDouble();
    final height = width * size.height / size.width;
    final page = await doc.getPage(pageIndex + 1);
    try {
      final image = await page.render(
        width: width,
        height: height,
        format: PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
      );
      if (image == null) {
        throw StateError('Failed to render page ${pageIndex + 1}');
      }
      return image.bytes;
    } finally {
      await page.close();
    }
  }

  Future<void> close() async {
    _cache.clear();
    _pageSizes = const [];
    final doc = _document;
    _document = null;
    await doc?.close();
  }
}
