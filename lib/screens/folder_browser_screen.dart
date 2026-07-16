import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/strings.dart';
import '../models/library_file.dart';
import '../services/folder_library_service.dart';
import '../theme/design_tokens.dart';

/// Lists PDFs/images across every folder the user has picked (any number of
/// them — Drive/OneDrive/Dropbox folders included via Storage Access
/// Framework on Android, or a real local folder on web via the File System
/// Access API), with filter-by-type and sort. Tapping a file reads its bytes
/// and hands them to the caller the same way History's "view" does.
class FolderBrowserScreen extends StatefulWidget {
  const FolderBrowserScreen({super.key, this.embedded = false, this.onOpen});

  /// True when hosted inside the web toolbox side panel instead of pushed
  /// as its own full-screen route — skips the AppBar (the panel supplies
  /// its own chrome) since there's nothing to "back" out of.
  final bool embedded;

  /// Loads a picked file's bytes into the work screen — the caller owns
  /// closing this screen/panel and opening the document.
  final void Function(Uint8List bytes, String fileName)? onOpen;

  @override
  State<FolderBrowserScreen> createState() => _FolderBrowserScreenState();
}

class _FolderBrowserScreenState extends State<FolderBrowserScreen> {
  final FolderLibraryService _library = FolderLibraryService();

  List<LibraryFolder> _folders = [];
  List<LibraryFile> _files = [];
  LibraryFileKind? _filter;
  LibrarySort _sort = const LibrarySort(LibrarySortField.name);
  bool _loading = true;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final folders = await _library.listFolders();
    final files = <LibraryFile>[];
    for (final folder in folders) {
      files.addAll(await _library.listFiles(folder));
    }
    if (!mounted) return;
    setState(() {
      _folders = folders;
      _files = files;
      _loading = false;
    });
  }

  Future<void> _addFolder() async {
    final folder = await _library.pickFolder();
    if (folder == null || !mounted) return;
    await _load();
  }

  Future<void> _removeFolder(LibraryFolder folder) async {
    await _library.removeFolder(folder.id);
    if (!mounted) return;
    await _load();
  }

  Future<void> _openFile(LibraryFile file) async {
    final onOpen = widget.onOpen;
    if (onOpen == null || _opening) return;
    setState(() => _opening = true);
    final bytes = await _library.readFile(file);
    if (!mounted) return;
    setState(() => _opening = false);
    if (bytes == null) {
      _snack(S.of(context)['exportError']);
      return;
    }
    onOpen(bytes, file.name);
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
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: Text(s['folderLibrary']),
              actions: [
                if (FolderLibraryService.isSupported)
                  IconButton(
                    tooltip: s['addFolder'],
                    icon: const Icon(Icons.create_new_folder_outlined),
                    onPressed: _addFolder,
                  ),
              ],
            ),
      body: !FolderLibraryService.isSupported
          ? _buildUnsupported(s)
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : _folders.isEmpty
          ? _buildEmpty(s)
          : Stack(
              children: [
                Column(
                  children: [
                    if (widget.embedded) _buildEmbeddedAddBar(s),
                    _buildFolderChips(s),
                    _buildFilterAndSortBar(s),
                    Expanded(child: _buildFileList(s)),
                  ],
                ),
                if (_opening)
                  const ColoredBox(
                    color: Color(0x33000000),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
    );
  }

  Widget _buildEmbeddedAddBar(S s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          onPressed: _addFolder,
          icon: const Icon(Icons.create_new_folder_outlined, size: 18),
          label: Text(s['addFolder']),
        ),
      ),
    );
  }

  Widget _buildUnsupported(S s) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.folder_off_outlined,
              size: 40,
              color: DesignTokens.textFaint,
            ),
            const SizedBox(height: 16),
            Text(
              s['folderLibraryUnsupported'],
              style: const TextStyle(fontSize: 15, color: DesignTokens.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(S s) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: const BoxDecoration(
                color: DesignTokens.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.folder_open_outlined,
                size: 38,
                color: DesignTokens.primaryDeep,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              s['folderLibraryEmpty'],
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: DesignTokens.ink,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              s['folderLibraryEmptyHint'],
              style: const TextStyle(fontSize: 14, color: DesignTokens.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _addFolder,
              icon: const Icon(Icons.create_new_folder_outlined),
              label: Text(s['addFolder']),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderChips(S s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _folders
            .map(
              (folder) => InputChip(
                avatar: const Icon(Icons.folder_outlined, size: 18),
                label: Text(folder.name),
                onDeleted: () => _removeFolder(folder),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildFilterAndSortBar(S s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              children: [
                _FilterChip(
                  label: s['filterAll'],
                  selected: _filter == null,
                  onTap: () => setState(() => _filter = null),
                ),
                _FilterChip(
                  label: s['filterPdf'],
                  selected: _filter == LibraryFileKind.pdf,
                  onTap: () => setState(() => _filter = LibraryFileKind.pdf),
                ),
                _FilterChip(
                  label: s['filterImages'],
                  selected: _filter == LibraryFileKind.image,
                  onTap: () => setState(() => _filter = LibraryFileKind.image),
                ),
              ],
            ),
          ),
          PopupMenuButton<LibrarySortField>(
            tooltip: s['sortBy'],
            onSelected: (field) =>
                setState(() => _sort = _sort.toggledOn(field)),
            itemBuilder: (context) => [
              _sortMenuItem(s, LibrarySortField.name, s['sortByName']),
              _sortMenuItem(s, LibrarySortField.modified, s['sortByDate']),
              _sortMenuItem(s, LibrarySortField.size, s['sortBySize']),
            ],
            icon: Icon(
              _sort.ascending
                  ? Icons.arrow_upward
                  : Icons.arrow_downward,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<LibrarySortField> _sortMenuItem(
    S s,
    LibrarySortField field,
    String label,
  ) {
    final selected = _sort.field == field;
    return PopupMenuItem(
      value: field,
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 18,
            color: selected ? DesignTokens.primaryDeep : DesignTokens.textFaint,
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  Widget _buildFileList(S s) {
    final files = applyLibraryFilterAndSort(_files, _filter, _sort);
    if (files.isEmpty) {
      return Center(
        child: Text(
          s['noFilesInFolders'],
          style: const TextStyle(fontSize: 14, color: DesignTokens.textMuted),
        ),
      );
    }
    final folderNames = {for (final f in _folders) f.id: f.name};
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: files.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final file = files[index];
        return _LibraryFileTile(
          file: file,
          folderName: folderNames[file.folderId] ?? '',
          onTap: () => _openFile(file),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap());
  }
}

class _LibraryFileTile extends StatelessWidget {
  const _LibraryFileTile({
    required this.file,
    required this.folderName,
    required this.onTap,
  });

  final LibraryFile file;
  final String folderName;
  final VoidCallback onTap;

  static String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData get _icon => switch (file.kind) {
    LibraryFileKind.pdf => Icons.picture_as_pdf_outlined,
    LibraryFileKind.image => Icons.image_outlined,
    LibraryFileKind.other => Icons.insert_drive_file_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('d.M.yyyy · HH:mm').format(file.modified);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        minVerticalPadding: 12,
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: DesignTokens.primarySoft,
          child: Icon(_icon, color: DesignTokens.primaryDeep),
        ),
        title: Text(
          file.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '$folderName · $dateStr · ${_formatSize(file.sizeBytes)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }
}
