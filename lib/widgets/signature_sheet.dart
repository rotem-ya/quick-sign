import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

import '../l10n/strings.dart';

/// What the signature sheet produced: freshly drawn ink (worth saving as the
/// reusable signature) or a stored image picked from the shortcuts.
class SignatureSheetResult {
  SignatureSheetResult({required this.bytes, required this.isNewDrawing});

  final Uint8List bytes;
  final bool isNewDrawing;
}

/// Bottom sheet with a drawing canvas. Shows one-tap shortcuts for the saved
/// signature / stamp when they exist.
Future<SignatureSheetResult?> showSignatureSheet(
  BuildContext context, {
  Uint8List? savedSignature,
  Uint8List? savedStamp,
}) {
  return showModalBottomSheet<SignatureSheetResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _SignatureSheet(
      savedSignature: savedSignature,
      savedStamp: savedStamp,
    ),
  );
}

class _SignatureSheet extends StatefulWidget {
  const _SignatureSheet({this.savedSignature, this.savedStamp});

  final Uint8List? savedSignature;
  final Uint8List? savedStamp;

  @override
  State<_SignatureSheet> createState() => _SignatureSheetState();
}

class _SignatureSheetState extends State<_SignatureSheet> {
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
    Navigator.of(context)
        .pop(SignatureSheetResult(bytes: bytes, isNewDrawing: true));
  }

  void _useSaved(Uint8List bytes) {
    Navigator.of(context)
        .pop(SignatureSheetResult(bytes: bytes, isNewDrawing: false));
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
              children: [
                if (widget.savedSignature != null)
                  ActionChip(
                    avatar: const Icon(Icons.draw, size: 20),
                    label: Text(s['savedSignature']),
                    onPressed: () => _useSaved(widget.savedSignature!),
                  ),
                if (widget.savedStamp != null)
                  ActionChip(
                    avatar: const Icon(Icons.approval, size: 20),
                    label: Text(s['myStamp']),
                    onPressed: () => _useSaved(widget.savedStamp!),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
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
