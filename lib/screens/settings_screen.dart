import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/settings_service.dart';
import '../services/share_service.dart';
import '../services/stamp_service.dart';
import 'stamp_setup_screen.dart';

/// Profile, saved signature/stamp management, portable backup, about.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settings = SettingsService();
  final StampService _stampService = StampService();
  final ShareService _shareService = ShareService();

  final TextEditingController _nameController = TextEditingController();
  Uint8List? _stamp;
  Uint8List? _signature;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final name = await _settings.getName();
    final stamp = await _stampService.getStampBytes();
    final signature = await _stampService.getSignatureBytes();
    if (!mounted) return;
    setState(() {
      _nameController.text = name ?? '';
      _stamp = stamp;
      _signature = signature;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _settings.setName(_nameController.text);
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _exportBackup() async {
    final s = S.of(context);
    await _settings.setName(_nameController.text);
    final bundle = await _settings.exportBundle();
    final saved = await _shareService.saveAs(bundle, 'quicksign-backup.json');
    if (saved && mounted) _snack(s['backupSaved']);
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

  Future<void> _replaceStamp() async {
    final bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => const StampSetupScreen()),
    );
    if (bytes != null) await _load();
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
                _SectionTitle(s['savedItems']),
                _SavedItemCard(
                  icon: Icons.draw_outlined,
                  title: s['savedSignature'],
                  bytes: _signature,
                  emptyLabel: s['notSaved'],
                  deleteLabel: s['delete'],
                  onDelete: () async {
                    await _stampService.removeSignature();
                    await _load();
                  },
                ),
                const SizedBox(height: 12),
                _SavedItemCard(
                  icon: Icons.approval_outlined,
                  title: s['myStamp'],
                  bytes: _stamp,
                  emptyLabel: s['notSaved'],
                  deleteLabel: s['delete'],
                  replaceLabel: s['replace'],
                  onReplace: _replaceStamp,
                  onDelete: () async {
                    await _stampService.removeStamp();
                    await _load();
                  },
                ),
                const SizedBox(height: 24),
                _SectionTitle(s['backup']),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.upload_file_outlined),
                        title: Text(s['exportSettings']),
                        subtitle: Text(s['exportSettingsSub'],
                            style: const TextStyle(fontSize: 13)),
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
                        Icon(Icons.verified_user_outlined,
                            color: scheme.primary),
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

class _SavedItemCard extends StatelessWidget {
  const _SavedItemCard({
    required this.icon,
    required this.title,
    required this.bytes,
    required this.emptyLabel,
    required this.deleteLabel,
    required this.onDelete,
    this.replaceLabel,
    this.onReplace,
  });

  final IconData icon;
  final String title;
  final Uint8List? bytes;
  final String emptyLabel;
  final String deleteLabel;
  final String? replaceLabel;
  final VoidCallback onDelete;
  final VoidCallback? onReplace;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 88,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: bytes != null
                  ? Padding(
                      padding: const EdgeInsets.all(4),
                      child: Image.memory(bytes!, fit: BoxFit.contain),
                    )
                  : Icon(icon, color: scheme.outline),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w500)),
                  if (bytes == null)
                    Text(emptyLabel,
                        style: TextStyle(
                            fontSize: 13, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            if (onReplace != null)
              IconButton(
                tooltip: replaceLabel,
                onPressed: onReplace,
                icon: const Icon(Icons.autorenew),
              ),
            if (bytes != null)
              IconButton(
                tooltip: deleteLabel,
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline, color: scheme.error),
              ),
          ],
        ),
      ),
    );
  }
}
