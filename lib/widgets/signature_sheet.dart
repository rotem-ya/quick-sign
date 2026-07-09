import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

import '../l10n/strings.dart';

/// What the signature sheet produced.
class SignatureSheetResult {
  SignatureSheetResult({
    required this.bytes,
    required this.isNewDrawing,
    required this.withStamp,
    required this.allPages,
  });

  final Uint8List bytes;

  /// True when freshly drawn (worth remembering as the reusable signature).
  final bool isNewDrawing;

  /// Place the signature on top of the saved stamp as one combined item.
  final bool withStamp;

  /// Replicate the placement on every page of the document.
  final bool allPages;
}

/// Bottom sheet with a drawing canvas, one-tap shortcuts for the saved
/// signature / stamp, and toggles for stamp-combo and all-pages placement.
Future<SignatureSheetResult?> showSignatureSheet(
  BuildContext context, {
  Uint8List? savedSignature,
  Uint8List? savedStamp,
  bool showAllPagesOption = false,
}) {
  return showModalBottomSheet<SignatureSheetResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _SignatureSheet(
      savedSignature: savedSignature,
      savedStamp: savedStamp,
      showAllPagesOption: showAllPagesOption,
    ),
  );
}

class _SignatureSheet extends StatefulWidget {
  const _SignatureSheet({
    this.savedSignature,
    this.savedStamp,
    required this.showAllPagesOption,
  });

  final Uint8List? savedSignature;
  final Uint8List? savedStamp;
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
      withStamp: _withStamp && widget.savedStamp != null,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.savedSignature != null || widget.savedStamp != null) ...[
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (widget.savedSignature != null)
                  ActionChip(
                    avatar: const Icon(Icons.draw, size: 20),
                    label: Text(s['savedSignature']),
                    onPressed: () =>
                        _pop(widget.savedSignature!, isNewDrawing: false),
                  ),
                if (widget.savedStamp != null)
                  ActionChip(
                    avatar: const Icon(Icons.approval, size: 20),
                    label: Text(s['myStamp']),
                    onPressed: () {
                      // The stamp itself — the combo toggle is irrelevant.
                      Navigator.of(context).pop(SignatureSheetResult(
                        bytes: widget.savedStamp!,
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
              if (widget.savedStamp != null)
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
