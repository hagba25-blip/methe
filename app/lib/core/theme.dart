import 'package:flutter/material.dart';

class AppTheme {
  static const _brand = Color(0xFF0B5FFF);
  static const _accent = Color(0xFF16A34A);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: _brand, secondary: _accent, brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      ),
    );
  }

  static final light = _base(Brightness.light);
  static final dark = _base(Brightness.dark);
}
