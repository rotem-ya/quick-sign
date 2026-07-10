import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'stamp_service.dart';

/// Local profile + portable backup of everything personal in the app.
///
/// The backup file is a small JSON bundle (name, stamp, saved signature)
/// that the user can keep anywhere — including a Drive/OneDrive folder —
/// and restore on any device or platform. This gives cross-device transfer
/// without accounts or servers, complementing Android's automatic backup.
class SettingsService {
  static const _nameKey = 'profile_name';
  static const _bundleApp = 'quicksign';
  static const _bundleVersion = 1;

  final StampService _stampService = StampService();

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
    final stamp = await _stampService.getStampBytes();
    final signature = await _stampService.getSignatureBytes();
    final bundle = <String, Object>{
      'app': _bundleApp,
      'version': _bundleVersion,
      'name': ?await getName(),
      'stamp': ?stamp == null ? null : base64Encode(stamp),
      'signature': ?signature == null ? null : base64Encode(signature),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(bundle)));
  }

  /// Restores a bundle produced by [exportBundle]. Throws [FormatException]
  /// on anything that isn't a QuickSign backup.
  Future<void> importBundle(Uint8List bytes) async {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic> || decoded['app'] != _bundleApp) {
      throw const FormatException('Not a QuickSign backup');
    }
    if (decoded['name'] is String) {
      await setName(decoded['name'] as String);
    }
    if (decoded['stamp'] is String) {
      await _stampService.saveStamp(base64Decode(decoded['stamp'] as String));
    }
    if (decoded['signature'] is String) {
      await _stampService
          .saveSignature(base64Decode(decoded['signature'] as String));
    }
  }
}
