import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/history_entry.dart';
import 'history_store_stub.dart'
    if (dart.library.js_interop) 'history_store_web.dart'
    as web_store;

/// Keeps a permanent local copy of every signed document, independent of the
/// temp file used for share/print — persisted until the user deletes it from
/// the History screen. Never uploaded anywhere; this is on-device/in-browser
/// storage only.
///
/// Native: a real file in the app's own documents directory, tracked by
/// [HistoryEntry.filePath]. Web has no filesystem, so bytes go into
/// IndexedDB instead (see history_store_web.dart), keyed by [HistoryEntry.id]
/// — [HistoryEntry.filePath] holds that key on web, not an actual path.
/// Either way the small JSON index (name/date/size/page count) lives in
/// shared_preferences, which already works on both platforms.
class HistoryService {
  static const _indexKey = 'history_index';

  static bool get isSupported => true;

  Future<Directory> _historyDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/history');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// All entries, newest first. On native, entries whose file no longer
  /// exists (e.g. storage was cleared outside the app) are dropped and the
  /// index is rewritten so it stays truthful — skipped on web, where
  /// checking would mean one extra IndexedDB round-trip per entry.
  Future<List<HistoryEntry>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_indexKey);
    if (raw == null) return const [];

    final decoded = jsonDecode(raw) as List<dynamic>;
    final entries = <HistoryEntry>[];
    for (final item in decoded) {
      final entry = HistoryEntry.fromJson(item as Map<String, dynamic>);
      if (entry == null) continue;
      if (kIsWeb || await File(entry.filePath).exists()) {
        entries.add(entry);
      }
    }
    entries.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    if (entries.length != decoded.length) {
      await _saveIndex(entries);
    }
    return entries;
  }

  /// Saves [bytes] as a new permanent history entry.
  Future<HistoryEntry> record({
    required Uint8List bytes,
    required String fileName,
    required int pageCount,
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final storageRef = await _write(id, fileName, bytes);

    final entry = HistoryEntry(
      id: id,
      fileName: fileName,
      savedAt: DateTime.now(),
      pageCount: pageCount,
      sizeBytes: bytes.length,
      filePath: storageRef,
    );
    final current = await list();
    await _saveIndex([entry, ...current]);
    return entry;
  }

  Future<Uint8List?> readBytes(HistoryEntry entry) async {
    if (kIsWeb) return web_store.getHistoryBytes(entry.filePath);
    final file = File(entry.filePath);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  Future<void> delete(HistoryEntry entry) async {
    final current = await list();
    await _saveIndex(current.where((e) => e.id != entry.id).toList());
    if (kIsWeb) {
      await web_store.deleteHistoryBytes(entry.filePath);
      return;
    }
    final file = File(entry.filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Re-creates an entry removed by [delete], using bytes captured just
  /// before the deletion — the "Undo" action on the delete snackbar.
  Future<void> restore(HistoryEntry entry, Uint8List bytes) async {
    if (kIsWeb) {
      await web_store.putHistoryBytes(entry.filePath, bytes);
    } else {
      await File(entry.filePath).writeAsBytes(bytes, flush: true);
    }
    final current = await list();
    await _saveIndex([entry, ...current]);
  }

  /// Writes [bytes] to storage and returns the value to keep in
  /// [HistoryEntry.filePath] — an IndexedDB key on web, a real file path
  /// on native.
  Future<String> _write(String id, String fileName, Uint8List bytes) async {
    if (kIsWeb) {
      await web_store.putHistoryBytes(id, bytes);
      return id;
    }
    final dir = await _historyDir();
    final safeName = fileName.replaceAll(RegExp(r'[/\\]'), '_');
    final file = File('${dir.path}/$id-$safeName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> _saveIndex(List<HistoryEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _indexKey,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }
}
