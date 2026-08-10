import 'package:flutter/material.dart';

abstract class AppColors {
  // === Surfaces (светлая тема) ===
  static const Color surface = Color(0xFFF7F9FC);
  static const Color surfaceBright = Color(0xFFF7F9FC);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceContainerLow = Color(0xFFF2F4F7);
  static const Color surfaceContainer = Color(0xFFECEEF1);
  static const Color surfaceContainerHigh = Color(0xFFE6E8EB);
  static const Color surfaceContainerHighest = Color(0xFFE0E3E6);
  static const Color surfaceDim = Color(0xFFD8DADD);

  // === Текст и контуры ===
  static const Color onSurface = Color(0xFF191C1E);
  static const Color onSurfaceVariant = Color(0xFF444655);
  static const Color outline = Color(0xFF747687);
  static const Color outlineVariant = Color(0xFFC4C5D8);

  // === Primary (синий) ===
  static const Color primary = Color(0xFF0038D1);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFF2F54EB);
  static const Color onPrimaryContainer = Color(0xFFDEE1FF);

  // === Secondary (зелёный / success) ===
  static const Color secondary = Color(0xFF006D41);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color secondaryContainer = Color(0xFF95F7BB);
  static const Color onSecondaryContainer = Color(0xFF007346);

  // === Error / SOS (красный) ===
  static const Color error = Color(0xFFBA1A1A);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFFFFDAD6);
  static const Color onErrorContainer = Color(0xFF93000A);
  static const Color sosRed = Color(0xFFE53935);
  static const Color sosTrack = Color(0xFFFFD1D1);
  static const Color sosDark = Color(0xFF8C3333);

  // === Прочее ===
  static const Color tertiary = Color(0xFF9F0019);
  static const Color inverseSurface = Color(0xFF2D3133);
  static const Color inverseOnSurface = Color(0xFFEFF1F4);

  // === Legacy-алиасы (совместимость) ===
  static const Color neutral = surface;
  static const Color textPrimary = onSurface;
  static const Color textSecondary = onSurfaceVariant;
  static const Color activeGreen = secondary;
}
