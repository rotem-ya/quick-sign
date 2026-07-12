import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/saved_mark.dart';
import '../services/default_folder_service.dart';
import '../services/marks_service.dart';
import '../services/settings_service.dart';
import '../services/share_service.dart';
import '../services/stamp_service.dart';
import '../widgets/signature_sheet.dart';
import '../widgets/transparency_checkerboard.dart';
import 'stamp_designer_screen.dart';
import 'stamp_setup_screen.dart';

/// Profile, the signatures/stamps library (any number of each — name, add,
/// edit, delete), default save folder, portable backup, about.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settings = SettingsService();
  final MarksService _marksService = MarksService();
  final ShareService _shareService = ShareService();
  final DefaultFolderService _folderService = DefaultFolderService();

  final TextEditingController _nameController = TextEditingController();
  List<SavedMark> _signatures = [];
  List<SavedMark> _stamps = [];
  List<SavedMark> _combos = [];
  String? _defaultSignatureId;
  String? _defaultStampId;
  String? _defaultComboId;
  String? _folderName;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final name = await _settings.getName();
    final signatures = await _marksService.list(type: MarkType.signature);
    final stamps = await _marksService.list(type: MarkType.stamp);
    final combos = await _marksService.list(type: MarkType.combo);
    final defaultSignature = await _marksService.getDefault(MarkType.signature);
    final defaultStamp = await _marksService.getDefault(MarkType.stamp);
    final defaultCombo = await _marksService.getDefault(MarkType.combo);
    final folderName = await _folderService.folderName();
    if (!mounted) return;
    setState(() {
      _nameController.text = name ?? '';
      _signatures = signatures;
      _stamps = stamps;
      _combos = combos;
      _defaultSignatureId = defaultSignature?.id;
      _defaultStampId = defaultStamp?.id;
      _defaultComboId = defaultCombo?.id;
      _folderName = folderName;
      _loaded = true;
    });
  }

  Future<void> _pickFolder() async {
    final name = await _folderService.pickFolder();
    if (!mounted || name == null) return;
    setState(() => _folderName = name);
  }

  Future<void> _clearFolder() async {
    await _folderService.clearFolder();
    if (!mounted) return;
    setState(() => _folderName = null);
  }

  Future<void> _exportBackup() async {
    final s = S.of(context);
    await _settings.setName(_nameController.text);
    final bundle = await _settings.exportBundle();
    final saved = await _shareService.saveAs(bundle, 'quicksign-backup.json');
    if (saved && mounted) _snack(s['backupSaved']);
  }

  /// One tap, no dialog — writes straight into the already-chosen default
  /// folder (Drive/OneDrive/Dropbox via SAF, see [DefaultFolderService]).
  /// This is how a backup gets to the user's own cloud without any account
  /// or OAuth: the same mechanism already used for signed documents.
  Future<void> _quickBackupToFolder() async {
    final s = S.of(context);
    await _settings.setName(_nameController.text);
    final bundle = await _settings.exportBundle();
    final ok = await _folderService.saveFile(bundle, 'quicksign-backup.json');
    if (!mounted) return;
    _snack(
      ok ? '${s['savedToDefaultFolder']} — $_folderName' : s['backupError'],
    );
  }

  Future<void> _importBackup() async {
    final s = S.of(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) return;
    try {
      await _settings.importBundle(bytes);
      await _load();
      if (mounted) _snack(s['backupRestored']);
    } on FormatException {
      if (mounted) _snack(s['backupError']);
    }
  }

  // ── Marks (signatures / stamps) ────────────────────────────────────────

  Future<void> _addSignature() async {
    final bytes = await showDrawCanvasSheet(context);
    if (bytes == null || !mounted) return;
    await _marksService.add(
      type: MarkType.signature,
      name: '${S.of(context)['sign']} ${_signatures.length + 1}',
      imageBytes: bytes,
    );
    await _load();
  }

  Future<void> _redrawSignature(SavedMark mark) async {
    final bytes = await showDrawCanvasSheet(context);
    if (bytes == null || !mounted) return;
    await _marksService.update(mark.id, imageBytes: bytes);
    await _load();
  }

  Future<void> _addStamp() async {
    final mark = await Navigator.of(context).push<SavedMark>(
      MaterialPageRoute(builder: (_) => const StampSetupScreen()),
    );
    if (mark == null) return;
    await _load();
  }

  Future<void> _editStamp(SavedMark mark) async {
    if (mark.design != null) {
      // Designer-made stamp — reopen the designer prefilled.
      final result = await Navigator.of(context).push<StampDesignResult>(
        MaterialPageRoute(
          builder: (_) => StampDesignerScreen(initialDesign: mark.design),
        ),
      );
      if (result == null || !mounted) return;
      await _marksService.update(
        mark.id,
        imageBytes: result.bytes,
        design: result.design,
      );
    } else {
      final updated = await Navigator.of(context).push<SavedMark>(
        MaterialPageRoute(builder: (_) => StampSetupScreen(editingMark: mark)),
      );
      if (updated == null) return;
    }
    await _load();
  }

  Future<void> _rename(SavedMark mark) async {
    final s = S.of(context);
    final controller = TextEditingController(text: mark.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s['renameMark']),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(fontSize: 18),
          decoration: InputDecoration(labelText: s['markNameLabel']),
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(s['cancel']),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(s['done']),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = newName?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    await _marksService.update(mark.id, name: trimmed);
    await _load();
  }

  /// Picks an existing saved signature + stamp and saves the pre-composited
  /// pair as its own mark — placing it on a document needs no runtime
  /// combining, just picking this one item.
  Future<void> _addCombo() async {
    final s = S.of(context);
    if (_signatures.isEmpty || _stamps.isEmpty) {
      _snack(s['comboNeedsBoth']);
      return;
    }
    final picked = await showDialog<_ComboPick>(
      context: context,
      builder: (_) =>
          _ComboPickerDialog(signatures: _signatures, stamps: _stamps),
    );
    if (picked == null) return;
    final bytes = await StampService.compositeSignatureOverStamp(
      picked.signature.imageBytes,
      picked.stamp.imageBytes,
    );
    if (!mounted) return;
    await _marksService.add(
      type: MarkType.combo,
      name: '${s['sign']}+${s['stamp']} ${_combos.length + 1}',
      imageBytes: bytes,
    );
    await _load();
  }

  Future<void> _editCombo(SavedMark mark) async {
    final picked = await showDialog<_ComboPick>(
      context: context,
      builder: (_) =>
          _ComboPickerDialog(signatures: _signatures, stamps: _stamps),
    );
    if (picked == null) return;
    final bytes = await StampService.compositeSignatureOverStamp(
      picked.signature.imageBytes,
      picked.stamp.imageBytes,
    );
    if (!mounted) return;
    await _marksService.update(mark.id, imageBytes: bytes);
    await _load();
  }

  Future<void> _toggleDefault(SavedMark mark, String? currentDefaultId) async {
    if (currentDefaultId == mark.id) {
      await _marksService.clearDefault(mark.type);
    } else {
      await _marksService.setDefault(mark.type, mark.id);
    }
    await _load();
  }

  Future<void> _delete(SavedMark mark) async {
    final s = S.of(context);
    await _marksService.delete(mark.id);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(s['deleted'], style: const TextStyle(fontSize: 16)),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: s['undo'],
            onPressed: () async {
              await _marksService.restore(mark);
              await _load();
            },
          ),
        ),
      );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(s['settings'])),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SectionTitle(s['profile']),
                TextField(
                  controller: _nameController,
                  style: const TextStyle(fontSize: 18),
                  decoration: InputDecoration(
                    labelText: s['profileName'],
                    prefixIcon: const Icon(Icons.person_outline),
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: _settings.setName,
                ),
                const SizedBox(height: 24),
                _SectionTitle(s['savedSignatures']),
                for (final mark in _signatures) ...[
                  _MarkTile(
                    mark: mark,
                    onRename: () => _rename(mark),
                    onEdit: () => _redrawSignature(mark),
                    editIcon: Icons.draw_outlined,
                    editTooltip: s['redrawSignature'],
                    onDelete: () => _delete(mark),
                    isDefault: mark.id == _defaultSignatureId,
                    onToggleDefault: () =>
                        _toggleDefault(mark, _defaultSignatureId),
                  ),
                  const SizedBox(height: 8),
                ],
                _AddMarkTile(label: s['addSignature'], onTap: _addSignature),
                const SizedBox(height: 24),
                _SectionTitle(s['savedStamps']),
                for (final mark in _stamps) ...[
                  _MarkTile(
                    mark: mark,
                    onRename: () => _rename(mark),
                    onEdit: () => _editStamp(mark),
                    editIcon: Icons.edit_outlined,
                    editTooltip: s['edit'],
                    onDelete: () => _delete(mark),
                    isDefault: mark.id == _defaultStampId,
                    onToggleDefault: () =>
                        _toggleDefault(mark, _defaultStampId),
                  ),
                  const SizedBox(height: 8),
                ],
                _AddMarkTile(label: s['addStamp'], onTap: _addStamp),
                const SizedBox(height: 24),
                _SectionTitle(s['savedCombos']),
                Text(
                  s['combosHint'],
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                for (final mark in _combos) ...[
                  _MarkTile(
                    mark: mark,
                    onRename: () => _rename(mark),
                    onEdit: () => _editCombo(mark),
                    editIcon: Icons.edit_outlined,
                    editTooltip: s['edit'],
                    onDelete: () => _delete(mark),
                    isDefault: mark.id == _defaultComboId,
                    onToggleDefault: () =>
                        _toggleDefault(mark, _defaultComboId),
                  ),
                  const SizedBox(height: 8),
                ],
                _AddMarkTile(label: s['addCombo'], onTap: _addCombo),
                if (DefaultFolderService.isSupported) ...[
                  const SizedBox(height: 24),
                  _SectionTitle(s['defaultFolder']),
                  Card(
                    margin: EdgeInsets.zero,
                    child: _folderName == null
                        ? ListTile(
                            leading: const Icon(Icons.folder_open_outlined),
                            title: Text(s['chooseFolder']),
                            subtitle: Text(
                              s['defaultFolderHint'],
                              style: const TextStyle(fontSize: 13),
                            ),
                            onTap: _pickFolder,
                          )
                        : ListTile(
                            leading: Icon(Icons.folder, color: scheme.primary),
                            title: Text(_folderName!),
                            subtitle: Text(
                              s['savesHereHint'],
                              style: const TextStyle(fontSize: 13),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: s['changeFolder'],
                                  onPressed: _pickFolder,
                                  icon: const Icon(Icons.autorenew),
                                ),
                                IconButton(
                                  tooltip: s['removeFolder'],
                                  onPressed: _clearFolder,
                                  icon: Icon(Icons.close, color: scheme.error),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
                const SizedBox(height: 24),
                _SectionTitle(s['backup']),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      if (DefaultFolderService.isSupported &&
                          _folderName != null) ...[
                        ListTile(
                          leading: Icon(
                            Icons.cloud_upload_outlined,
                            color: scheme.primary,
                          ),
                          title: Text(s['quickBackup']),
                          subtitle: Text(
                            '${s['quickBackupSub']} — $_folderName',
                            style: const TextStyle(fontSize: 13),
                          ),
                          onTap: _quickBackupToFolder,
                        ),
                        const Divider(height: 1),
                      ],
                      ListTile(
                        leading: const Icon(Icons.upload_file_outlined),
                        title: Text(s['exportSettings']),
                        subtitle: Text(
                          s['exportSettingsSub'],
                          style: const TextStyle(fontSize: 13),
                        ),
                        onTap: _exportBackup,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.settings_backup_restore),
                        title: Text(s['importSettings']),
                        onTap: _importBackup,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _SectionTitle(s['about']),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.verified_user_outlined,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            s['aboutText'],
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _MarkTile extends StatelessWidget {
  const _MarkTile({
    required this.mark,
    required this.onRename,
    required this.onEdit,
    required this.editIcon,
    required this.editTooltip,
    required this.onDelete,
    required this.isDefault,
    required this.onToggleDefault,
  });

  final SavedMark mark;
  final VoidCallback onRename;
  final VoidCallback onEdit;
  final IconData editIcon;
  final String editTooltip;
  final VoidCallback onDelete;
  final bool isDefault;
  final VoidCallback onToggleDefault;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: isDefault ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 88,
                height: 56,
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: TransparencyCheckerboard(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Image.memory(mark.imageBytes, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: onRename,
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        mark.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.edit, size: 14, color: scheme.outline),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: isDefault ? s['unsetDefault'] : s['setDefault'],
              onPressed: onToggleDefault,
              icon: Icon(
                isDefault ? Icons.star : Icons.star_border,
                color: isDefault ? scheme.primary : scheme.outline,
              ),
            ),
            IconButton(
              tooltip: editTooltip,
              onPressed: onEdit,
              icon: Icon(editIcon),
            ),
            IconButton(
              tooltip: s['delete'],
              onPressed: onDelete,
              icon: Icon(Icons.delete_outline, color: scheme.error),
            ),
          ],
        ),
      ),
    );
  }
}

/// A signature + stamp chosen together to build a combo mark.
class _ComboPick {
  _ComboPick({required this.signature, required this.stamp});
  final SavedMark signature;
  final SavedMark stamp;
}

class _ComboPickerDialog extends StatefulWidget {
  const _ComboPickerDialog({required this.signatures, required this.stamps});

  final List<SavedMark> signatures;
  final List<SavedMark> stamps;

  @override
  State<_ComboPickerDialog> createState() => _ComboPickerDialogState();
}

class _ComboPickerDialogState extends State<_ComboPickerDialog> {
  SavedMark? _signature;
  SavedMark? _stamp;

  @override
  void initState() {
    super.initState();
    if (widget.signatures.length == 1) _signature = widget.signatures.single;
    if (widget.stamps.length == 1) _stamp = widget.stamps.single;
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AlertDialog(
      title: Text(s['addCombo']),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s['savedSignatures'],
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final mark in widget.signatures)
                  ChoiceChip(
                    label: Text(mark.name),
                    selected: _signature?.id == mark.id,
                    onSelected: (_) => setState(() => _signature = mark),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              s['savedStamps'],
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final mark in widget.stamps)
                  ChoiceChip(
                    label: Text(mark.name),
                    selected: _stamp?.id == mark.id,
                    onSelected: (_) => setState(() => _stamp = mark),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s['cancel']),
        ),
        FilledButton(
          onPressed: _signature == null || _stamp == null
              ? null
              : () => Navigator.of(
                  context,
                ).pop(_ComboPick(signature: _signature!, stamp: _stamp!)),
          child: Text(s['done']),
        ),
      ],
    );
  }
}

class _AddMarkTile extends StatelessWidget {
  const _AddMarkTile({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.add),
      label: Align(alignment: Alignment.centerLeft, child: Text(label)),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
        foregroundColor: scheme.primary,
        alignment: Alignment.centerLeft,
      ),
    );
  }
}
