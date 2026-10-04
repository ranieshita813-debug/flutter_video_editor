import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get lightTheme {
    const seed = Color(0xFF7C3AED);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0B1020),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF111827),
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF111827),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: Color(0xFFE5E7EB),
        ),
      ),
    );
  }
}
