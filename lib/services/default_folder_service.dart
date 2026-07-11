import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show MethodChannel, PlatformException;

/// A persisted "save straight here" folder — one picked by the user through
/// the system folder picker (Storage Access Framework).
///
/// This is how QuickSign "connects to Drive/OneDrive" without any OAuth: the
/// Drive/OneDrive/Dropbox apps each register as a SAF document provider, so
/// they show up as folders in the same system picker used for local storage.
/// Once granted, the permission is persistent — the app can write there
/// again after a restart or a reinstall of QuickSign (not of the Drive app)
/// without asking again. Android only; iOS/web fall back to "Save to…".
class DefaultFolderService {
  static const MethodChannel _channel =
      MethodChannel('quick_sign/default_folder');

  static bool get isSupported => !kIsWeb;

  /// Opens the system folder picker. Returns the folder's display name once
  /// chosen, or null if unsupported / the user cancelled.
  Future<String?> pickFolder() async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>('pickFolder');
    } on PlatformException {
      return null;
    }
  }

  /// The currently remembered folder's display name, or null if none is set
  /// (or the grant is no longer valid).
  Future<String?> folderName() async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>('folderName');
    } on PlatformException {
      return null;
    }
  }

  Future<void> clearFolder() async {
    if (!isSupported) return;
    await _channel.invokeMethod('clearFolder');
  }

  /// Writes [bytes] as [fileName] into the default folder. Returns true on
  /// success; false when no folder is set or the write failed.
  Future<bool> saveFile(Uint8List bytes, String fileName) async {
    if (!isSupported) return false;
    try {
      final uri = await _channel.invokeMethod<String>('saveFile', {
        'fileName': fileName,
        'bytes': bytes,
      });
      return uri != null;
    } on PlatformException {
      return false;
    }
  }
}
