import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Sends the signed document back out — system share sheet (WhatsApp, mail,
/// save to Files…) or a local copy inside the app.
class ShareService {
  Future<void> shareFile(String path) async {
    await Share.shareXFiles([XFile(path, mimeType: 'application/pdf')]);
  }

  /// Copies the signed PDF into the app's documents folder and returns the
  /// saved path.
  Future<String> saveCopy(String path) async {
    final dir = await getApplicationDocumentsDirectory();
    final signedDir = Directory('${dir.path}/signed');
    await signedDir.create(recursive: true);
    final name = path.split(Platform.pathSeparator).last;
    final target = File('${signedDir.path}/$name');
    await File(path).copy(target.path);
    return target.path;
  }
}
