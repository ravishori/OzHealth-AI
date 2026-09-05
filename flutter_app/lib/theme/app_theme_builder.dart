import 'package:flutter/material.dart';
import 'design_tokens/app_colors.dart';
import 'design_tokens/app_radius.dart';
import 'design_tokens/app_spacing.dart';
import 'design_tokens/app_typography.dart';
import 'theme_extensions.dart';
import 'theme_manager.dart';

/// Builds [ThemeData] for any [AppThemeSettings] combination.
/// Called from [VitaPulseApp] every time the theme state changes.
abstract final class AppThemeBuilder {
  static ThemeData light(AppThemeSettings s) =>
      _build(AppColors.lightScheme(s.variant), s);

  static ThemeData dark(AppThemeSettings s) =>
      _build(AppColors.darkScheme(s.variant), s);

  // ── Core builder ────────────────────────────────────────────────────────────

  static ThemeData _build(ColorScheme scheme, AppThemeSettings s) {
    final textTheme   = AppTypography.textTheme(s.textSize);
    final cardBr      = AppRadius.cardRadius(s.cardStyle);
    final overrides   = AppColors.healthcareOverrides(s.variant);
    final healthcare  = healthcareColorsFor(
      cardStyle:      s.cardStyle,
      iconStyle:      s.iconStyle,
      animationSpeed: s.animationSpeed,
      density:        s.density,
      aiAccent:       overrides.aiAccent,
      aiContainer:    overrides.aiContainer,
      onAiContainer:  overrides.onAiContainer,
      prescription:   overrides.prescription,
      labReport:      overrides.labReport,
      radiology:      overrides.radiology,
      discharge:      overrides.discharge,
    );

    // Accessibility theme: force minimum touch-target size
    final tapTarget = s.variant == AppThemeVariant.accessibility
        ? MaterialTapTargetSize.padded
        : MaterialTapTargetSize.padded; // always padded for healthcare

    return ThemeData(
      useMaterial3:        true,
      colorScheme:         scheme,
      extensions:          [healthcare],
      textTheme:           textTheme,
      materialTapTargetSize: tapTarget,

      // ── AppBar ─────────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor:        scheme.surface,
        foregroundColor:        scheme.onSurface,
        surfaceTintColor:       scheme.surfaceTint,
        elevation:              0,
        scrolledUnderElevation: 2,
        shadowColor:            scheme.shadow.withValues(alpha: 0.12),
        centerTitle:            false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color:      scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        iconTheme:  IconThemeData(color: scheme.onSurface, size: AppSpacing.iconMd),
        actionsIconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: AppSpacing.iconMd),
      ),

      // ── Navigation Bar (bottom) ────────────────────────────────────────────
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor:   scheme.surface,
        surfaceTintColor:  scheme.surfaceTint,
        indicatorColor:    scheme.primaryContainer,
        elevation:         3,
        height:            68,
        labelBehavior:     NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: scheme.onPrimaryContainer, size: AppSpacing.iconMd);
          }
          return IconThemeData(color: scheme.onSurfaceVariant, size: AppSpacing.iconMd);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final base = textTheme.labelSmall ?? const TextStyle();
          if (states.contains(WidgetState.selected)) {
            return base.copyWith(
              color:      scheme.onSurface,
              fontWeight: FontWeight.w700,
            );
          }
          return base.copyWith(color: scheme.onSurfaceVariant);
        }),
      ),

      // ── Navigation Drawer ──────────────────────────────────────────────────
      drawerTheme: DrawerThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
        elevation: 1,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(AppRadius.xxl)),
        ),
      ),

      // ── Card ───────────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        elevation:    0,
        color:        scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
        shape: RoundedRectangleBorder(
          borderRadius: cardBr,
          side: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),

      // ── Buttons ────────────────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor:  scheme.primary,
          foregroundColor:  scheme.onPrimary,
          minimumSize:      const Size(0, 48),
          padding:          const EdgeInsets.symmetric(horizontal: AppSpacing.x4, vertical: AppSpacing.x3),
          elevation:        0,
          shape:            const RoundedRectangleBorder(borderRadius: AppRadius.button),
          textStyle:        textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding:     const EdgeInsets.symmetric(horizontal: AppSpacing.x4, vertical: AppSpacing.x3),
          shape:       const RoundedRectangleBorder(borderRadius: AppRadius.button),
          textStyle:   textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize:  const Size(0, 48),
          padding:      const EdgeInsets.symmetric(horizontal: AppSpacing.x4, vertical: AppSpacing.x3),
          shape:        const RoundedRectangleBorder(borderRadius: AppRadius.button),
          side:         BorderSide(color: scheme.primary, width: 1.5),
          textStyle:    textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding:     const EdgeInsets.symmetric(horizontal: AppSpacing.x3),
          shape:       const RoundedRectangleBorder(borderRadius: AppRadius.button),
          textStyle:   textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),

      // ── FAB ────────────────────────────────────────────────────────────────
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation:       3,
        focusElevation:  4,
        shape:           const RoundedRectangleBorder(borderRadius: AppRadius.fab),
      ),

      // ── Input ──────────────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: AppRadius.textField,
          borderSide:   BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.textField,
          borderSide:   BorderSide(color: scheme.outline, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.textField,
          borderSide:   BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.textField,
          borderSide:   BorderSide(color: scheme.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.textField,
          borderSide:   BorderSide(color: scheme.error, width: 2),
        ),
        filled:          true,
        fillColor:       scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        contentPadding:  const EdgeInsets.symmetric(horizontal: AppSpacing.x4, vertical: AppSpacing.x3),
        hintStyle:       textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        labelStyle:      textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        floatingLabelStyle: textTheme.bodySmall?.copyWith(color: scheme.primary),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        errorStyle:      textTheme.bodySmall?.copyWith(color: scheme.error),
      ),

      // ── Chip ───────────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor:   scheme.surfaceContainerHighest,
        selectedColor:     scheme.primaryContainer,
        deleteIconColor:   scheme.onSurfaceVariant,
        labelStyle:        textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.chip,
          side:         BorderSide(color: scheme.outlineVariant),
        ),
        padding:  const EdgeInsets.symmetric(horizontal: AppSpacing.x3, vertical: AppSpacing.x1),
        elevation: 0,
        pressElevation: 1,
      ),

      // ── Dialog ─────────────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
        elevation: 6,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.dialog),
        titleTextStyle:   textTheme.headlineSmall?.copyWith(color: scheme.onSurface),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),

      // ── Bottom Sheet ───────────────────────────────────────────────────────
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor:   scheme.surface,
        surfaceTintColor:  scheme.surfaceTint,
        elevation:         4,
        showDragHandle:    true,
        dragHandleColor:   scheme.onSurfaceVariant.withValues(alpha: 0.4),
        modalElevation:    8,
        clipBehavior:      Clip.antiAlias,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.bottomSheet),
      ),

      // ── SnackBar ───────────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        behavior:          SnackBarBehavior.floating,
        backgroundColor:   scheme.inverseSurface,
        contentTextStyle:  textTheme.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        actionTextColor:   scheme.inversePrimary,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brSm),
        elevation:         4,
      ),

      // ── Progress indicators ────────────────────────────────────────────────
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color:            scheme.primary,
        linearTrackColor: scheme.primaryContainer,
        circularTrackColor: scheme.primaryContainer,
        linearMinHeight: 4,
      ),

      // ── List tile ──────────────────────────────────────────────────────────
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x5,
          vertical:   AppSpacing.x1,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
        tileColor:        Colors.transparent,
        iconColor:        scheme.onSurfaceVariant,
        textColor:        scheme.onSurface,
        subtitleTextStyle: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),

      // ── Switch / Checkbox / Radio ──────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.onPrimary;
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return null;
        }),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return null;
        }),
        checkColor: WidgetStateProperty.all(scheme.onPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return null;
        }),
      ),

      // ── Divider ────────────────────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color:     scheme.outlineVariant,
        thickness: 1,
        space:     1,
      ),

      // ── Badge ──────────────────────────────────────────────────────────────
      badgeTheme: BadgeThemeData(
        backgroundColor: scheme.primary,
        textColor:       scheme.onPrimary,
        textStyle:       textTheme.labelSmall,
        padding:         const EdgeInsets.symmetric(horizontal: AppSpacing.x2),
        smallSize:       8,
      ),

      // ── Tooltip ────────────────────────────────────────────────────────────
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color:        scheme.inverseSurface,
          borderRadius: AppRadius.brSm,
        ),
        textStyle: textTheme.labelSmall?.copyWith(color: scheme.onInverseSurface),
        preferBelow: true,
        waitDuration: const Duration(milliseconds: 500),
      ),

      // ── Icon ───────────────────────────────────────────────────────────────
      iconTheme: IconThemeData(
        color: scheme.onSurface,
        size:  AppSpacing.iconMd,
      ),

      // ── Tab bar ────────────────────────────────────────────────────────────
      tabBarTheme: TabBarThemeData(
        indicatorColor:    scheme.primary,
        labelColor:        scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorSize:     TabBarIndicatorSize.tab,
        labelStyle:        textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelStyle: textTheme.labelLarge,
        dividerColor:      scheme.outlineVariant,
      ),

      // ── Popup menu ─────────────────────────────────────────────────────────
      popupMenuTheme: PopupMenuThemeData(
        color:        scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
        elevation:    4,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
        textStyle:    textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
        labelTextStyle: WidgetStateProperty.all(
          textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
        ),
      ),
    );
  }
}
