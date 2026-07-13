import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/strings.dart';
import '../models/history_entry.dart';
import '../services/default_folder_service.dart';
import '../services/history_service.dart';
import '../services/print_service.dart';
import '../services/share_service.dart';

/// Every signed document, kept until the user explicitly deletes it — a
/// permanent local copy, separate from the transient file used for a single
/// share/print action.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, this.embedded = false});

  /// True when hosted inside the web toolbox side panel instead of pushed
  /// as its own full-screen route — skips the AppBar (the panel supplies
  /// its own chrome) since there's nothing to "back" out of.
  final bool embedded;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final HistoryService _history = HistoryService();
  final ShareService _shareService = ShareService();
  final DefaultFolderService _folderService = DefaultFolderService();
  final PrintService _printService = PrintService();

  List<HistoryEntry>? _entries;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await _history.list();
    if (!mounted) return;
    setState(() => _entries = entries);
  }

  Future<void> _delete(HistoryEntry entry) async {
    final s = S.of(context);
    final bytes = await _history.readBytes(entry);
    await _history.delete(entry);
    await _load();
    if (!mounted || bytes == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(s['deleted'], style: const TextStyle(fontSize: 16)),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: s['undo'],
            onPressed: () async {
              await _history.restore(entry, bytes);
              await _load();
            },
          ),
        ),
      );
  }

  Future<void> _openActions(HistoryEntry entry) async {
    final s = S.of(context);
    final bytes = await _history.readBytes(entry);
    if (!mounted) return;
    if (bytes == null) {
      _snack(s['exportError']);
      return;
    }
    final defaultFolder = await _folderService.folderName();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (defaultFolder != null)
              ListTile(
                leading: Icon(Icons.bolt, size: 28, color: Colors.amber[800]),
                title: Text(
                  s['saveToDefaultFolder'],
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  defaultFolder,
                  style: const TextStyle(fontSize: 13),
                ),
                minTileHeight: 56,
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final ok = await _folderService.saveFile(
                    bytes,
                    entry.fileName,
                  );
                  _snack(
                    ok
                        ? '${s['savedToDefaultFolder']} — $defaultFolder'
                        : s['exportError'],
                  );
                },
              ),
            if (ShareService.canShare)
              ListTile(
                leading: const Icon(Icons.share, size: 28),
                title: Text(s['share'], style: const TextStyle(fontSize: 18)),
                minTileHeight: 56,
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _shareService.shareBytes(bytes, entry.fileName);
                },
              ),
            ListTile(
              leading: Icon(
                ShareService.canShare
                    ? Icons.drive_folder_upload_outlined
                    : Icons.download,
                size: 28,
              ),
              title: Text(
                ShareService.canShare ? s['saveTo'] : s['download'],
                style: const TextStyle(fontSize: 18),
              ),
              minTileHeight: 56,
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final saved = await _shareService.saveAs(bytes, entry.fileName);
                if (saved) _snack(s['copySaved']);
              },
            ),
            ListTile(
              leading: const Icon(Icons.print_outlined, size: 28),
              title: Text(s['print'], style: const TextStyle(fontSize: 18)),
              minTileHeight: 56,
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _printService.printPdf(bytes, entry.fileName);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message, style: const TextStyle(fontSize: 16))),
      );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: Text(s['history'])),
      body: _entries == null
          ? const Center(child: CircularProgressIndicator())
          : _entries!.isEmpty
          ? _buildEmpty(s, scheme)
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _entries!.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final entry = _entries![index];
                return _HistoryTile(
                  key: ValueKey(entry.id),
                  entry: entry,
                  onTap: () => _openActions(entry),
                  onDelete: () => _delete(entry),
                );
              },
            ),
    );
  }

  Widget _buildEmpty(S s, ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 56, color: scheme.outline),
            const SizedBox(height: 16),
            Text(
              s['historyEmpty'],
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              s['historyEmptyHint'],
              style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onDelete,
  });

  final HistoryEntry entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  static String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final dateStr = DateFormat('d.M.yyyy · HH:mm').format(entry.savedAt);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        minVerticalPadding: 12,
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          child: Icon(
            Icons.picture_as_pdf_outlined,
            color: scheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          entry.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '$dateStr · ${entry.pageCount} ${s['pages']} · ${_formatSize(entry.sizeBytes)}',
          style: const TextStyle(fontSize: 13),
        ),
        trailing: IconButton(
          tooltip: s['delete'],
          icon: Icon(Icons.delete_outline, color: scheme.error),
          onPressed: onDelete,
        ),
      ),
    );
  }
}
