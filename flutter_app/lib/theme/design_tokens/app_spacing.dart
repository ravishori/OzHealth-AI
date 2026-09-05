import 'package:flutter/material.dart';

/// 8-point grid system for consistent spacing across the app.
abstract final class AppSpacing {
  // Raw scale
  static const double x1  = 4.0;
  static const double x2  = 8.0;
  static const double x3  = 12.0;
  static const double x4  = 16.0;
  static const double x5  = 20.0;
  static const double x6  = 24.0;
  static const double x8  = 32.0;
  static const double x10 = 40.0;
  static const double x12 = 48.0;
  static const double x16 = 64.0;

  // Semantic aliases
  static const double screenHorizontal = x5;   // 20
  static const double cardPadding      = x4;   // 16
  static const double sectionGap       = x6;   // 24
  static const double itemGap          = x3;   // 12
  static const double inlineGap        = x2;   // 8
  static const double touchTarget      = x12;  // 48
  static const double iconSm           = 18.0;
  static const double iconMd           = 24.0;
  static const double iconLg           = 32.0;
  static const double iconXl           = 40.0;

  // Layout helpers
  static const EdgeInsets screenPadding =
      EdgeInsets.symmetric(horizontal: screenHorizontal, vertical: x4);
  static const EdgeInsets cardEdge =
      EdgeInsets.all(cardPadding);
  static const EdgeInsets cardEdgeHorizontal =
      EdgeInsets.symmetric(horizontal: cardPadding, vertical: x3);

  // Display density multipliers
  static EdgeInsets densityPadding(AppDisplayDensity d) => switch (d) {
    AppDisplayDensity.compact     => const EdgeInsets.all(x3),
    AppDisplayDensity.comfortable => const EdgeInsets.all(x4),
    AppDisplayDensity.spacious    => const EdgeInsets.all(x6),
  };

  static double densityGap(AppDisplayDensity d) => switch (d) {
    AppDisplayDensity.compact     => x2,
    AppDisplayDensity.comfortable => x3,
    AppDisplayDensity.spacious    => x4,
  };
}

enum AppDisplayDensity { compact, comfortable, spacious }
