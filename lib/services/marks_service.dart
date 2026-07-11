import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/saved_mark.dart';
import '../models/stamp_design.dart';
import 'stamp_service.dart';

/// A named library of saved signatures and stamps — any number of each, with
/// rename / edit / delete, replacing the old "exactly one signature, one
/// stamp" model.
///
/// Stored as JSON (with images as base64) in SharedPreferences: works
/// identically on every platform, including web, and rides Android's
/// automatic backup like the single-item version did before it.
class MarksService {
  static const _key = 'saved_marks_v1';
  static const _migratedKey = 'saved_marks_migrated_v1';

  Future<List<SavedMark>> list({MarkType? type}) async {
    await _migrateLegacyIfNeeded();
    final all = await _readAll();
    if (type == null) return all;
    return all.where((m) => m.type == type).toList();
  }

  Future<SavedMark> add({
    required MarkType type,
    required String name,
    required Uint8List imageBytes,
    StampDesign? design,
  }) async {
    final mark = SavedMark(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: type,
      name: name,
      imageBytes: imageBytes,
      design: design,
    );
    final current = await list();
    await _writeAll([...current, mark]);
    return mark;
  }

  Future<void> update(
    String id, {
    String? name,
    Uint8List? imageBytes,
    StampDesign? design,
    bool clearDesign = false,
  }) async {
    final current = await list();
    for (final mark in current) {
      if (mark.id != id) continue;
      if (name != null) mark.name = name;
      if (imageBytes != null) mark.imageBytes = imageBytes;
      if (clearDesign) {
        mark.design = null;
      } else if (design != null) {
        mark.design = design;
      }
    }
    await _writeAll(current);
  }

  Future<void> delete(String id) async {
    final current = await list();
    await _writeAll(current.where((m) => m.id != id).toList());
  }

  /// Re-adds a mark removed by [delete] — backs the delete-snackbar "Undo".
  Future<void> restore(SavedMark mark) async {
    final current = await list();
    await _writeAll([...current, mark]);
  }

  Future<List<SavedMark>> _readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    final marks = <SavedMark>[];
    for (final item in decoded) {
      final mark = SavedMark.fromJson(item as Map<String, dynamic>);
      if (mark != null) marks.add(mark);
    }
    return marks;
  }

  Future<void> _writeAll(List<SavedMark> marks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(marks.map((m) => m.toJson()).toList()));
  }

  /// One-time upgrade from the old single-signature/single-stamp storage
  /// (StampService's `signature_png_b64` / `stamp_png_b64`), so nobody's
  /// existing signature disappears when this version installs.
  Future<void> _migrateLegacyIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_migratedKey) == true) return;
    await prefs.setBool(_migratedKey, true);

    final legacy = StampService();
    final signature = await legacy.getSignatureBytes();
    final stamp = await legacy.getStampBytes();
    if (signature == null && stamp == null) return;

    final existing = await _readAll();
    if (signature != null) {
      existing.add(SavedMark(
        id: 'legacy-signature',
        type: MarkType.signature,
        name: 'החתימה שלי',
        imageBytes: signature,
      ));
    }
    if (stamp != null) {
      existing.add(SavedMark(
        id: 'legacy-stamp',
        type: MarkType.stamp,
        name: 'החותמת שלי',
        imageBytes: stamp,
      ));
    }
    await _writeAll(existing);
    await legacy.removeSignature();
    await legacy.removeStamp();
  }
}
