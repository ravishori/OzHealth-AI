import 'package:flutter/material.dart';

/// Legacy design-token class — MIGRATION COMPLETE (Wave 6/6).
///
/// All color, radius, spacing, shadow, and typography constants below are
/// [Deprecated]. Feature code must use:
///   • [Theme.of(context).colorScheme] — semantic Material 3 colors
///   • [HealthcareColors.of(context)]  — clinical specialty colors
///   • [AppRadius]                      — border radii
///   • [Theme.of(context).textTheme]   — typography
///
/// [lightTheme] and [darkTheme] have been removed — use [ThemeManager] instead.
/// Animation ([durationFast], [durationMed], [durationSlow], [curveDefault])
/// and layout ([navHeight]) constants are kept without deprecation as they
/// have no direct replacement in the new system yet.
///
/// This class will be deleted once all deprecated references are gone.
// ignore_for_file: deprecated_member_use_from_same_package
class AppTheme {
  // ── Brand colors — Medical Sapphire identity ──────────────────────────────────

  @Deprecated('Use Theme.of(context).colorScheme.primary')
  static const Color primary          = Color(0xFF1A4B8F);

  @Deprecated('Use Color.lerp(cs.primary, Colors.black, 0.35)!')
  static const Color primaryDark      = Color(0xFF0F3068);

  @Deprecated('Use Theme.of(context).colorScheme.primary')
  static const Color primaryMid       = Color(0xFF2B5FAD);

  @Deprecated('Use Theme.of(context).colorScheme.primaryContainer')
  static const Color primaryLight     = Color(0xFFD6E4FF);

  @Deprecated('Use Theme.of(context).colorScheme.primaryContainer')
  static const Color primaryContainer = Color(0xFFEEF3FB);

  @Deprecated('Use Theme.of(context).colorScheme.secondary')
  static const Color accent           = Color(0xFF00B4A2);

  @Deprecated('Use Theme.of(context).colorScheme.secondary')
  static const Color accentDark       = Color(0xFF008F80);

  @Deprecated('Use Theme.of(context).colorScheme.secondaryContainer')
  static const Color accentLight      = Color(0xFFB2EDE8);

  @Deprecated('Use Theme.of(context).colorScheme.secondaryContainer')
  static const Color accentContainer  = Color(0xFFE0FAF7);

  @Deprecated('Use Theme.of(context).colorScheme.tertiary')
  static const Color secondary        = Color(0xFFF59E0B);

  @Deprecated('Use Theme.of(context).colorScheme.tertiary')
  static const Color amber            = Color(0xFFF59E0B);

  @Deprecated('Use HealthcareColors.of(context).vitaWarning')
  static const Color secondaryDark    = Color(0xFFB45309);

  @Deprecated('Use Theme.of(context).colorScheme.tertiaryContainer')
  static const Color secondaryContainer = Color(0xFFFEF3C7);

  @Deprecated('Use Theme.of(context).colorScheme.error')
  static const Color error            = Color(0xFFDC2626);

  @Deprecated('Use Theme.of(context).colorScheme.errorContainer')
  static const Color errorContainer   = Color(0xFFFEF2F2);

  @Deprecated('Use HealthcareColors.of(context).vitaGood')
  static const Color success          = Color(0xFF059669);

  @Deprecated('Use HealthcareColors.of(context).vitaGood.withValues(alpha:0.08)')
  static const Color successContainer = Color(0xFFECFDF5);

  @Deprecated('Use HealthcareColors.of(context).vitaWarning')
  static const Color warning          = Color(0xFFD97706);

  @Deprecated('Use HealthcareColors.of(context).vitaWarning.withValues(alpha:0.08)')
  static const Color warningContainer = Color(0xFFFFFBEB);

  @Deprecated('Use HealthcareColors.of(context).emergency')
  static const Color emergencyRed     = Color(0xFF991B1B);

  @Deprecated('Use HealthcareColors.of(context).emergencyContainer')
  static const Color emergencyContainer = Color(0xFFFFE4E6);

  // ── Surface & background — Light ─────────────────────────────────────────────

  @Deprecated('Use Theme.of(context).colorScheme.surface')
  static const Color background    = Color(0xFFF7FAFC);

  @Deprecated('Use Theme.of(context).colorScheme.surface')
  static const Color surface       = Colors.white;

  @Deprecated('Use Theme.of(context).colorScheme.surfaceContainerHighest')
  static const Color surfaceVariant = Color(0xFFEEF3FB);

  @Deprecated('Use Theme.of(context).colorScheme.surface')
  static const Color cardColor     = Colors.white;

  @Deprecated('Use Theme.of(context).colorScheme.outline')
  static const Color outline       = Color(0xFFD1D9E6);

  @Deprecated('Use Theme.of(context).colorScheme.outlineVariant')
  static const Color outlineVariant = Color(0xFFC7CDD4);

  // ── Surface — Dark (Midnight Medical) ────────────────────────────────────────

  @Deprecated('Use Theme.of(context).colorScheme.surface in dark ThemeMode')
  static const Color backgroundDark  = Color(0xFF080E1E);

  @Deprecated('Use Theme.of(context).colorScheme.surface in dark ThemeMode')
  static const Color surfaceDark     = Color(0xFF0E1829);

  @Deprecated('Use Theme.of(context).colorScheme.surfaceContainer in dark ThemeMode')
  static const Color surfaceDark2    = Color(0xFF162033);

  @Deprecated('Use Theme.of(context).colorScheme.surfaceContainerHigh in dark ThemeMode')
  static const Color surfaceDark3    = Color(0xFF1C2A40);

  @Deprecated('Use Theme.of(context).colorScheme.outline in dark ThemeMode')
  static const Color outlineDark     = Color(0xFF1E2D45);

  @Deprecated('Use Theme.of(context).colorScheme.primary in dark ThemeMode')
  static const Color primaryOnDark   = Color(0xFF5B8FD4);

  @Deprecated('Use Theme.of(context).colorScheme.secondary in dark ThemeMode')
  static const Color accentOnDark    = Color(0xFF0DD4BF);

  // ── Text — Light ─────────────────────────────────────────────────────────────

  @Deprecated('Use Theme.of(context).colorScheme.onSurface')
  static const Color textPrimary   = Color(0xFF0D1B3E);

  @Deprecated('Use Theme.of(context).colorScheme.onSurfaceVariant')
  static const Color textSecondary = Color(0xFF4A5978);

  @Deprecated('Use Theme.of(context).colorScheme.onSurfaceVariant')
  static const Color textTertiary  = Color(0xFF8898AA);

  // ── Text — Dark ──────────────────────────────────────────────────────────────

  @Deprecated('Use Theme.of(context).colorScheme.onSurface in dark ThemeMode')
  static const Color textPrimaryDark   = Color(0xFFEFF6FF);

  @Deprecated('Use Theme.of(context).colorScheme.onSurfaceVariant in dark ThemeMode')
  static const Color textSecondaryDark = Color(0xFF94A3B8);

  @Deprecated('Use Theme.of(context).colorScheme.onSurfaceVariant in dark ThemeMode')
  static const Color textTertiaryDark  = Color(0xFF475569);

  // ── Medical record type colors ────────────────────────────────────────────────

  @Deprecated('Use HealthcareColors.of(context).prescription')
  static const Color recordPrescription  = Color(0xFF2563EB);

  @Deprecated('Use HealthcareColors.of(context).labReport')
  static const Color recordLabReport     = Color(0xFF7C3AED);

  @Deprecated('Use HealthcareColors.of(context).radiology')
  static const Color recordRadiology     = Color(0xFF0891B2);

  @Deprecated('Use HealthcareColors.of(context).discharge')
  static const Color recordDischarge     = Color(0xFF059669);

  @Deprecated('Use Theme.of(context).colorScheme.onSurfaceVariant')
  static const Color recordConsultation  = Color(0xFFB45309);

  @Deprecated('Use Theme.of(context).colorScheme.secondary')
  static const Color recordImmunization  = Color(0xFFBE185D);

  // ── Risk level colors ─────────────────────────────────────────────────────────

  @Deprecated('Use HealthcareColors.of(context).vitaGood')
  static const Color riskLow      = Color(0xFF059669);

  @Deprecated('Use HealthcareColors.of(context).vitaWarning')
  static const Color riskModerate = Color(0xFFD97706);

  @Deprecated('Use Theme.of(context).colorScheme.error')
  static const Color riskHigh     = Color(0xFFDC2626);

  @Deprecated('Use HealthcareColors.of(context).vitaCritical')
  static const Color riskCritical = Color(0xFF991B1B);

  // ── Drug schedule colors (TGA AU) ─────────────────────────────────────────────

  @Deprecated('Use HealthcareColors.of(context).vitaGood')
  static const Color scheduleS2 = Color(0xFF388E3C);

  @Deprecated('Use HealthcareColors.of(context).vitaWarning')
  static const Color scheduleS4 = Color(0xFFB45309);

  @Deprecated('Use HealthcareColors.of(context).vitaCritical')
  static const Color scheduleS8 = Color(0xFFC62828);

  // ── Health metric status ──────────────────────────────────────────────────────

  @Deprecated('Use HealthcareColors.of(context).vitaGood')
  static const Color metricNormal   = Color(0xFF059669);

  @Deprecated('Use Theme.of(context).colorScheme.error')
  static const Color metricHigh     = Color(0xFFDC2626);

  @Deprecated('Use HealthcareColors.of(context).vitaWarning')
  static const Color metricLow      = Color(0xFF00B4A2);

  @Deprecated('Use HealthcareColors.of(context).vitaCritical')
  static const Color metricCritical = Color(0xFF880E4F);

  // ── Semantic surface tints ────────────────────────────────────────────────────

  @Deprecated('Use cs.primary.withValues(alpha: 0.08)')
  static const Color primarySurface  = Color(0x121A4B8F);

  @Deprecated('Use cs.primary.withValues(alpha: 0.15)')
  static const Color primarySurface2 = Color(0x261A4B8F);

  @Deprecated('Use cs.error.withValues(alpha: 0.07)')
  static const Color errorSurface    = Color(0x12DC2626);

  @Deprecated('Use HealthcareColors.of(context).vitaWarning.withValues(alpha: 0.08)')
  static const Color warningSurface  = Color(0x14D97706);

  @Deprecated('Use HealthcareColors.of(context).emergency.withValues(alpha: 0.04)')
  static const Color emergencySurface = Color(0x0A991B1B);

  @Deprecated('Use HealthcareColors.of(context).vitaGood.withValues(alpha: 0.08)')
  static const Color successSurface  = Color(0x14059669);

  @Deprecated('Use Colors.black.withValues(alpha: 0.04)')
  static const Color scrim           = Color(0x0A000000);

  // ── Spacing — 8pt grid ────────────────────────────────────────────────────────

  @Deprecated('Use inline const 2.0')
  static const double spacing2  = 2;

  @Deprecated('Use inline const 4.0')
  static const double spacingXS = 4;

  @Deprecated('Use inline const 8.0')
  static const double spacingSM = 8;

  @Deprecated('Use inline const 12.0')
  static const double spacing12 = 12;

  @Deprecated('Use inline const 16.0')
  static const double spacingMD = 16;

  @Deprecated('Use inline const 20.0')
  static const double spacing20 = 20;

  @Deprecated('Use inline const 24.0')
  static const double spacingLG = 24;

  @Deprecated('Use inline const 32.0')
  static const double spacingXL = 32;

  @Deprecated('Use inline const 40.0')
  static const double spacing40 = 40;

  @Deprecated('Use inline const 48.0')
  static const double spacing48 = 48;

  @Deprecated('Use inline const 56.0')
  static const double spacing56 = 56;

  @Deprecated('Use inline const 64.0')
  static const double spacing64 = 64;

  // ── Border radius ─────────────────────────────────────────────────────────────

  @Deprecated('Use AppRadius.xs (4.0)')
  static const double radiusXS  = 4;

  @Deprecated('Use AppRadius.sm (8.0)')
  static const double radiusSM  = 8;

  @Deprecated('Use AppRadius.md (12.0)')
  static const double radiusMD  = 12;

  @Deprecated('Use AppRadius.lg (16.0)')
  static const double radiusLG  = 16;

  @Deprecated('Use AppRadius.xxl (24.0) — note: xxl not xl')
  static const double radiusXL  = 24;

  @Deprecated('Use AppRadius.xxxl (28.0)')
  static const double radiusXXL = 28;

  @Deprecated('Use AppRadius.brXs')
  static const BorderRadius brXS  = BorderRadius.all(Radius.circular(4));

  @Deprecated('Use AppRadius.brSm')
  static const BorderRadius brSM  = BorderRadius.all(Radius.circular(8));

  @Deprecated('Use AppRadius.brMd')
  static const BorderRadius brMD  = BorderRadius.all(Radius.circular(12));

  @Deprecated('Use AppRadius.brLg')
  static const BorderRadius brLG  = BorderRadius.all(Radius.circular(16));

  @Deprecated('Use AppRadius.brXxl (24px maps to xxl, not xl)')
  static const BorderRadius brXL  = BorderRadius.all(Radius.circular(24));

  @Deprecated('Use AppRadius.brXxxl')
  static const BorderRadius brXXL = BorderRadius.all(Radius.circular(28));

  @Deprecated('Use AppRadius.brFull')
  static const BorderRadius brFull = BorderRadius.all(Radius.circular(9999));

  @Deprecated('Use AppRadius.xl as a raw double (20.0)')
  static const double radiusSheet  = 20.0;

  @Deprecated('Use AppRadius.bottomSheet')
  static const BorderRadius brSheet =
      BorderRadius.vertical(top: Radius.circular(20));

  // ── Animation ─────────────────────────────────────────────────────────────────
  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationMed  = Duration(milliseconds: 300);
  static const Duration durationSlow = Duration(milliseconds: 500);
  static const Curve    curveDefault = Curves.easeOutCubic;

  // ── Layout ────────────────────────────────────────────────────────────────────
  static const double navHeight = 80.0;

  // ── Elevation / shadows ───────────────────────────────────────────────────────

  @Deprecated('Inline const BoxShadow list: see migration guide')
  static const List<BoxShadow> elevation1 = [
    BoxShadow(color: Color(0x1F000000), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x14000000), blurRadius: 3, offset: Offset(0, 1)),
  ];

  @Deprecated('Inline const BoxShadow list: see migration guide')
  static const List<BoxShadow> elevation2 = [
    BoxShadow(color: Color(0x24000000), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 2)),
  ];

  @Deprecated('Inline const BoxShadow list: see migration guide')
  static const List<BoxShadow> elevation3 = [
    BoxShadow(color: Color(0x1F000000), blurRadius: 8, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x24000000), blurRadius: 3, offset: Offset(0, 1)),
  ];

  @Deprecated('Inline const BoxShadow list: see migration guide')
  static const List<BoxShadow> elevation4 = [
    BoxShadow(color: Color(0x1F000000), blurRadius: 10, offset: Offset(0, 6)),
    BoxShadow(color: Color(0x1F000000), blurRadius: 3,  offset: Offset(0, 2)),
  ];

  @Deprecated('Inline const BoxShadow list: see migration guide')
  static const List<BoxShadow> elevation5 = [
    BoxShadow(color: Color(0x1F000000), blurRadius: 12, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x1F000000), blurRadius: 4,  offset: Offset(0, 4)),
  ];

  // ── MD3 Type scale ────────────────────────────────────────────────────────────

  @Deprecated('Use Theme.of(context).textTheme.displayLarge')
  static const TextStyle displayLarge = TextStyle(
    fontSize: 57, fontWeight: FontWeight.w700, letterSpacing: -0.25,
    color: Color(0xFF0D1B3E),
  );

  @Deprecated('Use Theme.of(context).textTheme.displayMedium')
  static const TextStyle displayMedium = TextStyle(
    fontSize: 45, fontWeight: FontWeight.w700, color: Color(0xFF0D1B3E),
  );

  @Deprecated('Use Theme.of(context).textTheme.displaySmall')
  static const TextStyle displaySmall = TextStyle(
    fontSize: 36, fontWeight: FontWeight.w700, color: Color(0xFF0D1B3E),
  );

  @Deprecated('Use Theme.of(context).textTheme.headlineLarge')
  static const TextStyle headlineLarge = TextStyle(
    fontSize: 32, fontWeight: FontWeight.w700, color: Color(0xFF0D1B3E),
  );

  @Deprecated('Use Theme.of(context).textTheme.headlineMedium')
  static const TextStyle headlineMedium = TextStyle(
    fontSize: 28, fontWeight: FontWeight.w700, color: Color(0xFF0D1B3E),
  );

  @Deprecated('Use Theme.of(context).textTheme.headlineSmall')
  static const TextStyle headlineSmall = TextStyle(
    fontSize: 24, fontWeight: FontWeight.w600, color: Color(0xFF0D1B3E),
  );

  @Deprecated('Use Theme.of(context).textTheme.titleLarge')
  static const TextStyle titleLarge = TextStyle(
    fontSize: 22, fontWeight: FontWeight.w600, color: Color(0xFF0D1B3E),
  );

  @Deprecated('Use Theme.of(context).textTheme.titleMedium')
  static const TextStyle titleMedium = TextStyle(
    fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.15,
    color: Color(0xFF0D1B3E),
  );

  @Deprecated('Use Theme.of(context).textTheme.titleSmall')
  static const TextStyle titleSmall = TextStyle(
    fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1,
    color: Color(0xFF0D1B3E),
  );

  @Deprecated('Use Theme.of(context).textTheme.bodyLarge')
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16, fontWeight: FontWeight.w400, letterSpacing: 0.5,
    color: Color(0xFF0D1B3E),
  );

  @Deprecated('Use Theme.of(context).textTheme.bodyMedium')
  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14, fontWeight: FontWeight.w400, letterSpacing: 0.25,
    color: Color(0xFF0D1B3E),
  );

  @Deprecated('Use Theme.of(context).textTheme.bodySmall')
  static const TextStyle bodySmall = TextStyle(
    fontSize: 12, fontWeight: FontWeight.w400, letterSpacing: 0.4,
    color: Color(0xFF4A5978),
  );

  @Deprecated('Use Theme.of(context).textTheme.labelLarge')
  static const TextStyle labelLarge = TextStyle(
    fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1,
    color: Color(0xFF0D1B3E),
  );

  @Deprecated('Use Theme.of(context).textTheme.labelMedium')
  static const TextStyle labelMedium = TextStyle(
    fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5,
    color: Color(0xFF4A5978),
  );

  @Deprecated('Use Theme.of(context).textTheme.labelSmall')
  static const TextStyle labelSmall = TextStyle(
    fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5,
    color: Color(0xFF4A5978),
  );
}
