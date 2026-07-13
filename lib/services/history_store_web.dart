import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Raw byte storage for [HistoryService] on web, via IndexedDB — the only
/// browser storage with no realistic size ceiling for PDF-sized blobs
/// (unlike localStorage/shared_preferences, which this app already uses for
/// the small JSON index of entries). One database, one object store,
/// entries keyed by [HistoryEntry.id].
const _dbName = 'quicksign_history';
const _storeName = 'files';
const _dbVersion = 1;

web.IDBDatabase? _dbCache;

Future<web.IDBDatabase> _openDb() {
  final cached = _dbCache;
  if (cached != null) return Future.value(cached);

  final completer = Completer<web.IDBDatabase>();
  final request = web.window.indexedDB.open(_dbName, _dbVersion);

  request.onupgradeneeded = ((web.Event _) {
    final db = request.result as web.IDBDatabase;
    if (!db.objectStoreNames.contains(_storeName)) {
      db.createObjectStore(_storeName);
    }
  }).toJS;
  request.onsuccess = ((web.Event _) {
    final db = request.result as web.IDBDatabase;
    _dbCache = db;
    completer.complete(db);
  }).toJS;
  request.onerror = ((web.Event _) {
    completer.completeError(request.error?.message ?? 'IndexedDB open failed');
  }).toJS;

  return completer.future;
}

Future<web.IDBObjectStore> _store(String mode) async {
  final db = await _openDb();
  final tx = db.transaction(_storeName.toJS, mode);
  return tx.objectStore(_storeName);
}

Future<void> putHistoryBytes(String key, Uint8List bytes) async {
  final store = await _store('readwrite');
  final completer = Completer<void>();
  // Stored as base64 text, not the raw TypedArray — storing a Uint8Array
  // directly (via .toJS, a zero-copy view over Dart's own memory) reopened
  // reliably fine on its own, but reopening a document read back this way
  // reproducibly hung pdf.js's *render* call forever afterwards (confirmed:
  // identical bytes reopened via the file picker never hang, only ones
  // that round-tripped through IndexedDB as a TypedArray did — even a
  // full copy on the read side didn't help, so something about the stored
  // TypedArray/ArrayBuffer itself seems to be the trigger). A plain string
  // has none of that ambiguity in structured-clone/JS-interop.
  final request = store.put(base64Encode(bytes).toJS, key.toJS);
  request.onsuccess = ((web.Event _) {
    completer.complete();
  }).toJS;
  request.onerror = ((web.Event _) {
    completer.completeError(request.error?.message ?? 'put failed');
  }).toJS;
  return completer.future;
}

Future<Uint8List?> getHistoryBytes(String key) async {
  final store = await _store('readonly');
  final completer = Completer<Uint8List?>();
  final request = store.get(key.toJS);
  request.onsuccess = ((web.Event _) {
    final result = request.result;
    completer.complete(
      result == null ? null : base64Decode((result as JSString).toDart),
    );
  }).toJS;
  request.onerror = ((web.Event _) {
    completer.completeError(request.error?.message ?? 'get failed');
  }).toJS;
  return completer.future;
}

Future<void> deleteHistoryBytes(String key) async {
  final store = await _store('readwrite');
  final completer = Completer<void>();
  final request = store.delete(key.toJS);
  request.onsuccess = ((web.Event _) {
    completer.complete();
  }).toJS;
  request.onerror = ((web.Event _) {
    completer.completeError(request.error?.message ?? 'delete failed');
  }).toJS;
  return completer.future;
}
