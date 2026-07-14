import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

import '../l10n/strings.dart';
import '../models/saved_mark.dart';
import '../theme/design_tokens.dart';
import '../widgets/transparency_checkerboard.dart';

/// What the mark picker sheet produced.
class MarkPickerResult {
  MarkPickerResult({required this.mark, this.allPages = false});

  final SavedMark mark;

  /// Replicate the placement on every page of the document.
  final bool allPages;
}

/// Bottom sheet used to place a mark on the document — restricted to
/// pre-prepared signatures/stamps/combos from the library (built in
/// Settings). No drawing canvas, no camera/gallery: preparing a new mark
/// only happens in Settings, never mid-document.
Future<MarkPickerResult?> showMarkPickerSheet(
  BuildContext context, {
  required List<SavedMark> marks,
  bool showAllPagesOption = false,
}) {
  return showModalBottomSheet<MarkPickerResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) =>
        _MarkPickerSheet(marks: marks, showAllPagesOption: showAllPagesOption),
  );
}

/// A minimal drawing-only sheet — used to draw a new signature or redraw an
/// existing one from the marks library, in Settings only (no chips, no
/// toggles).
Future<Uint8List?> showDrawCanvasSheet(BuildContext context) {
  return showModalBottomSheet<Uint8List>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => const _DrawCanvasSheet(),
  );
}

class _MarkPickerSheet extends StatefulWidget {
  const _MarkPickerSheet({
    required this.marks,
    required this.showAllPagesOption,
  });

  final List<SavedMark> marks;
  final bool showAllPagesOption;

  @override
  State<_MarkPickerSheet> createState() => _MarkPickerSheetState();
}

class _MarkPickerSheetState extends State<_MarkPickerSheet> {
  bool _allPages = false;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s['chooseMark'],
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final mark in widget.marks)
                  _MarkChip(
                    mark: mark,
                    onTap: () => Navigator.of(
                      context,
                    ).pop(MarkPickerResult(mark: mark, allPages: _allPages)),
                  ),
              ],
            ),
            if (widget.showAllPagesOption) ...[
              const SizedBox(height: 8),
              FilterChip(
                avatar: _allPages
                    ? null
                    : const Icon(Icons.copy_all_outlined, size: 20),
                label: Text(s['allPages']),
                selected: _allPages,
                onSelected: (v) => setState(() => _allPages = v),
              ),
            ],
          ],
        ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s['emptySignature'])));
      return;
    }
    final bytes = await _controller.toPngBytes();
    if (bytes == null || !mounted) return;
    Navigator.of(context).pop(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 220,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                boxShadow: DesignTokens.shadowSm,
                border: Border.all(color: DesignTokens.hairline2),
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
      ),
    );
  }
}
