import 'package:flutter/material.dart';

class AppTheme {
  static const Color _primaryColor = Color(0xFF0F172A);
  static const Color _secondaryColor = Color(0xFF00B5D8);
  static const Color _lightGray = Color(0xFFE5E7EB);
  static const Color _offWhite = Color(0xFFF7F7F7);

  const AppTheme._();

  static ThemeData buildTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _primaryColor,
      primary: _primaryColor,
      secondary: _secondaryColor,
      surface: Colors.white,
      background: _offWhite,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _offWhite,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.background,
        foregroundColor: colorScheme.onBackground,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _lightGray),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _secondaryColor, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _lightGray),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _primaryColor,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _secondaryColor,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}
