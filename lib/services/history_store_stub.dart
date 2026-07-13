import 'dart:typed_data';

// Never called on native — HistoryService stores bytes as real files there.
Future<void> putHistoryBytes(String key, Uint8List bytes) =>
    throw UnsupportedError('IndexedDB history store is web-only');

Future<Uint8List?> getHistoryBytes(String key) =>
    throw UnsupportedError('IndexedDB history store is web-only');

Future<void> deleteHistoryBytes(String key) =>
    throw UnsupportedError('IndexedDB history store is web-only');
