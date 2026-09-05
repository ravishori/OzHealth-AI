import 'package:flutter/material.dart';

enum AppTextSize { small, medium, large, extraLarge }

abstract final class AppTypography {
  static double scaleFactor(AppTextSize s) => switch (s) {
    AppTextSize.small      => 0.875,
    AppTextSize.medium     => 1.0,
    AppTextSize.large      => 1.125,
    AppTextSize.extraLarge => 1.25,
  };

  /// Build a Material Design 3 TextTheme scaled for [size].
  static TextTheme textTheme(AppTextSize size) {
    final k = scaleFactor(size);

    TextStyle t(double fs, FontWeight fw, double ls, double lh) => TextStyle(
      fontSize:       fs * k,
      fontWeight:     fw,
      letterSpacing:  ls,
      height:         lh / (fs * k),
    );

    return TextTheme(
      // Display
      displayLarge:  t(57, FontWeight.w400,  -0.25, 64),
      displayMedium: t(45, FontWeight.w400,   0.00, 52),
      displaySmall:  t(36, FontWeight.w400,   0.00, 44),
      // Headline
      headlineLarge:  t(32, FontWeight.w600, 0.00, 40),
      headlineMedium: t(28, FontWeight.w600, 0.00, 36),
      headlineSmall:  t(24, FontWeight.w600, 0.00, 32),
      // Title
      titleLarge:  t(22, FontWeight.w500,  0.00, 28),
      titleMedium: t(16, FontWeight.w600,  0.15, 24),
      titleSmall:  t(14, FontWeight.w600,  0.10, 20),
      // Body
      bodyLarge:  t(16, FontWeight.w400,  0.50, 24),
      bodyMedium: t(14, FontWeight.w400,  0.25, 20),
      bodySmall:  t(12, FontWeight.w400,  0.40, 16),
      // Label
      labelLarge:  t(14, FontWeight.w600,  0.10, 20),
      labelMedium: t(12, FontWeight.w600,  0.50, 16),
      labelSmall:  t(11, FontWeight.w600,  0.50, 16),
    );
  }

  // ── Semantic shortcuts ─────────────────────────────────────────────────────

  /// AppBar / screen title
  static TextStyle screenTitle(BuildContext ctx) =>
    Theme.of(ctx).textTheme.titleLarge!;

  /// Section heading (e.g. "Quick Access")
  static TextStyle sectionTitle(BuildContext ctx) =>
    Theme.of(ctx).textTheme.titleSmall!;

  /// Card primary label
  static TextStyle cardTitle(BuildContext ctx) =>
    Theme.of(ctx).textTheme.titleSmall!;

  /// Card secondary descriptor
  static TextStyle cardSubtitle(BuildContext ctx) =>
    Theme.of(ctx).textTheme.bodySmall!;

  /// Data / stats value
  static TextStyle statValue(BuildContext ctx) =>
    Theme.of(ctx).textTheme.headlineSmall!;

  /// Compact pill / badge text
  static TextStyle badge(BuildContext ctx) =>
    Theme.of(ctx).textTheme.labelSmall!;
}
