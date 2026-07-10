import 'package:flutter/material.dart';

import '../l10n/strings.dart';

/// Bottom sheet for adding a short note. Large font, high contrast, follows
/// the text's own direction (Hebrew types RTL automatically).
///
/// [suggestions] are one-tap chips (today's date, "approved", the user's
/// name…) that append to the text — the fastest path for the common cases.
Future<String?> showNoteSheet(
  BuildContext context, {
  List<String> suggestions = const [],
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _NoteSheet(suggestions: suggestions),
  );
}

class _NoteSheet extends StatefulWidget {
  const _NoteSheet({required this.suggestions});

  final List<String> suggestions;

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _append(String chip) {
    final current = _controller.text.trim();
    _controller.text = current.isEmpty ? chip : '$current $chip';
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
  }

  void _confirm() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.suggestions.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final chip in widget.suggestions)
                  ActionChip(
                    label: Text(chip),
                    onPressed: () => _append(chip),
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 1,
            maxLines: 4,
            style: const TextStyle(fontSize: 22),
            decoration: InputDecoration(
              hintText: s['noteHint'],
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _confirm(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _confirm,
            icon: const Icon(Icons.check),
            label: Text(s['done']),
            style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
          ),
        ],
      ),
    );
  }
}
