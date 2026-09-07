import 'package:flutter/material.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_spacing.dart';

/// Material 3–aligned breakpoints for phone / tablet layouts.
abstract final class AppBreakpoints {
  static const double compact = 600; // phone → tablet
  static const double medium = 840; // tablet → expanded
  static const double expanded = 1200;
}

class ResponsiveLayout {
  ResponsiveLayout._();

  static bool isTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= AppBreakpoints.compact;

  static bool isExpanded(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= AppBreakpoints.medium;

  /// 2 columns on phones, 3 on tablets, 4 on expanded widths.
  static int featureColumns(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= AppBreakpoints.medium) return 4;
    if (w >= AppBreakpoints.compact) return 3;
    return 2;
  }

  static EdgeInsets screenPadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = w >= AppBreakpoints.compact ? AppSpacing.x5 : AppSpacing.x4;
    return EdgeInsets.fromLTRB(h, AppSpacing.x4, h, AppSpacing.x4);
  }

  static double contentMaxWidth(BuildContext context) {
    if (isExpanded(context)) return 960;
    if (isTablet(context)) return 720;
    return double.infinity;
  }
}

/// Centers content and caps width on large screens.
class ResponsiveContent extends StatelessWidget {
  const ResponsiveContent({
    super.key,
    required this.child,
    this.padding,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: ResponsiveLayout.contentMaxWidth(context),
        ),
        child: Padding(
          padding: padding ?? ResponsiveLayout.screenPadding(context),
          child: child,
        ),
      ),
    );
  }
}
