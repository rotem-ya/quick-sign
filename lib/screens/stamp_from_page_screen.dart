import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/stamp_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/crop_view.dart';

/// Browses a PDF's pages and crops a stamp out of one of them — the
/// selection rectangle itself decides whether a nearby signature comes
/// along with it or not, there's no separate toggle for that. Pops with
/// the cropped, background-cleaned PNG bytes, same shape as the camera/
/// gallery capture flow in [StampSetupScreen] produces.
///
/// [pageBytesLoader] is supplied by the caller so this screen works both
/// for a freshly-picked PDF file (a throwaway PdfRenderService) and for the
/// document already open in the work screen (its existing renderer, so the
/// current page doesn't get re-rendered from scratch).
class StampFromPageScreen extends StatefulWidget {
  const StampFromPageScreen({
    super.key,
    required this.pageCount,
    required this.initialPageIndex,
    required this.pageBytesLoader,
  });

  final int pageCount;
  final int initialPageIndex;
  final Future<Uint8List> Function(int pageIndex) pageBytesLoader;

  @override
  State<StampFromPageScreen> createState() => _StampFromPageScreenState();
}

class _StampFromPageScreenState extends State<StampFromPageScreen> {
  late int _pageIndex = widget.initialPageIndex;
  Uint8List? _pageBytes;
  double _pageAspect = 1;
  Rect _crop = const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9);
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  Future<void> _loadPage() async {
    setState(() => _loading = true);
    try {
      final bytes = await widget.pageBytesLoader(_pageIndex);
      final image = await decodeImageFromList(bytes);
      final aspect = image.width / image.height;
      image.dispose();
      if (!mounted) return;
      setState(() {
        _pageBytes = bytes;
        _pageAspect = aspect;
        _crop = const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snackError();
    }
  }

  void _goToPage(int index) {
    if (index < 0 || index >= widget.pageCount || index == _pageIndex) return;
    setState(() => _pageIndex = index);
    _loadPage();
  }

  Future<void> _confirm() async {
    final bytes = _pageBytes;
    if (bytes == null) return;
    setState(() => _busy = true);
    try {
      final processed = await compute(
        StampService.cropAndClean,
        StampCropRequest(
          bytes: bytes,
          left: _crop.left,
          top: _crop.top,
          right: _crop.right,
          bottom: _crop.bottom,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(processed);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snackError();
    }
  }

  void _snackError() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(S.of(context)['importError'])));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(s['stampFromPageTitle']),
        actions: [
          if (widget.pageCount > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                // A pure digits-and-slash string has no strong-direction
                // character to anchor it, so under the app's RTL base
                // direction it can visually reorder ("3 / 1" instead of
                // "1 / 3") — force LTR explicitly, like a fraction always
                // reads regardless of the surrounding language.
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    '${_pageIndex + 1} / ${widget.pageCount}',
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                s['cropHint'],
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: DesignTokens.surfaceMuted,
                    borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                    boxShadow: DesignTokens.shadowSm,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _loading || _pageBytes == null
                      ? const Center(child: CircularProgressIndicator())
                      : Padding(
                          padding: const EdgeInsets.all(12),
                          child: CropView(
                            imageBytes: _pageBytes!,
                            imageAspect: _pageAspect,
                            crop: _crop,
                            onChanged: (rect) => setState(() => _crop = rect),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (widget.pageCount > 1) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _loading || _pageIndex == 0
                            ? null
                            : () => _goToPage(_pageIndex - 1),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 56),
                        ),
                        child: Text(s['previousPage']),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _loading || _pageIndex >= widget.pageCount - 1
                            ? null
                            : () => _goToPage(_pageIndex + 1),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 56),
                        ),
                        child: Text(s['nextPage']),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    flex: widget.pageCount > 1 ? 2 : 1,
                    child: ElevatedButton.icon(
                      onPressed: _busy || _loading ? null : _confirm,
                      icon: const Icon(Icons.crop),
                      label: Text(s['done']),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(48, 56),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
