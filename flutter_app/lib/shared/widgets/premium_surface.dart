import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_elevation.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_spacing.dart';
/// Soft elevated surface — default card language for the premium healthcare UI.
/// Prefer this over bare [Card] when you need subtle shadow without loud borders.
class SoftSurface extends StatelessWidget {
  const SoftSurface({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius,
    this.color,
    this.onTap,
    this.elevation = SoftSurfaceElevation.level1,
    this.border,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final Color? color;
  final VoidCallback? onTap;
  final SoftSurfaceElevation elevation;
  final Border? border;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Prefer explicit radius; otherwise MD3 16dp healthcare default.
    final radius = borderRadius ?? AppRadius.brLg;
    final shadows = switch (elevation) {
      SoftSurfaceElevation.none => AppElevation.none,
      SoftSurfaceElevation.level1 => AppElevation.level1,
      SoftSurfaceElevation.level2 => AppElevation.level2,
      SoftSurfaceElevation.level3 => AppElevation.level3,
    };

    final content = Container(
      margin: margin,
      padding: padding ?? AppSpacing.cardEdge,
      decoration: BoxDecoration(
        color: color ?? cs.surface,
        borderRadius: radius,
        boxShadow: shadows,
        border: border ??
            Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.45),
              width: 1,
            ),
      ),
      child: child,
    );

    if (onTap == null) {
      return Semantics(
        container: true,
        label: semanticLabel,
        child: content,
      );
    }

    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: content,
        ),
      ),
    );
  }
}

enum SoftSurfaceElevation { none, level1, level2, level3 }

/// Lightweight glass panel for hero headers / overlays.
/// Uses backdrop blur when supported; falls back to translucent fill.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.opacity = 0.22,
    this.blurSigma = 14,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final double opacity;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? AppRadius.brLg;
    final fill = Colors.white.withValues(alpha: opacity);

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding ?? const EdgeInsets.all(AppSpacing.x3),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: radius,
            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
          ),
          child: child,
        ),
      ),
    );
  }
}
