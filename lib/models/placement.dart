import 'dart:typed_data';

enum PlacementType { signature, stamp, note }

/// A single item placed on the document: a drawn signature, a saved stamp
/// image, or a short text note.
///
/// Coordinates are normalized (0..1) relative to the target page, so the
/// placement stays correct under zoom, different screen sizes, and when
/// flattening onto the real-size PDF page at export.
class Placement {
  Placement({
    required this.type,
    required this.pageIndex,
    required this.nx,
    required this.ny,
    this.widthFraction = 0.25,
    this.aspectRatio = 2.0,
    this.imageBytes,
    this.text,
  });

  final PlacementType type;

  /// Zero-based page index.
  final int pageIndex;

  /// Normalized center X (0..1) relative to the page width.
  double nx;

  /// Normalized center Y (0..1) relative to the page height.
  double ny;

  /// Width relative to the page width. Height derives from [aspectRatio].
  double widthFraction;

  /// Width / height of [imageBytes]. Used to size the overlay and the
  /// exported image without re-decoding.
  double aspectRatio;

  /// Transparent PNG — for [PlacementType.signature] and [PlacementType.stamp].
  final Uint8List? imageBytes;

  /// Note text — for [PlacementType.note].
  final String? text;
}
