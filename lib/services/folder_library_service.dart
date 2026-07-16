import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show MethodChannel;

import '../models/library_file.dart';
import 'folder_library_stub.dart'
    if (dart.library.js_interop) 'folder_library_web.dart'
    as web_lib;

/// Read-only access to folders the user has explicitly picked (any number
/// of them) — lists the PDFs/images inside so they can be opened straight
/// from QuickSign. The read counterpart to [DefaultFolderService]'s
/// write-only "save here" folder, same trick on Android: Drive/OneDrive/
/// Dropbox all register as Storage Access Framework document providers, so
/// picking "a folder inside Drive" works with no OAuth. Web uses the File
/// System Access API where the browser supports it (Chromium-based only);
/// iOS isn't wired up yet.
class FolderLibraryService {
  static const MethodChannel _channel = MethodChannel(
    'quick_sign/folder_library',
  );

  static bool get isSupported => kIsWeb ? web_lib.isSupported : true;

  Future<LibraryFolder?> pickFolder() async {
    if (!isSupported) return null;
    if (kIsWeb) return web_lib.pickFolder();
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'pickFolder',
      );
      if (result == null) return null;
      return LibraryFolder(
        id: result['uri'] as String,
        name: result['name'] as String,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<LibraryFolder>> listFolders() async {
    if (!isSupported) return const [];
    if (kIsWeb) return web_lib.listFolders();
    try {
      final result = await _channel.invokeListMethod<Map>('listFolders');
      if (result == null) return const [];
      return result
          .map(
            (m) => LibraryFolder(
              id: m['uri'] as String,
              name: m['name'] as String,
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> removeFolder(String id) async {
    if (!isSupported) return;
    if (kIsWeb) return web_lib.removeFolder(id);
    try {
      await _channel.invokeMethod('removeFolder', {'uri': id});
    } catch (_) {
      // Best-effort — nothing sensible to surface to the caller.
    }
  }

  Future<List<LibraryFile>> listFiles(LibraryFolder folder) async {
    if (!isSupported) return const [];
    if (kIsWeb) return web_lib.listFiles(folder.id);
    try {
      final result = await _channel.invokeListMethod<Map>('listFiles', {
        'uri': folder.id,
      });
      if (result == null) return const [];
      return result.map((m) {
        return LibraryFile(
          id: m['uri'] as String,
          folderId: folder.id,
          name: m['name'] as String,
          sizeBytes: (m['size'] as num).toInt(),
          modified: DateTime.fromMillisecondsSinceEpoch(
            (m['lastModified'] as num).toInt(),
          ),
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<Uint8List?> readFile(LibraryFile file) async {
    if (!isSupported) return null;
    if (kIsWeb) return web_lib.readFile(file.id);
    try {
      return await _channel.invokeMethod<Uint8List>('readFile', {
        'uri': file.id,
      });
    } catch (_) {
      return null;
    }
  }
}
