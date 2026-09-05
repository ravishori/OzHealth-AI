import 'package:flutter/material.dart';

/// MD3-aligned shadow tokens.
abstract final class AppElevation {
  static const List<BoxShadow> none = [];

  static const List<BoxShadow> level1 = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 2,  offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0A000000), blurRadius: 3,  offset: Offset(0, 1)),
  ];

  static const List<BoxShadow> level2 = [
    BoxShadow(color: Color(0x14000000), blurRadius: 6,  offset: Offset(0, 2)),
    BoxShadow(color: Color(0x0F000000), blurRadius: 8,  offset: Offset(0, 1)),
  ];

  static const List<BoxShadow> level3 = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 10, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, 2)),
  ];

  static const List<BoxShadow> level4 = [
    BoxShadow(color: Color(0x1F000000), blurRadius: 14, offset: Offset(0, 6)),
    BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 4)),
  ];

  static const List<BoxShadow> level5 = [
    BoxShadow(color: Color(0x24000000), blurRadius: 18, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x1A000000), blurRadius: 20, offset: Offset(0, 6)),
  ];

  // Accessibility-friendly flat shadow (border-only visual elevation)
  static const BoxShadow flatBorder = BoxShadow(
    color: Color(0x1F000000),
    blurRadius: 0,
    spreadRadius: 1,
  );
}
