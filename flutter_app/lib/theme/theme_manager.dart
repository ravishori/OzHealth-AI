import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'design_tokens/app_radius.dart';
import 'design_tokens/app_spacing.dart';
import 'design_tokens/app_typography.dart';
import 'theme_extensions.dart';

// ─── Enums ────────────────────────────────────────────────────────────────────

enum AppThemeVariant {
  healthcareClassic,
  modernBlue,
  wellnessGreen,
  professionalDark,
  accessibility,
  australianClinical,
}

extension AppThemeVariantX on AppThemeVariant {
  String get label => switch (this) {
    AppThemeVariant.healthcareClassic  => 'Healthcare Classic',
    AppThemeVariant.modernBlue         => 'Modern Blue',
    AppThemeVariant.wellnessGreen      => 'Wellness Green',
    AppThemeVariant.professionalDark   => 'Professional Dark',
    AppThemeVariant.accessibility      => 'Accessibility',
    AppThemeVariant.australianClinical => 'Australian Clinical',
  };

  String get description => switch (this) {
    AppThemeVariant.healthcareClassic  =>
      'Classic teal palette — professional and calming',
    AppThemeVariant.modernBlue         =>
      'Corporate blue — tech-forward and clean',
    AppThemeVariant.wellnessGreen      =>
      'Nature-inspired greens — calm and minimal',
    AppThemeVariant.professionalDark   =>
      'OLED dark mode — premium and high-contrast',
    AppThemeVariant.accessibility      =>
      'High contrast — WCAG AA, large touch targets',
    AppThemeVariant.australianClinical =>
      'Australian clinical colours — trusted and minimal',
  };

  Color get swatch => switch (this) {
    AppThemeVariant.healthcareClassic  => const Color(0xFF006A60),
    AppThemeVariant.modernBlue         => const Color(0xFF1855BF),
    AppThemeVariant.wellnessGreen      => const Color(0xFF2E6B33),
    AppThemeVariant.professionalDark   => const Color(0xFF0D1117),
    AppThemeVariant.accessibility      => const Color(0xFF000000),
    AppThemeVariant.australianClinical => const Color(0xFF00695C),
  };

  Color get accentSwatch => switch (this) {
    AppThemeVariant.healthcareClassic  => const Color(0xFF82D5C8),
    AppThemeVariant.modernBlue         => const Color(0xFFB4C4FF),
    AppThemeVariant.wellnessGreen      => const Color(0xFFB2EBB7),
    AppThemeVariant.professionalDark   => const Color(0xFF80CBC4),
    AppThemeVariant.accessibility      => const Color(0xFF0000CC),
    AppThemeVariant.australianClinical => const Color(0xFFE65100),
  };
}

// ─── Settings state ───────────────────────────────────────────────────────────

@immutable
class AppThemeSettings {
  const AppThemeSettings({
    this.variant       = AppThemeVariant.healthcareClassic,
    this.themeMode     = ThemeMode.system,
    this.cardStyle     = AppCardStyle.rounded,
    this.iconStyle     = AppIconStyle.filled,
    this.textSize      = AppTextSize.medium,
    this.density       = AppDisplayDensity.comfortable,
    this.animationSpeed = AppAnimationSpeed.normal,
  });

  final AppThemeVariant    variant;
  final ThemeMode          themeMode;
  final AppCardStyle       cardStyle;
  final AppIconStyle       iconStyle;
  final AppTextSize        textSize;
  final AppDisplayDensity  density;
  final AppAnimationSpeed  animationSpeed;

  AppThemeSettings copyWith({
    AppThemeVariant?    variant,
    ThemeMode?          themeMode,
    AppCardStyle?       cardStyle,
    AppIconStyle?       iconStyle,
    AppTextSize?        textSize,
    AppDisplayDensity?  density,
    AppAnimationSpeed?  animationSpeed,
  }) =>
      AppThemeSettings(
        variant:        variant        ?? this.variant,
        themeMode:      themeMode      ?? this.themeMode,
        cardStyle:      cardStyle      ?? this.cardStyle,
        iconStyle:      iconStyle      ?? this.iconStyle,
        textSize:       textSize       ?? this.textSize,
        density:        density        ?? this.density,
        animationSpeed: animationSpeed ?? this.animationSpeed,
      );

  // Hive persistence — simple integer map
  Map<String, int> toMap() => {
    'variant':        variant.index,
    'themeMode':      themeMode.index,
    'cardStyle':      cardStyle.index,
    'iconStyle':      iconStyle.index,
    'textSize':       textSize.index,
    'density':        density.index,
    'animationSpeed': animationSpeed.index,
  };

  static AppThemeSettings fromMap(Map<dynamic, dynamic> m) => AppThemeSettings(
    variant:        _safeVariant(m['variant']),
    themeMode:      _safeThemeMode(m['themeMode']),
    cardStyle:      _safeEnum(AppCardStyle.values,       m['cardStyle'],      1),
    iconStyle:      _safeEnum(AppIconStyle.values,       m['iconStyle'],      0),
    textSize:       _safeEnum(AppTextSize.values,        m['textSize'],       1),
    density:        _safeEnum(AppDisplayDensity.values,  m['density'],        1),
    animationSpeed: _safeEnum(AppAnimationSpeed.values,  m['animationSpeed'], 0),
  );

  static AppThemeVariant _safeVariant(dynamic v) {
    final i = v as int? ?? 0;
    return (i >= 0 && i < AppThemeVariant.values.length)
        ? AppThemeVariant.values[i]
        : AppThemeVariant.healthcareClassic;
  }

  static ThemeMode _safeThemeMode(dynamic v) {
    final i = v as int? ?? 0;
    return (i >= 0 && i < ThemeMode.values.length)
        ? ThemeMode.values[i]
        : ThemeMode.system;
  }

  static T _safeEnum<T>(List<T> values, dynamic v, int defaultIdx) {
    final i = v as int? ?? defaultIdx;
    return (i >= 0 && i < values.length) ? values[i] : values[defaultIdx];
  }
}

// ─── StateNotifier ─────────────────────────────────────────────────────────────

const _kBoxKey = 'theme_settings';

class ThemeManager extends StateNotifier<AppThemeSettings> {
  ThemeManager(this._box) : super(_load(_box));

  final Box _box;

  static AppThemeSettings _load(Box box) {
    final raw = box.get(_kBoxKey);
    if (raw is Map) return AppThemeSettings.fromMap(raw);
    return const AppThemeSettings();
  }

  Future<void> _persist() => _box.put(_kBoxKey, state.toMap());

  Future<void> setVariant(AppThemeVariant v) async {
    state = state.copyWith(variant: v);
    await _persist();
  }

  Future<void> setThemeMode(ThemeMode m) async {
    state = state.copyWith(themeMode: m);
    await _persist();
  }

  Future<void> setCardStyle(AppCardStyle s) async {
    state = state.copyWith(cardStyle: s);
    await _persist();
  }

  Future<void> setIconStyle(AppIconStyle s) async {
    state = state.copyWith(iconStyle: s);
    await _persist();
  }

  Future<void> setTextSize(AppTextSize s) async {
    state = state.copyWith(textSize: s);
    await _persist();
  }

  Future<void> setDensity(AppDisplayDensity d) async {
    state = state.copyWith(density: d);
    await _persist();
  }

  Future<void> setAnimationSpeed(AppAnimationSpeed s) async {
    state = state.copyWith(animationSpeed: s);
    await _persist();
  }

  void resetToDefaults() {
    state = const AppThemeSettings();
    _box.delete(_kBoxKey);
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final themeManagerProvider =
    StateNotifierProvider<ThemeManager, AppThemeSettings>((ref) {
  final box = Hive.box('app_preferences');
  return ThemeManager(box);
});
