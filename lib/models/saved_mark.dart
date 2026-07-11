import 'dart:convert';
import 'dart:typed_data';

import 'stamp_design.dart';

enum MarkType { signature, stamp }

/// One named, saved signature or stamp — the app supports any number of
/// each, not just one of each.
class SavedMark {
  SavedMark({
    required this.id,
    required this.type,
    required this.name,
    required this.imageBytes,
    this.design,
  });

  final String id;
  final MarkType type;
  String name;
  Uint8List imageBytes;

  /// Present only for stamps made with the built-in designer — lets the
  /// designer be reopened prefilled instead of only replacing the image.
  StampDesign? design;

  Map<String, Object?> toJson() => {
        'id': id,
        'type': type.name,
        'name': name,
        'image': base64Encode(imageBytes),
        'design': design?.toJson(),
      };

  /// Returns null on malformed data instead of throwing, so one corrupt
  /// entry can't take the whole library down.
  static SavedMark? fromJson(Map<String, dynamic> json) {
    try {
      final designJson = json['design'];
      return SavedMark(
        id: json['id'] as String,
        type: MarkType.values.byName(json['type'] as String),
        name: json['name'] as String,
        imageBytes: base64Decode(json['image'] as String),
        design: designJson == null
            ? null
            : StampDesign.fromJson(designJson as Map<String, dynamic>),
      );
    } catch (_) {
      return null;
    }
  }
}
