import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'placement.dart';

/// The active document being signed: the normalized PDF on disk, its page
/// geometry, and every placement the user has added so far.
class DocumentSession {
  DocumentSession({
    required this.pdfPath,
    required this.pageCount,
    required this.pageSizes,
  });

  /// Path of the working PDF (original PDF, or a single-page PDF wrapping an
  /// imported image).
  final String pdfPath;

  final int pageCount;

  /// Per-page size in PDF points, index-aligned with pages.
  final List<Size> pageSizes;

  /// Median height of a text line in the document, in PDF points. Filled
  /// asynchronously after open; null when the document has no extractable
  /// text (e.g. a photographed page). Used to size signatures / stamps /
  /// notes proportionally to the document's own writing.
  double? bodyTextHeightPts;

  /// Placements notifier so the UI rebuilds on add / move / resize / delete.
  final ValueNotifier<List<Placement>> placements =
      ValueNotifier<List<Placement>>(<Placement>[]);

  void addPlacement(Placement p) {
    placements.value = List.of(placements.value)..add(p);
  }

  void removePlacement(Placement p) {
    placements.value = List.of(placements.value)..remove(p);
  }

  /// Call after mutating a placement in place (drag / pinch) to notify listeners.
  void touch() {
    placements.value = List.of(placements.value);
  }

  void dispose() {
    placements.dispose();
  }
}
