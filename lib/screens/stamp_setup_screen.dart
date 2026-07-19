import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/saved_mark.dart';
import '../models/stamp_design.dart';
import '../services/marks_service.dart';
import '../services/pdf_render_service.dart';
import '../services/stamp_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/crop_view.dart';
import '../widgets/transparency_checkerboard.dart';
import 'stamp_designer_screen.dart';
import 'stamp_from_page_screen.dart';

/// Stamp capture: photograph the stamp, pick any image, pull a region out of
/// a PDF, or (via [initialProcessedBytes]) accept an already-cropped image
/// from elsewhere (the work screen's "create stamp from this document").
/// Mark the stamp region, the background is removed automatically, preview,
/// save into the marks library.
///
/// Pass [editingMark] to replace an existing stamp's image instead of adding
/// a new one (used from the marks library in Settings). Pops with the
/// resulting [SavedMark] when the user confirms.
class StampSetupScreen extends StatefulWidget {
  const StampSetupScreen({
    super.key,
    this.editingMark,
    this.initialProcessedBytes,
  });

  final SavedMark? editingMark;

  /// Already-cropped, already-cleaned bytes — skips straight to the
  /// preview/confirm step instead of the capture screen.
  final Uint8List? initialProcessedBytes;

  @override
  State<StampSetupScreen> createState() => _StampSetupScreenState();
}

class _StampSetupScreenState extends State<StampSetupScreen> {
  final StampService _service = StampService();
  final MarksService _marksService = MarksService();

  Uint8List? _raw;
  double _rawAspect = 1;
  Rect _crop = const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9);
  Uint8List? _processed;
  StampDesign? _pendingDesign;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final editing = widget.editingMark;
    if (editing != null) {
      // Show the current stamp right away — Retake / Redesign / confirm.
      _processed = editing.imageBytes;
      _pendingDesign = editing.design;
    } else if (widget.initialProcessedBytes != null) {
      _processed = widget.initialProcessedBytes;
    }
  }

  Future<void> _capture({required bool fromCamera}) =>
      _captureFrom(() => _service.captureImage(fromCamera: fromCamera));

  /// Files can be a plain image (straight into the existing crop step) or a
  /// PDF (pull a stamp — with or without a nearby signature, whatever the
  /// user's crop rectangle happens to include — out of any page of an
  /// already-signed/scanned document).
  Future<void> _pickFromFiles() async {
    setState(() => _busy = true);
    final picked = await _service.pickImageOrPdfFile();
    if (picked == null) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (picked.isPdf) {
      await _pickFromPdf(picked.bytes);
    } else {
      await _useRawBytes(picked.bytes);
    }
  }

  Future<void> _pickFromPdf(Uint8List pdfBytes) async {
    final renderService = PdfRenderService();
    try {
      final info = await renderService.open(pdfBytes);
      if (!mounted) return;
      final processed = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          builder: (_) => StampFromPageScreen(
            pageCount: info.pageCount,
            initialPageIndex: 0,
            pageBytesLoader: renderService.renderPage,
          ),
        ),
      );
      if (!mounted) return;
      if (processed == null) {
        setState(() => _busy = false);
        return;
      }
      setState(() {
        _raw = null;
        _processed = processed;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snackError();
    } finally {
      await renderService.close();
    }
  }

  Future<void> _useRawBytes(Uint8List raw) async {
    try {
      final image = await decodeImageFromList(raw);
      final aspect = image.width / image.height;
      image.dispose();
      if (!mounted) return;
      setState(() {
        _raw = raw;
        _rawAspect = aspect;
        _crop = const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9);
        _processed = null;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snackError();
    }
  }

  Future<void> _captureFrom(Future<Uint8List?> Function() picker) async {
    setState(() => _busy = true);
    try {
      final raw = await picker();
      if (raw == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final image = await decodeImageFromList(raw);
      final aspect = image.width / image.height;
      image.dispose();
      if (!mounted) return;
      setState(() {
        _raw = raw;
        _rawAspect = aspect;
        _crop = const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9);
        _processed = null;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snackError();
    }
  }

  Future<void> _applyCrop() async {
    final raw = _raw;
    if (raw == null) return;
    setState(() => _busy = true);
    try {
      final processed = await compute(
        StampService.cropAndClean,
        StampCropRequest(
          bytes: raw,
          left: _crop.left,
          top: _crop.top,
          right: _crop.right,
          bottom: _crop.bottom,
        ),
      );
      if (!mounted) return;
      setState(() {
        _processed = processed;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snackError();
    }
  }

  Future<void> _openDesigner() async {
    final result = await Navigator.of(context).push<StampDesignResult>(
      MaterialPageRoute(
        builder: (_) => StampDesignerScreen(initialDesign: _pendingDesign),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _raw = null;
      _processed = result.bytes;
      _pendingDesign = result.design;
    });
  }

  Future<void> _confirm() async {
    final bytes = _processed;
    if (bytes == null) return;
    setState(() => _busy = true);
    final editing = widget.editingMark;
    final SavedMark mark;
    if (editing != null) {
      await _marksService.update(
        editing.id,
        imageBytes: bytes,
        design: _pendingDesign,
        clearDesign: _pendingDesign == null,
      );
      mark = SavedMark(
        id: editing.id,
        type: editing.type,
        name: editing.name,
        imageBytes: bytes,
        design: _pendingDesign,
      );
    } else {
      final existingCount = (await _marksService.list(
        type: MarkType.stamp,
      )).length;
      if (!mounted) return;
      mark = await _marksService.add(
        type: MarkType.stamp,
        name: '${S.of(context)['stamp']} ${existingCount + 1}',
        imageBytes: bytes,
        design: _pendingDesign,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop(mark);
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
        title: Text(
          widget.editingMark != null
              ? s['editStampTitle']
              : s['stampSetupTitle'],
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: DesignTokens.surfaceMuted,
                    borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                    boxShadow: DesignTokens.shadowSm,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _busy
                      ? const Center(child: CircularProgressIndicator())
                      : _buildPreviewArea(s, scheme),
                ),
              ),
              const SizedBox(height: 16),
              _buildActions(s),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewArea(S s, ColorScheme scheme) {
    if (_processed != null) {
      // Checkerboard, not a solid fill — makes it visually obvious the
      // stamp's background was actually removed, not just painted white.
      return TransparencyCheckerboard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Image.memory(_processed!, fit: BoxFit.contain),
        ),
      );
    }
    if (_raw != null) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Text(
              s['cropHint'],
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: CropView(
                imageBytes: _raw!,
                imageAspect: _rawAspect,
                crop: _crop,
                onChanged: (rect) => setState(() => _crop = rect),
              ),
            ),
          ),
        ],
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          s['stampHint'],
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 17, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _buildActions(S s) {
    if (_processed != null) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _processed = null;
                      _pendingDesign = null;
                    }),
              icon: const Icon(Icons.replay),
              label: Text(s['retake']),
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 56)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : _confirm,
              icon: const Icon(Icons.check),
              label: Text(s['useStamp']),
              style: ElevatedButton.styleFrom(minimumSize: const Size(48, 56)),
            ),
          ),
        ],
      );
    }
    if (_raw != null) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => setState(() => _raw = null),
              icon: const Icon(Icons.replay),
              label: Text(s['retake']),
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 56)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : _applyCrop,
              icon: const Icon(Icons.crop),
              label: Text(s['done']),
              style: ElevatedButton.styleFrom(minimumSize: const Size(48, 56)),
            ),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Tooltip(
              message: s['captureStamp'],
              child: OutlinedButton(
                onPressed: _busy ? null : () => _capture(fromCamera: true),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(56, 56),
                  maximumSize: const Size(56, 56),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                  ),
                ),
                child: const Icon(Icons.photo_camera_outlined),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _pickFromFiles,
                icon: const Icon(Icons.folder_open_outlined),
                label: Text(s['fromFiles']),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(48, 56),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _openDesigner,
          icon: const Icon(Icons.design_services_outlined),
          label: Text(s['designStamp']),
          style: OutlinedButton.styleFrom(minimumSize: const Size(48, 56)),
        ),
      ],
    );
  }
}
