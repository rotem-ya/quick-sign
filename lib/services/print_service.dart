import 'dart:typed_data';

import 'package:printing/printing.dart';

/// Sends the signed PDF to the system print dialog (AirPrint / Android print
/// service / the browser's print preview on the web).
class PrintService {
  Future<void> printPdf(Uint8List bytes, String fileName) async {
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: fileName,
    );
  }
}
