import 'package:flutter/material.dart';

/// Border radius tokens.
abstract final class AppRadius {
  static const double none = 0;
  static const double xs   = 4.0;
  static const double sm   = 8.0;
  static const double md   = 12.0;
  static const double lg   = 16.0;
  static const double xl   = 20.0;
  static const double xxl  = 24.0;
  static const double xxxl = 28.0;
  static const double full = 9999.0;

  // Semantic
  static const BorderRadius brNone   = BorderRadius.all(Radius.circular(none));
  static const BorderRadius brXs     = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius brSm     = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius brMd     = BorderRadius.all(Radius.circular(md));
  static const BorderRadius brLg     = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius brXl     = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius brXxl    = BorderRadius.all(Radius.circular(xxl));
  static const BorderRadius brXxxl   = BorderRadius.all(Radius.circular(xxxl));
  static const BorderRadius brFull   = BorderRadius.all(Radius.circular(full));
  static const BorderRadius brTop    = BorderRadius.vertical(top: Radius.circular(xxxl));

  // Component defaults
  static const BorderRadius button      = brMd;
  static const BorderRadius chip        = brSm;
  static const BorderRadius dialog      = brXxxl;
  static const BorderRadius bottomSheet = brTop;
  static const BorderRadius textField   = brMd;
  static const BorderRadius badge       = brFull;
  static const BorderRadius fab         = brLg;
  static const BorderRadius navBar      = brNone;

  // Card radius driven by user preference
  static BorderRadius cardRadius(AppCardStyle style) => switch (style) {
    AppCardStyle.rounded => brLg,
    AppCardStyle.square  => brXs,
    AppCardStyle.soft    => brXxl,
  };
}

enum AppCardStyle { rounded, square, soft }
