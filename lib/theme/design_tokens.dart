import 'package:flutter/material.dart';

/// Exact colors from the work-screen hi-fi design handoff — copied directly
/// rather than derived from [ColorScheme], since the handoff calls for
/// pixel-accurate reproduction of a specific palette, not a Material tonal
/// approximation of it. Scoped to the work screen's own widgets (header,
/// canvas, toolbar, zoom control, placement selection); other screens keep
/// the regular derived [ColorScheme].
abstract final class DesignTokens {
  static const Color primary = Color(0xFF3E63DD);
  static const Color primaryDeep = Color(0xFF2947B8);
  static const Color primarySoft = Color(0xFFEEF1FC);

  static const Color ink = Color(0xFF15223B);
  static const Color inkSignature = Color(0xFF1B2A4A);
  static const Color textMuted = Color(0xFF5E6472);
  static const Color textMuted2 = Color(0xFF6B7180);
  static const Color textFaint = Color(0xFF9AA0AC);
  static const Color iconStroke = Color(0xFF48505F);
  static const Color iconStroke2 = Color(0xFF3A4356);

  static const Color surfaceHeader = Color(0xFFFBFAF7);
  static const Color surfacePaper = Color(0xFFFFFFFF);
  static const Color canvasBg = Color(0xFFEFEEE9);
  static const Color placeholderBar = Color(0xFFEFEEE9);

  static const Color hairline1 = Color(0xFFEAE9E3);
  static const Color hairline2 = Color(0xFFEEEDE9);
  static const Color hairline3 = Color(0xFFEDECE7);
  static const Color hairline4 = Color(0xFFD8D7D1);

  static const Gradient primaryGradient = LinearGradient(
    begin: Alignment(-0.5, -1),
    end: Alignment(0.5, 1),
    colors: [primary, primaryDeep],
  );
}
