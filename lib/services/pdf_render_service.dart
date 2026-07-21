import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:pdfx/pdfx.dart';

import 'auth_service.dart';

class PdfDocumentInfo {
  PdfDocumentInfo({required this.pageCount, required this.pageSizes});

  final int pageCount;

  /// Page sizes in PDF points (72dpi), zero-indexed.
  final List<Size> pageSizes;
}

/// Renders PDF pages to images for on-screen display (pdfx — pdfium on
/// mobile/desktop, pdf.js on the web).
///
/// Pages are rendered on demand and cached, so long documents don't blow up
/// memory at open time.
class PdfRenderService {
  PdfDocument? _document;
  List<Size> _pageSizes = const [];
  final Map<int, Future<Uint8List>> _cache = {};

  /// Render scale relative to the page's point size. Long documents render
  /// lighter because every page image stays in memory while the document is
  /// open. [maxRenderWidth] is the real bottleneck for large-format sheets
  /// (e.g. an ANSI-D engineering drawing is ~2448pt wide at 72dpi) — at the
  /// old 2048px cap those pages rendered *below* their native resolution
  /// before any on-screen zoom even happened, which is what made zooming
  /// into fine linework look pixelated rather than just "not sharper".
  static const double renderScale = 3.0;
  static const double lightRenderScale = 1.8;
  static const int lightModePageThreshold = 12;
  static const double maxRenderWidth = 4096;

  double get _effectiveScale => _pageSizes.length > lightModePageThreshold
      ? lightRenderScale
      : renderScale;

  Future<PdfDocumentInfo> open(Uint8List pdfBytes) async {
    await close();
    final doc = await PdfDocument.openData(pdfBytes);
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

  /// How long a single page render may take before we give up and surface
  /// an error instead of leaving the UI on a spinner forever. Rendering
  /// itself is normally well under a second; this is only a backstop for
  /// the underlying platform renderer getting stuck (observed on web: the
  /// pdf.js worker can end up wedged after certain document-switching
  /// sequences and never resolves its render call at all — no exception,
  /// just silence — so a plain try/catch around the render doesn't help).
  static const Duration renderTimeout = Duration(seconds: 12);

  /// PNG bytes of the zero-indexed [pageIndex].
  Future<Uint8List> renderPage(int pageIndex) {
    return _cache.putIfAbsent(pageIndex, () async {
      final sw = Stopwatch()..start();
      try {
        final bytes = await _renderPage(pageIndex).timeout(renderTimeout);
        // Log slow renders so a "not loaded" report has a timing trail.
        if (sw.elapsedMilliseconds > 2500) {
          AuthService.instance.log(
            'Render: page ${pageIndex + 1} slow (${sw.elapsedMilliseconds}ms)',
          );
        }
        return bytes;
      } catch (e) {
        AuthService.instance.log(
          'Render: page ${pageIndex + 1} failed after '
          '${sw.elapsedMilliseconds}ms: $e',
        );
        rethrow;
      }
    });
  }

  /// Drops a page's cached render (including a failed/timed-out one) so
  /// the next [renderPage] call retries from scratch.
  void evictPage(int pageIndex) => _cache.remove(pageIndex);

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
