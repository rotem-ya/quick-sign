import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
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
///
/// Stored as base64 in shared preferences: works identically on mobile and
/// web, and on Android it rides the OS auto-backup, so the stamp and
/// signature survive app reinstalls through the user's own Google backup —
/// no accounts, no servers.
class StampService {
  static const _stampKey = 'stamp_png_b64';
  static const _signatureKey = 'signature_png_b64';

  // Pre-web versions stored file paths; migrated lazily on first read.
  static const _legacyStampPathKey = 'stamp_path';
  static const _legacySignaturePathKey = 'signature_path';

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

  /// Pure processing step: page background → transparent, then crop to the
  /// content bounding box so the stamp places tightly. Returns PNG bytes.
  ///
  /// Adaptive: the background color is estimated from the image border, so a
  /// grayish / yellowish / shadowed photographed page disappears too — only
  /// the stamp ink survives, with a soft edge where ink meets paper.
  static Uint8List removeWhiteBackground(Uint8List bytes) {
    final source = img.decodeImage(bytes);
    if (source == null) {
      throw const FormatException('Unsupported image');
    }
    final rgba = source.convert(numChannels: 4);

    final bg = _estimateBackground(rgba);
    // Distance from background below [low] → fully transparent; above
    // [high] → fully opaque ink; between → soft edge.
    const low = 28.0;
    const high = 72.0;

    var minX = rgba.width, minY = rgba.height, maxX = -1, maxY = -1;
    for (final pixel in rgba) {
      final d = _chebyshev(pixel, bg);
      if (d <= low) {
        pixel.a = 0;
        continue;
      }
      if (d < high) {
        pixel.a = (pixel.a * (d - low) / (high - low)).round();
      }
      if (pixel.a > 40) {
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

  /// Median color of the image's border ring — a robust estimate of the
  /// paper/page background even when it is gray, tinted or unevenly lit.
  static img.ColorRgb8 _estimateBackground(img.Image image) {
    final rs = <int>[], gs = <int>[], bs = <int>[];
    void sample(int x, int y) {
      final p = image.getPixel(x, y);
      rs.add(p.r.toInt());
      gs.add(p.g.toInt());
      bs.add(p.b.toInt());
    }

    final stepX = (image.width / 48).ceil().clamp(1, image.width);
    final stepY = (image.height / 48).ceil().clamp(1, image.height);
    for (var x = 0; x < image.width; x += stepX) {
      sample(x, 0);
      sample(x, image.height - 1);
    }
    for (var y = 0; y < image.height; y += stepY) {
      sample(0, y);
      sample(image.width - 1, y);
    }
    int median(List<int> v) {
      v.sort();
      return v[v.length ~/ 2];
    }

    return img.ColorRgb8(median(rs), median(gs), median(bs));
  }

  static double _chebyshev(img.Pixel p, img.ColorRgb8 bg) {
    final dr = (p.r - bg.r).abs();
    final dg = (p.g - bg.g).abs();
    final db = (p.b - bg.b).abs();
    return [dr, dg, db].reduce((a, b) => a > b ? a : b).toDouble();
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

  Future<void> saveStamp(Uint8List pngBytes) => _savePng(pngBytes, _stampKey);

  Future<void> saveSignature(Uint8List pngBytes) =>
      _savePng(pngBytes, _signatureKey);

  Future<Uint8List?> getStampBytes() =>
      _readPng(_stampKey, legacyPathKey: _legacyStampPathKey);

  Future<Uint8List?> getSignatureBytes() =>
      _readPng(_signatureKey, legacyPathKey: _legacySignaturePathKey);

  Future<bool> hasStamp() async => await getStampBytes() != null;

  Future<void> removeStamp() => _remove(_stampKey, _legacyStampPathKey);

  Future<void> removeSignature() =>
      _remove(_signatureKey, _legacySignaturePathKey);

  Future<void> _remove(String prefKey, String legacyKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefKey);
    await prefs.remove(legacyKey);
  }

  Future<void> _savePng(Uint8List bytes, String prefKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKey, base64Encode(bytes));
  }

  Future<Uint8List?> _readPng(String prefKey,
      {required String legacyPathKey}) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(prefKey);
    if (encoded != null) {
      try {
        return base64Decode(encoded);
      } catch (_) {
        return null;
      }
    }
    // One-time migration from the old file-based storage (mobile only).
    if (kIsWeb) return null;
    final legacyPath = prefs.getString(legacyPathKey);
    if (legacyPath == null) return null;
    try {
      final file = File(legacyPath);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      await prefs.setString(prefKey, base64Encode(bytes));
      await prefs.remove(legacyPathKey);
      return bytes;
    } catch (_) {
      return null;
    }
  }
}
