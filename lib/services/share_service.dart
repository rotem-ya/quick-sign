import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'web_download_stub.dart'
    if (dart.library.js_interop) 'web_download_web.dart' as web_download;

/// Sends the signed document back out.
///
/// - Share: the system share sheet (WhatsApp, mail, …). Mobile only.
/// - Save to…: the system save dialog. On Android this is the Storage Access
///   Framework, so the user can save straight into Google Drive, OneDrive,
///   Dropbox or any shared folder — no accounts or API keys in the app, and
///   the document still never passes through our servers (we have none).
/// - On the web both actions become a browser download.
class ShareService {
  /// True when the platform has a native share sheet.
  static bool get canShare => !kIsWeb;

  Future<void> shareBytes(Uint8List bytes, String fileName) async {
    if (kIsWeb) {
      await web_download.downloadBytes(bytes, fileName);
      return;
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(file.path, mimeType: 'application/pdf')]);
  }

  /// Opens the system "save to…" dialog (Drive / OneDrive / shared folders /
  /// device storage). Returns true when the file was saved, false on cancel.
  Future<bool> saveAs(Uint8List bytes, String fileName) async {
    if (kIsWeb) {
      await web_download.downloadBytes(bytes, fileName);
      return true;
    }
    final path = await FilePicker.platform.saveFile(
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      bytes: bytes,
    );
    return path != null;
  }
}
