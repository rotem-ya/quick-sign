import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

import '../l10n/strings.dart';
import '../models/saved_mark.dart';
import '../widgets/transparency_checkerboard.dart';

/// What the signature sheet produced.
class SignatureSheetResult {
  SignatureSheetResult({
    required this.bytes,
    required this.isNewDrawing,
    required this.withStamp,
    required this.allPages,
  });

  final Uint8List bytes;

  /// True when freshly drawn (worth remembering as a new saved signature).
  final bool isNewDrawing;

  /// Place the signature on top of the first saved stamp as one combined item.
  final bool withStamp;

  /// Replicate the placement on every page of the document.
  final bool allPages;
}

/// Bottom sheet with a drawing canvas, one-tap shortcuts for every saved
/// signature / stamp, and toggles for stamp-combo and all-pages placement.
Future<SignatureSheetResult?> showSignatureSheet(
  BuildContext context, {
  List<SavedMark> savedSignatures = const [],
  List<SavedMark> savedStamps = const [],
  bool showAllPagesOption = false,
}) {
  return showModalBottomSheet<SignatureSheetResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _SignatureSheet(
      savedSignatures: savedSignatures,
      savedStamps: savedStamps,
      showAllPagesOption: showAllPagesOption,
    ),
  );
}

/// A minimal drawing-only sheet — used to redraw an existing saved signature
/// from the marks library in Settings (no chips, no toggles).
Future<Uint8List?> showDrawCanvasSheet(BuildContext context) {
  return showModalBottomSheet<Uint8List>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => const _DrawCanvasSheet(),
  );
}

class _SignatureSheet extends StatefulWidget {
  const _SignatureSheet({
    required this.savedSignatures,
    required this.savedStamps,
    required this.showAllPagesOption,
  });

  final List<SavedMark> savedSignatures;
  final List<SavedMark> savedStamps;
  final bool showAllPagesOption;

  @override
  State<_SignatureSheet> createState() => _SignatureSheetState();
}

class _SignatureSheetState extends State<_SignatureSheet> {
  late final SignatureController _controller = SignatureController(
    penStrokeWidth: 4,
    penColor: const Color(0xFF1A2C7C),
    exportBackgroundColor: Colors.transparent,
  );

  bool _withStamp = false;
  bool _allPages = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _pop(Uint8List bytes, {required bool isNewDrawing}) {
    Navigator.of(context).pop(SignatureSheetResult(
      bytes: bytes,
      isNewDrawing: isNewDrawing,
      withStamp: _withStamp && widget.savedStamps.isNotEmpty,
      allPages: _allPages,
    ));
  }

  Future<void> _confirm() async {
    final s = S.of(context);
    if (_controller.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s['emptySignature'])),
      );
      return;
    }
    final bytes = await _controller.toPngBytes();
    if (bytes == null || !mounted) return;
    _pop(bytes, isNewDrawing: true);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final hasSaved =
        widget.savedSignatures.isNotEmpty || widget.savedStamps.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasSaved) ...[
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final mark in widget.savedSignatures)
                  _MarkChip(
                    mark: mark,
                    onTap: () => _pop(mark.imageBytes, isNewDrawing: false),
                  ),
                for (final mark in widget.savedStamps)
                  _MarkChip(
                    mark: mark,
                    onTap: () {
                      // The stamp itself — the combo toggle is irrelevant.
                      Navigator.of(context).pop(SignatureSheetResult(
                        bytes: mark.imageBytes,
                        isNewDrawing: false,
                        withStamp: false,
                        allPages: _allPages,
                      ));
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Signature(
              controller: _controller,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              if (widget.savedStamps.isNotEmpty)
                FilterChip(
                  avatar: _withStamp
                      ? null
                      : const Icon(Icons.approval_outlined, size: 20),
                  label: Text(s['withStamp']),
                  selected: _withStamp,
                  onSelected: (v) => setState(() => _withStamp = v),
                ),
              if (widget.showAllPagesOption)
                FilterChip(
                  avatar: _allPages
                      ? null
                      : const Icon(Icons.copy_all_outlined, size: 20),
                  label: Text(s['allPages']),
                  selected: _allPages,
                  onSelected: (v) => setState(() => _allPages = v),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _controller.clear,
                  icon: const Icon(Icons.replay),
                  label: Text(s['clear']),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 52),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _confirm,
                  icon: const Icon(Icons.check),
                  label: Text(s['done']),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 52),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A saved signature/stamp shortcut: small transparent thumbnail + name.
class _MarkChip extends StatelessWidget {
  const _MarkChip({required this.mark, required this.onTap});

  final SavedMark mark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 24,
          height: 24,
          child: TransparencyCheckerboard(
            tile: 6,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Image.memory(mark.imageBytes, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
      label: Text(mark.name),
      onPressed: onTap,
    );
  }
}

class _DrawCanvasSheet extends StatefulWidget {
  const _DrawCanvasSheet();

  @override
  State<_DrawCanvasSheet> createState() => _DrawCanvasSheetState();
}

class _DrawCanvasSheetState extends State<_DrawCanvasSheet> {
  late final SignatureController _controller = SignatureController(
    penStrokeWidth: 4,
    penColor: const Color(0xFF1A2C7C),
    exportBackgroundColor: Colors.transparent,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final s = S.of(context);
    if (_controller.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s['emptySignature'])),
      );
      return;
    }
    final bytes = await _controller.toPngBytes();
    if (bytes == null || !mounted) return;
    Navigator.of(context).pop(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 220,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Signature(
              controller: _controller,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _controller.clear,
                  icon: const Icon(Icons.replay),
                  label: Text(s['clear']),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 52),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _confirm,
                  icon: const Icon(Icons.check),
                  label: Text(s['done']),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 52),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
