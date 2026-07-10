import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/strings.dart';
import 'screens/work_screen.dart';

class QuickSignApp extends StatelessWidget {
  const QuickSignApp({super.key});

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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A5CB0)),
        // Heebo covers Hebrew + Latin — one typographic voice everywhere,
        // matching the font embedded in exported documents.
        fontFamily: 'Heebo',
        visualDensity: VisualDensity.comfortable,
        // Accessibility: generous touch targets everywhere.
        materialTapTargetSize: MaterialTapTargetSize.padded,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontFamily: 'Heebo',
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1C1E),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: const WorkScreen(),
    );
  }
}
