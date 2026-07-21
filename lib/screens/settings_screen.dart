import 'dart:async';
import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/saved_mark.dart';
import '../services/auth_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/default_folder_service.dart';
import '../services/marks_service.dart';
import '../services/settings_service.dart';
import '../services/share_service.dart';
import '../services/stamp_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/signature_sheet.dart';
import '../widgets/transparency_checkerboard.dart';
import 'stamp_designer_screen.dart';
import 'stamp_setup_screen.dart';

/// Profile, the signatures/stamps library (any number of each — name, add,
/// edit, delete), default save folder, portable backup, about.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.embedded = false});

  /// True when hosted inside the web toolbox side panel instead of pushed
  /// as its own full-screen route — skips the AppBar (the panel supplies
  /// its own chrome) since there's nothing to "back" out of.
  final bool embedded;

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

  User? _user;
  bool _authBusy = false;
  bool _syncBusy = false;
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    _load();
    _user = AuthService.instance.currentUser;
    _subscribeToAuthState();
    AuthService.instance.availableNotifier.addListener(_onAuthAvailable);
    // Reload when the mark library changes — including a background restore
    // from the cloud after sign-in — so restored signatures appear without
    // reopening the screen.
    MarksService.revision.addListener(_onMarksChanged);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    AuthService.instance.availableNotifier.removeListener(_onAuthAvailable);
    MarksService.revision.removeListener(_onMarksChanged);
    super.dispose();
  }

  void _onMarksChanged() {
    if (mounted) _load();
  }

  // Firebase.initializeApp() in main() completes asynchronously, often after
  // this screen's first build — re-subscribe once it's actually ready so the
  // "not available yet" card doesn't get stuck showing forever (the stream
  // we subscribed to in initState was Stream.empty() until now).
  void _onAuthAvailable() {
    if (!mounted) return;
    _authSub?.cancel();
    _subscribeToAuthState();
    setState(() => _user = AuthService.instance.currentUser);
  }

  void _subscribeToAuthState() {
    _authSub = AuthService.instance.authStateChanges.listen((user) {
      if (mounted) setState(() => _user = user);
    });
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

  /// Honest status instead of a sign-in button that can't actually work yet
  /// — shown only while firebase_options.dart is still the placeholder (see
  /// FIREBASE_AUTH_SETUP.md), so nobody taps a button that silently fails.
  Future<void> _showSignInInfo() async {
    final s = S.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.account_circle_outlined, size: 32),
        title: Text(s['signInComingSoonTitle']),
        content: Text(
          s['signInComingSoonBody'],
          style: const TextStyle(fontSize: 15, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(s['done']),
          ),
        ],
      ),
    );
  }

  bool get _appleSignInSupported => !kIsWeb && Platform.isIOS;

  Future<void> _signInWithGoogle() =>
      _runAuthAction(AuthService.instance.signInWithGoogle);

  Future<void> _signInWithApple() =>
      _runAuthAction(AuthService.instance.signInWithApple);

  Future<void> _runAuthAction(Future<void> Function() action) async {
    if (_authBusy) return;
    setState(() => _authBusy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) _snack('${S.of(context)['signInFailed']}: $e');
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  Future<void> _signOut() async {
    if (_authBusy) return;
    setState(() => _authBusy = true);
    try {
      await AuthService.instance.signOut();
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  /// Pushes the signature/stamp library to the account on demand and reports
  /// the exact outcome — a success count, or the precise Firebase error (the
  /// common ones being Firestore/Storage not enabled or rules not deployed).
  Future<void> _syncNow() async {
    if (_syncBusy) return;
    setState(() => _syncBusy = true);
    final result = await CloudSyncService.instance.syncNow();
    if (!mounted) return;
    setState(() => _syncBusy = false);
    final s = S.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(result.ok ? s['syncOkTitle'] : s['syncFailedTitle']),
        content: Text(result.message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s['close']),
          ),
        ],
      ),
    );
  }

  /// Counts what's actually in the exported bundle right now — shown in the
  /// confirmation so a backup visibly proves it isn't empty, instead of a
  /// bare "saved" that looks identical whether it worked or not.
  String _markCountText(S s) {
    final total = _signatures.length + _stamps.length + _combos.length;
    return s['backupItemCount'].replaceAll('{n}', '$total');
  }

  Future<void> _exportBackup() async {
    final s = S.of(context);
    await _settings.setName(_nameController.text);
    final bundle = await _settings.exportBundle();
    final saved = await _shareService.saveAs(bundle, 'quicksign-backup.json');
    if (saved && mounted) {
      _snack('${s['backupSaved']} — ${_markCountText(s)}');
    }
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
      ok
          ? '${s['savedToDefaultFolder']} — $_folderName · ${_markCountText(s)}'
          : s['backupError'],
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
    final before = _signatures.length + _stamps.length + _combos.length;
    try {
      await _settings.importBundle(bytes);
      await _load();
      if (!mounted) return;
      final after = _signatures.length + _stamps.length + _combos.length;
      final added = after - before;
      _snack(
        '${s['backupRestored']} — ${s['backupItemsAdded'].replaceAll('{n}', '$added')}',
      );
    } on FormatException {
      if (mounted) _snack(s['backupError']);
    }
  }

  // ── Marks (signatures / stamps) ────────────────────────────────────────

  Future<void> _addSignature() async {
    if (await _marksService.atCapacity(MarkType.signature)) {
      if (mounted) _snack(S.of(context)['marksLimitReached']);
      return;
    }
    final bytes = await showDrawCanvasSheet(context);
    if (bytes == null || !mounted) return;
    try {
      await _marksService.add(
        type: MarkType.signature,
        name: '${S.of(context)['sign']} ${_signatures.length + 1}',
        imageBytes: bytes,
      );
    } on MarksLimitException {
      if (mounted) _snack(S.of(context)['marksLimitReached']);
      return;
    }
    await _load();
  }

  Future<void> _redrawSignature(SavedMark mark) async {
    final bytes = await showDrawCanvasSheet(context);
    if (bytes == null || !mounted) return;
    await _marksService.update(mark.id, imageBytes: bytes);
    await _load();
  }

  Future<void> _addStamp() async {
    if (await _marksService.atCapacity(MarkType.stamp)) {
      if (mounted) _snack(S.of(context)['marksLimitReached']);
      return;
    }
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
          ElevatedButton(
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
    if (await _marksService.atCapacity(MarkType.combo)) {
      if (mounted) _snack(s['marksLimitReached']);
      return;
    }
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
    try {
      await _marksService.add(
        type: MarkType.combo,
        name: '${s['sign']}+${s['stamp']} ${_combos.length + 1}',
        imageBytes: bytes,
      );
    } on MarksLimitException {
      if (mounted) _snack(s['marksLimitReached']);
      return;
    }
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
    // Warn before deleting — when signed in, the delete also propagates to the
    // account (cloud) on every device, permanently, so confirm intent first.
    final signedIn = AuthService.instance.currentUser != null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s['deleteConfirmTitle']),
        content: Text(
          signedIn ? s['deleteConfirmCloudBody'] : s['deleteConfirmBody'],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s['cancel']),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s['delete']),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _marksService.delete(mark.id);
    // Propagate the delete to the account so it doesn't reappear on next sync.
    unawaited(CloudSyncService.instance.deleteMark(mark.id));
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
              // Restore locally; the debounced push re-adds it to the account.
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

  Widget _buildAccountSection(S s, ColorScheme scheme) {
    if (!AuthService.instance.isAvailable) {
      return Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: Icon(
            Icons.account_circle_outlined,
            color: scheme.onSurfaceVariant,
          ),
          title: Text(s['signInWithGoogle']),
          subtitle: Text(
            s['signInComingSoonSub'],
            style: const TextStyle(fontSize: 13),
          ),
          trailing: const Icon(Icons.info_outline, size: 20),
          onTap: _showSignInInfo,
        ),
      );
    }

    final user = _user;
    if (user != null) {
      return Card(
        margin: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundImage: user.photoURL != null
                    ? NetworkImage(user.photoURL!)
                    : null,
                child: user.photoURL == null
                    ? const Icon(Icons.person_outline)
                    : null,
              ),
              title: Text(
                user.displayName ?? user.email ?? s['account'],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (user.email != null)
                    Text(
                      user.email!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // The email has no spaces to wrap at, so a squeezed row
                      // (avatar + sign-out button both take space) used to
                      // break it mid-word instead of truncating cleanly.
                      textDirection: TextDirection.ltr,
                    ),
                  Text(
                    s['cloudSyncActive'],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: scheme.primary),
                  ),
                ],
              ),
              trailing: _authBusy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton(onPressed: _signOut, child: Text(s['signOut'])),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: 8,
                  bottom: 4,
                ),
                child: _syncBusy
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : TextButton.icon(
                        onPressed: _syncNow,
                        icon: const Icon(Icons.cloud_sync_outlined, size: 18),
                        label: Text(s['syncNow']),
                      ),
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              Icons.account_circle_outlined,
              color: scheme.onSurfaceVariant,
            ),
            title: Text(s['signInWithGoogle']),
            trailing: _authBusy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _authBusy ? null : _signInWithGoogle,
          ),
          if (_appleSignInSupported) ...[
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.apple, color: scheme.onSurfaceVariant),
              title: Text(s['signInWithApple']),
              trailing: _authBusy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _authBusy ? null : _signInWithApple,
            ),
          ],
          // Developer diagnostics only — never shown in a release/store
          // build (gated on kDebugMode). On-device users get the "Sync now"
          // button above, which surfaces any error on demand in a dialog.
          ValueListenableBuilder<List<String>>(
            valueListenable: AuthService.instance.debugLog,
            builder: (context, log, _) {
              if (log.isEmpty || !kDebugMode) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  log.join('\n'),
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: Text(s['settings'])),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              // Add the system bottom inset (Android nav bar / gesture area)
              // so the last section (About) isn't hidden behind it.
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.of(context).padding.bottom,
              ),
              children: [
                _SectionTitle(s['profile'], icon: Icons.person_outline),
                TextField(
                  controller: _nameController,
                  style: const TextStyle(fontSize: 18),
                  decoration: InputDecoration(
                    labelText: s['profileName'],
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  onSubmitted: _settings.setName,
                ),
                const SizedBox(height: 24),
                _SectionTitle(s['account'], icon: Icons.shield_outlined),
                _buildAccountSection(s, scheme),
                const SizedBox(height: 24),
                _SectionTitle(s['savedSignatures'], icon: Icons.draw_outlined),
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
                _SectionTitle(s['savedStamps'], icon: Icons.approval_outlined),
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
                _SectionTitle(s['savedCombos'], icon: Icons.layers_outlined),
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
                  _SectionTitle(
                    s['defaultFolder'],
                    icon: Icons.folder_open_outlined,
                  ),
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
                _SectionTitle(s['backup'], icon: Icons.cloud_upload_outlined),
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
                _SectionTitle(s['about'], icon: Icons.info_outline),
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
  const _SectionTitle(this.title, {this.icon});

  final String title;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: DesignTokens.primarySoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 15, color: DesignTokens.primaryDeep),
            ),
            const SizedBox(width: 9),
          ],
          Text(
            title,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: DesignTokens.ink,
              letterSpacing: -0.1,
            ),
          ),
        ],
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
    return Container(
      decoration: BoxDecoration(
        color: DesignTokens.surfaceCard,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        border: isDefault
            ? Border.all(color: DesignTokens.primary, width: 1.6)
            : null,
        boxShadow: DesignTokens.shadowSm,
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
              child: Container(
                width: 88,
                height: 56,
                color: DesignTokens.surfaceMuted,
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
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                onTap: onRename,
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        mark.name,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          color: DesignTokens.ink,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.edit, size: 13, color: DesignTokens.textFaint),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: isDefault ? s['unsetDefault'] : s['setDefault'],
              onPressed: onToggleDefault,
              icon: Icon(
                isDefault ? Icons.star_rounded : Icons.star_outline_rounded,
                color: isDefault
                    ? DesignTokens.primary
                    : DesignTokens.textFaint,
              ),
            ),
            IconButton(
              tooltip: editTooltip,
              onPressed: onEdit,
              icon: Icon(editIcon, color: DesignTokens.iconStroke),
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
        ElevatedButton(
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
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: DesignTokens.primarySoft,
            borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: DesignTokens.primarySoftStrong,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add,
                    size: 18,
                    color: DesignTokens.primaryDeep,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: DesignTokens.primaryDeep,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
