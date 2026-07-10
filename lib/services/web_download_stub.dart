import 'dart:typed_data';

/// Non-web platforms never call this — sharing/saving goes through the
/// system share sheet and the system save dialog instead.
Future<void> downloadBytes(Uint8List bytes, String fileName) async {
  throw UnsupportedError('Browser download is only available on the web');
}
