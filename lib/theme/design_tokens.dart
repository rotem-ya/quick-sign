import 'package:flutter/material.dart';

/// QuickSign's design system — one source of truth for color, spacing,
/// radius and elevation so every screen reads as the same product instead of
/// a pile of ad-hoc Material defaults. Cool-neutral palette (not warm/beige)
/// so the blue brand color stays the only saturated accent on screen; every
/// card is separated from its background with a soft shadow rather than a
/// hard 1px border, which is what makes flat outlined boxes look unfinished.
abstract final class DesignTokens {
  // ── Brand ──────────────────────────────────────────────────────────────
  static const Color primary = Color(0xFF3E5EE0);
  static const Color primaryDeep = Color(0xFF2541AE);
  static const Color primarySoft = Color(0xFFEEF1FD);
  static const Color primarySoftStrong = Color(0xFFDFE4FB);

  static const Gradient primaryGradient = LinearGradient(
    begin: Alignment(-0.5, -1),
    end: Alignment(0.5, 1),
    colors: [primary, primaryDeep],
  );

  // ── Semantic ───────────────────────────────────────────────────────────
  static const Color success = Color(0xFF17A673);
  static const Color successSoft = Color(0xFFE4F6EE);
  static const Color danger = Color(0xFFE5484D);
  static const Color dangerSoft = Color(0xFFFCE9E9);
  static const Color warning = Color(0xFFC77B12);
  static const Color warningSoft = Color(0xFFFBF0DD);

  // ── Text ───────────────────────────────────────────────────────────────
  static const Color ink = Color(0xFF12162C);
  static const Color inkSignature = Color(0xFF1B2A4A);
  static const Color textMuted = Color(0xFF565C72);
  static const Color textMuted2 = Color(0xFF6A7086);
  static const Color textFaint = Color(0xFF9599AC);
  static const Color iconStroke = Color(0xFF454B60);
  static const Color iconStroke2 = Color(0xFF383E52);

  // ── Surfaces (cool neutrals — no beige) ───────────────────────────────
  static const Color background = Color(0xFFF4F5FA);
  static const Color surfaceHeader = Color(0xFFFFFFFF);
  static const Color surfacePaper = Color(0xFFFFFFFF);
  static const Color surfaceCard = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF0F1F8);
  static const Color canvasBg = Color(0xFFE7E9F1);
  static const Color placeholderBar = Color(0xFFE7E9F1);

  static const Color hairline1 = Color(0xFFE7E8F1);
  static const Color hairline2 = Color(0xFFECEDF5);
  static const Color hairline3 = Color(0xFFEDEEF6);
  static const Color hairline4 = Color(0xFFD8DAE6);

  // ── Spacing scale ──────────────────────────────────────────────────────
  static const double space4 = 4;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;
  static const double space32 = 32;
  static const double space40 = 40;

  // ── Radius scale ───────────────────────────────────────────────────────
  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 18;
  static const double radiusXl = 24;
  static const double radiusPill = 999;

  // ── Elevation (soft shadows instead of hard borders) ──────────────────
  static List<BoxShadow> get shadowSm => [
    BoxShadow(
      color: ink.withValues(alpha: 0.06),
      blurRadius: 10,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get shadowMd => [
    BoxShadow(
      color: ink.withValues(alpha: 0.08),
      blurRadius: 20,
      offset: const Offset(0, 6),
      spreadRadius: -4,
    ),
  ];

  static List<BoxShadow> get shadowLg => [
    BoxShadow(
      color: ink.withValues(alpha: 0.14),
      blurRadius: 32,
      offset: const Offset(0, 14),
      spreadRadius: -8,
    ),
  ];
}
