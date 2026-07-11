/// Shared between [StampDesignerScreen] (which renders these) and
/// [SavedMark] (which persists them so a designer-made stamp can be
/// reopened and edited later instead of only replaced).
library;

enum StampShape { rectangle, ellipse }

enum StampBorder { none, single, double_ }

/// The editable recipe behind a designer-made stamp — kept alongside the
/// rendered PNG so the designer can be reopened prefilled.
class StampDesign {
  StampDesign({
    required this.lines,
    required this.colorValue,
    required this.shape,
    required this.border,
  });

  final List<String> lines;

  /// ARGB32, from [Color.toARGB32()].
  final int colorValue;
  final StampShape shape;
  final StampBorder border;

  Map<String, Object?> toJson() => {
        'lines': lines,
        'color': colorValue,
        'shape': shape.name,
        'border': border.name,
      };

  static StampDesign? fromJson(Map<String, dynamic> json) {
    try {
      return StampDesign(
        lines: (json['lines'] as List).cast<String>(),
        colorValue: json['color'] as int,
        shape: StampShape.values.byName(json['shape'] as String),
        border: StampBorder.values.byName(json['border'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}
