import 'package:flutter/material.dart';

class AppColors {
  static const petroleum = Color(0xFF0F172A);
  static const cyan = Color(0xFF00B5D8);
  static const grayLight = Color(0xFFE5E7EB);
  static const whiteSoft = Color(0xFFF7F7F7);
}

ThemeData buildTheme() {
  final base = ThemeData(useMaterial3: true, brightness: Brightness.light);
  return base.copyWith(
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.cyan,
      primary: AppColors.petroleum,
      secondary: AppColors.cyan,
      surface: Colors.white,
      onPrimary: Colors.white,
    ),
    scaffoldBackgroundColor: Colors.white,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.petroleum,
      foregroundColor: Colors.white,
      centerTitle: true,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
    // Si quieres personalizar cards más tarde, usa CardTheme correctamente:
    // cardTheme: const CardTheme(), // CardThemeData en M3 ya es typedef correcto
  );
}
