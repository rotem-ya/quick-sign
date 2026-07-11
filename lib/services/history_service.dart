import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/history_entry.dart';

/// Keeps a permanent local copy of every signed document, independent of the
/// temp file used for share/print — a copy in the app's own documents
/// directory that survives until the user deletes it from the History
/// screen. Never uploaded anywhere; this is on-device storage only.
///
/// File-based, so it stays mobile-only (web has no equivalent persistent
/// filesystem) — matches [DefaultFolderService].
class HistoryService {
  static const _indexKey = 'history_index';

  static bool get isSupported => !kIsWeb;

  Future<Directory> _historyDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/history');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// All entries, newest first. Entries whose file no longer exists (e.g.
  /// storage was cleared outside the app) are dropped and the index is
  /// rewritten so it stays truthful.
  Future<List<HistoryEntry>> list() async {
    if (!isSupported) return const [];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_indexKey);
    if (raw == null) return const [];

    final decoded = jsonDecode(raw) as List<dynamic>;
    final entries = <HistoryEntry>[];
    for (final item in decoded) {
      final entry = HistoryEntry.fromJson(item as Map<String, dynamic>);
      if (entry != null && await File(entry.filePath).exists()) {
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
    final dir = await _historyDir();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final safeName = fileName.replaceAll(RegExp(r'[/\\]'), '_');
    final file = File('${dir.path}/$id-$safeName');
    await file.writeAsBytes(bytes, flush: true);

    final entry = HistoryEntry(
      id: id,
      fileName: fileName,
      savedAt: DateTime.now(),
      pageCount: pageCount,
      sizeBytes: bytes.length,
      filePath: file.path,
    );
    final current = await list();
    await _saveIndex([entry, ...current]);
    return entry;
  }

  Future<Uint8List?> readBytes(HistoryEntry entry) async {
    final file = File(entry.filePath);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  Future<void> delete(HistoryEntry entry) async {
    final current = await list();
    await _saveIndex(current.where((e) => e.id != entry.id).toList());
    final file = File(entry.filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Re-creates an entry removed by [delete], using bytes captured just
  /// before the deletion — the "Undo" action on the delete snackbar.
  Future<void> restore(HistoryEntry entry, Uint8List bytes) async {
    await File(entry.filePath).writeAsBytes(bytes, flush: true);
    final current = await list();
    await _saveIndex([entry, ...current]);
  }

  Future<void> _saveIndex(List<HistoryEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _indexKey,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }
}
