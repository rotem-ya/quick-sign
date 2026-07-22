import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/strings.dart';
import 'screens/work_screen.dart';
import 'theme/design_tokens.dart';

/// Lets WorkScreen know when it stops being the visible, topmost route
/// (Settings/History pushed on top, a sheet/dialog opened, …) — used to
/// scope the web mouse-wheel-pan override so it never steals scroll from
/// another screen's own scrollable.
final routeObserver = RouteObserver<PageRoute<void>>();

class QuickSignApp extends StatelessWidget {
  const QuickSignApp({super.key});

  static const _seed = DesignTokens.primary;

  ThemeData _theme(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    var scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    // The seeded scheme's default surfaces lean warm/purple-tinted; swap in
    // the design system's cool neutrals for light mode so the blue brand
    // color reads as the only saturated accent on screen. Dark mode keeps
    // the seeded tones — there's no hand-picked dark palette to match yet.
    if (isLight) {
      scheme = scheme.copyWith(
        primary: DesignTokens.primary,
        onPrimary: Colors.white,
        primaryContainer: DesignTokens.primarySoft,
        onPrimaryContainer: DesignTokens.primaryDeep,
        secondaryContainer: DesignTokens.primarySoft,
        onSecondaryContainer: DesignTokens.primaryDeep,
        error: DesignTokens.danger,
        errorContainer: DesignTokens.dangerSoft,
        onErrorContainer: DesignTokens.danger,
        surface: DesignTokens.surfaceCard,
        onSurface: DesignTokens.ink,
        onSurfaceVariant: DesignTokens.textMuted,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: DesignTokens.surfaceMuted,
        surfaceContainer: DesignTokens.surfaceMuted,
        surfaceContainerHigh: DesignTokens.hairline2,
        surfaceContainerHighest: DesignTokens.hairline3,
        outline: DesignTokens.hairline4,
        outlineVariant: DesignTokens.hairline2,
      );
    }
    final radiusMd = BorderRadius.circular(DesignTokens.radiusMd);
    final radiusLg = BorderRadius.circular(DesignTokens.radiusLg);
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: isLight
          ? DesignTokens.background
          : null,
      // Heebo covers Hebrew + Latin — one typographic voice everywhere,
      // matching the font embedded in exported documents.
      fontFamily: 'Heebo',
      visualDensity: VisualDensity.comfortable,
      splashFactory: InkSparkle.splashFactory,
      // Accessibility: generous touch targets everywhere.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      textTheme: const TextTheme(
        headlineSmall: TextStyle(fontWeight: FontWeight.w700, height: 1.2),
        titleLarge: TextStyle(fontWeight: FontWeight.w700, height: 1.25),
        titleMedium: TextStyle(fontWeight: FontWeight.w600, height: 1.3),
        bodyLarge: TextStyle(height: 1.4),
        bodyMedium: TextStyle(height: 1.4),
        labelLarge: TextStyle(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: isLight ? DesignTokens.surfaceHeader : scheme.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: DesignTokens.ink,
        titleTextStyle: const TextStyle(
          fontFamily: 'Heebo',
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: DesignTokens.ink,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: isLight ? 1.5 : 0,
        shadowColor: DesignTokens.ink.withValues(alpha: 0.14),
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: radiusLg),
        color: isLight ? DesignTokens.surfaceCard : scheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
      ),
      // Using ElevatedButton (styled flat, no shadow) instead of FilledButton
      // as the app's primary CTA button: on web, a themed button's label
      // renders invisible whenever the theme sets a custom `textStyle` —
      // reproduced with FilledButton AND ElevatedButton alike, gone as soon
      // as `textStyle` is dropped from the theme (button-level `style:`
      // overrides, like stamp_setup_screen's minimumSize, are unaffected).
      // Root cause not fully isolated (looks like a Flutter/CanvasKit merge
      // bug between the theme's WidgetStateProperty<TextStyle> and the
      // resolved foreground color) — the label font now falls back to
      // labelLarge (still Heebo, still bold via textTheme below) instead of
      // a button-specific size.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.12),
          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: radiusMd),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: BorderSide(color: scheme.outlineVariant, width: 1.4),
          shape: RoundedRectangleBorder(borderRadius: radiusMd),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: radiusMd),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: DesignTokens.iconStroke,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? DesignTokens.surfaceMuted : scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        labelStyle: TextStyle(color: DesignTokens.textMuted),
        hintStyle: TextStyle(color: DesignTokens.textFaint),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isLight ? DesignTokens.surfaceMuted : scheme.surfaceContainerLow,
        selectedColor: DesignTokens.primarySoftStrong,
        labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      dividerTheme: DividerThemeData(
        color: isLight ? DesignTokens.hairline2 : scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: DesignTokens.iconStroke,
        shape: RoundedRectangleBorder(borderRadius: radiusMd),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: DesignTokens.ink,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isLight ? Colors.white : null,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isLight ? Colors.white : null,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(DesignTokens.radiusXl),
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: radiusMd),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => S.of(context)['appTitle'],
      debugShowCheckedModeBanner: false,
      // Hebrew first — RTL layout comes from the locale automatically.
      supportedLocales: const [Locale('he'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Locked to the polished light theme for now: the design system uses
      // hand-picked light-mode colors throughout (section titles, toolbars,
      // etc. hardcode dark ink), so following the system into dark mode left
      // dark-on-dark text (e.g. invisible section headers). A proper dark
      // palette is a follow-up; until then a consistent light UI beats a
      // half-styled dark one.
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.light),
      themeMode: ThemeMode.light,
      navigatorObservers: [routeObserver],
      home: const WorkScreen(),
    );
  }
}
