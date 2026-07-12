import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/saved_mark.dart';
import 'marks_service.dart';

/// Local profile + portable backup of everything personal in the app.
///
/// The backup file is a small JSON bundle (name, every saved signature/
/// stamp/combo, and their defaults) that the user can keep anywhere —
/// including a Drive/OneDrive folder — and restore on any device or
/// platform. This gives cross-device transfer without accounts or servers,
/// complementing Android's automatic backup.
class SettingsService {
  static const _nameKey = 'profile_name';
  static const _bundleApp = 'quicksign';
  static const _bundleVersion = 2;

  final MarksService _marksService = MarksService();

  Future<String?> getName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_nameKey)?.trim();
    return (name == null || name.isEmpty) ? null : name;
  }

  Future<void> setName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      await prefs.remove(_nameKey);
    } else {
      await prefs.setString(_nameKey, trimmed);
    }
  }

  /// Everything personal, as a portable JSON file.
  Future<Uint8List> exportBundle() async {
    final marks = await _marksService.list();
    final defaults = <String, String>{};
    for (final type in MarkType.values) {
      final id = (await _marksService.getDefault(type))?.id;
      if (id != null) defaults[type.name] = id;
    }
    final bundle = <String, Object?>{
      'app': _bundleApp,
      'version': _bundleVersion,
      'name': ?await getName(),
      'marks': marks.map((m) => m.toJson()).toList(),
      'defaults': defaults,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(bundle)));
  }

  /// Restores a bundle produced by [exportBundle]. Throws [FormatException]
  /// on anything that isn't a QuickSign backup. Marks are added as fresh
  /// copies (new ids) rather than reusing the bundle's ids, so restoring
  /// the same backup twice — or onto a device that already has marks —
  /// never collides.
  Future<void> importBundle(Uint8List bytes) async {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic> || decoded['app'] != _bundleApp) {
      throw const FormatException('Not a QuickSign backup');
    }
    if (decoded['name'] is String) {
      await setName(decoded['name'] as String);
    }

    final rawMarks = decoded['marks'];
    if (rawMarks is List) {
      final idMap = <String, String>{};
      for (final item in rawMarks) {
        if (item is! Map<String, dynamic>) continue;
        final mark = SavedMark.fromJson(item);
        if (mark == null) continue;
        final added = await _marksService.add(
          type: mark.type,
          name: mark.name,
          imageBytes: mark.imageBytes,
          design: mark.design,
        );
        idMap[mark.id] = added.id;
      }
      final defaults = decoded['defaults'];
      if (defaults is Map<String, dynamic>) {
        for (final entry in defaults.entries) {
          final newId = idMap[entry.value];
          if (newId == null) continue;
          try {
            await _marksService.setDefault(
              MarkType.values.byName(entry.key),
              newId,
            );
          } catch (_) {
            // Unknown mark type in an old/foreign bundle — skip it.
          }
        }
      }
    } else {
      // Legacy (version 1) bundle: one signature, one stamp, no names.
      final stamp = decoded['stamp'];
      if (stamp is String) {
        await _marksService.add(
          type: MarkType.stamp,
          name: 'חותמת',
          imageBytes: base64Decode(stamp),
        );
      }
      final signature = decoded['signature'];
      if (signature is String) {
        await _marksService.add(
          type: MarkType.signature,
          name: 'חתימה',
          imageBytes: base64Decode(signature),
        );
      }
    }
  }
}
