import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../models/library_file.dart';

/// Folder browsing on web via the File System Access API
/// (`showDirectoryPicker`), which `package:web` doesn't bind — it's a
/// Chromium-only extension, not yet part of the generated WHATWG bindings —
/// so the picker call and directory iteration go through
/// `dart:js_interop_unsafe` instead of typed externs.
///
/// Handles are kept in memory only, keyed by a synthetic id: they're
/// structured-cloneable and *could* be persisted in IndexedDB across
/// reloads, but the browser still requires a fresh user-gesture permission
/// re-grant after every reload regardless — so persisting them would only
/// save re-typing a folder name, not another click. Not worth the added
/// storage/permission-revalidation complexity for v1; folders are re-picked
/// each session.
bool get isSupported =>
    (web.window as JSObject).hasProperty('showDirectoryPicker'.toJS).toDart;

final Map<String, web.FileSystemDirectoryHandle> _handles = {};
int _nextId = 0;

Future<LibraryFolder?> pickFolder() async {
  if (!isSupported) return null;
  try {
    final promise =
        (web.window as JSObject).callMethod('showDirectoryPicker'.toJS)
            as JSPromise;
    final handle = (await promise.toDart) as web.FileSystemDirectoryHandle;
    final id = 'web-${_nextId++}';
    _handles[id] = handle;
    return LibraryFolder(id: id, name: handle.name);
  } catch (_) {
    return null; // user cancelled the picker, or it's unsupported here
  }
}

Future<List<LibraryFolder>> listFolders() async => _handles.entries
    .map((e) => LibraryFolder(id: e.key, name: e.value.name))
    .toList();

Future<void> removeFolder(String id) async {
  _handles.remove(id);
}

Future<List<LibraryFile>> listFiles(String folderId) async {
  final handle = _handles[folderId];
  if (handle == null) return const [];

  final files = <LibraryFile>[];
  final iterator =
      (handle as JSObject).callMethod('entries'.toJS) as JSObject;
  while (true) {
    final next = await ((iterator.callMethod('next'.toJS) as JSPromise)
            .toDart)
        as JSObject;
    final done = next.getProperty('done'.toJS) as JSBoolean;
    if (done.toDart) break;

    final entry = next.getProperty('value'.toJS) as JSArray;
    final name = (entry[0] as JSString).toDart;
    final childHandle = entry[1] as JSObject;
    final kind = (childHandle.getProperty('kind'.toJS) as JSString).toDart;
    if (kind != 'file') continue;

    final fileHandle = childHandle as web.FileSystemFileHandle;
    final jsFile = await fileHandle.getFile().toDart;
    files.add(
      LibraryFile(
        id: '$folderId::$name',
        folderId: folderId,
        name: name,
        sizeBytes: jsFile.size,
        modified: DateTime.fromMillisecondsSinceEpoch(jsFile.lastModified),
      ),
    );
  }
  return files;
}

Future<Uint8List?> readFile(String fileId) async {
  final separator = fileId.indexOf('::');
  if (separator < 0) return null;
  final handle = _handles[fileId.substring(0, separator)];
  if (handle == null) return null;
  final name = fileId.substring(separator + 2);

  try {
    final fileHandle = await handle.getFileHandle(name).toDart;
    final jsFile = await fileHandle.getFile().toDart;
    final buffer = await jsFile.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  } catch (_) {
    return null;
  }
}
