import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Parameters for [StampService.cropAndClean] — sendable to a compute isolate.
class StampCropRequest {
  const StampCropRequest({
    required this.bytes,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final Uint8List bytes;

  /// Normalized crop rect (0..1) in image coordinates.
  final double left, top, right, bottom;
}

/// Captures, processes and stores the user's stamp — plus the last drawn
/// signature — so both can be placed with a single tap.
class StampService {
  static const _stampPathKey = 'stamp_path';
  static const _signaturePathKey = 'signature_path';

  /// White-background removal threshold: pixels with r,g,b all above this
  /// become fully transparent.
  static const int whiteThreshold = 235;

  final ImagePicker _picker = ImagePicker();

  Future<Uint8List?> captureImage({bool fromCamera = true}) async {
    final file = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (file == null) return null;
    return file.readAsBytes();
  }

  /// Pure processing step: white background → transparent, then crop to the
  /// content bounding box so the stamp places tightly. Returns PNG bytes.
  static Uint8List removeWhiteBackground(Uint8List bytes) {
    final source = img.decodeImage(bytes);
    if (source == null) {
      throw const FormatException('Unsupported image');
    }
    final rgba = source.convert(numChannels: 4);

    var minX = rgba.width, minY = rgba.height, maxX = -1, maxY = -1;
    for (final pixel in rgba) {
      if (pixel.r > whiteThreshold &&
          pixel.g > whiteThreshold &&
          pixel.b > whiteThreshold) {
        pixel.a = 0;
      } else if (pixel.a > 0) {
        if (pixel.x < minX) minX = pixel.x;
        if (pixel.x > maxX) maxX = pixel.x;
        if (pixel.y < minY) minY = pixel.y;
        if (pixel.y > maxY) maxY = pixel.y;
      }
    }

    var result = rgba;
    if (maxX >= minX && maxY >= minY) {
      // Small margin around the content so strokes aren't clipped.
      const pad = 4;
      final x = (minX - pad).clamp(0, rgba.width - 1);
      final y = (minY - pad).clamp(0, rgba.height - 1);
      final w = (maxX + pad).clamp(0, rgba.width - 1) - x + 1;
      final h = (maxY + pad).clamp(0, rgba.height - 1) - y + 1;
      result = img.copyCrop(rgba, x: x, y: y, width: w, height: h);
    }
    return Uint8List.fromList(img.encodePng(result));
  }

  /// Crops [bytes] to the normalized rect (0..1 in image coordinates), then
  /// removes the white background. Used when the user marks the stamp region
  /// inside a photographed / uploaded document. Returns PNG bytes.
  static Uint8List cropAndClean(StampCropRequest request) {
    final source = img.decodeImage(request.bytes);
    if (source == null) {
      throw const FormatException('Unsupported image');
    }
    final x = (request.left * source.width).round().clamp(0, source.width - 1);
    final y = (request.top * source.height).round().clamp(0, source.height - 1);
    final w =
        ((request.right - request.left) * source.width).round().clamp(1, source.width - x);
    final h = ((request.bottom - request.top) * source.height)
        .round()
        .clamp(1, source.height - y);
    final cropped = img.copyCrop(source, x: x, y: y, width: w, height: h);
    return removeWhiteBackground(
        Uint8List.fromList(img.encodePng(cropped)));
  }

  /// Draws the signature centered on top of the stamp (ink over stamp, like
  /// signing across a physical stamp) and returns one combined PNG.
  static Future<Uint8List> compositeSignatureOverStamp(
    Uint8List signaturePng,
    Uint8List stampPng,
  ) async {
    final stamp = await _decodeUiImage(stampPng);
    final signature = await _decodeUiImage(signaturePng);

    final w = stamp.width.toDouble();
    final h = stamp.height.toDouble();
    // Fit the signature inside the stamp bounds, slightly inset.
    final fit = 0.92 *
        (w / signature.width < h / signature.height
            ? w / signature.width
            : h / signature.height);
    final sw = signature.width * fit;
    final sh = signature.height * fit;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.high;
    canvas.drawImage(stamp, ui.Offset.zero, paint);
    canvas.drawImageRect(
      signature,
      ui.Rect.fromLTWH(
          0, 0, signature.width.toDouble(), signature.height.toDouble()),
      ui.Rect.fromCenter(
          center: ui.Offset(w / 2, h / 2), width: sw, height: sh),
      paint,
    );

    final picture = recorder.endRecording();
    final combined = await picture.toImage(stamp.width, stamp.height);
    stamp.dispose();
    signature.dispose();
    picture.dispose();
    final data = await combined.toByteData(format: ui.ImageByteFormat.png);
    combined.dispose();
    return data!.buffer.asUint8List();
  }

  static Future<ui.Image> _decodeUiImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  Future<String> saveStamp(Uint8List pngBytes) =>
      _savePng(pngBytes, 'stamp.png', _stampPathKey);

  Future<String> saveSignature(Uint8List pngBytes) =>
      _savePng(pngBytes, 'saved_signature.png', _signaturePathKey);

  Future<Uint8List?> getStampBytes() => _readPng(_stampPathKey);

  Future<Uint8List?> getSignatureBytes() => _readPng(_signaturePathKey);

  Future<bool> hasStamp() async => await getStampBytes() != null;

  Future<String> _savePng(Uint8List bytes, String name, String prefKey) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKey, file.path);
    return file.path;
  }

  Future<Uint8List?> _readPng(String prefKey) async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(prefKey);
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }
}
