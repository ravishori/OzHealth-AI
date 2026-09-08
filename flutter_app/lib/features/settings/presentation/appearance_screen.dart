import 'package:flutter/material.dart';
import 'package:vitapulse_ai/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitapulse_ai/core/locale/locale_controller.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_spacing.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_typography.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';
import 'package:vitapulse_ai/theme/widgets/theme_preview_card.dart';

class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(themeManagerProvider);
    final manager  = ref.read(themeManagerProvider.notifier);
    final locale   = ref.watch(localeControllerProvider);
    final localeCtl = ref.read(localeControllerProvider.notifier);
    final l10n     = AppLocalizations.of(context);
    final cs       = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appearance),
        centerTitle: false,
      ),
      body: ListView(
        padding: AppSpacing.screenPadding,
        children: [
          // ── Language (HN-FUTURE-006) ───────────────────────────────────────
          _SectionHeader(l10n.language),
          const SizedBox(height: AppSpacing.x2),
          Text(
            l10n.languageSubtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpacing.x3),
          Semantics(
            label: l10n.language,
            child: Column(
              children: [
                RadioListTile<String?>(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.languageSystem),
                  value: null,
                  groupValue: locale?.languageCode,
                  onChanged: (_) async {
                    await localeCtl.useSystemLocale();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.settingsSaved)),
                      );
                    }
                  },
                ),
                RadioListTile<String?>(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.languageEnglish),
                  value: 'en',
                  groupValue: locale?.languageCode,
                  onChanged: (v) => _onLanguageSelected(context, localeCtl, l10n, v),
                ),
                RadioListTile<String?>(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.languageHindi),
                  value: 'hi',
                  groupValue: locale?.languageCode,
                  onChanged: (v) => _onLanguageSelected(context, localeCtl, l10n, v),
                ),
                RadioListTile<String?>(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.languageMarathi),
                  value: 'mr',
                  groupValue: locale?.languageCode,
                  onChanged: (v) => _onLanguageSelected(context, localeCtl, l10n, v),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(
            l10n.welcomeLongSample,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(
            '${l10n.emergencyCallZeroZeroZero} — ${l10n.medicalDisclaimerShort}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpacing.x6),

          // ── Theme ──────────────────────────────────────────────────────────
          const _SectionHeader('Theme'),
          const SizedBox(height: AppSpacing.x3),
          SizedBox(
            height: 210,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: AppSpacing.x2),
              itemCount: AppThemeVariant.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.x3),
              itemBuilder: (_, i) {
                final v = AppThemeVariant.values[i];
                return ThemePreviewCard(
                  variant:    v,
                  isSelected: settings.variant == v,
                  onTap:      () => manager.setVariant(v),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.x1),
          // Description of current theme
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _ThemeDescription(
              key: ValueKey(settings.variant),
              settings: settings,
            ),
          ),
          const SizedBox(height: AppSpacing.x6),

          // ── Dark Mode ──────────────────────────────────────────────────────
          const _SectionHeader('Dark Mode'),
          const SizedBox(height: AppSpacing.x3),
          _SegmentRow<ThemeMode>(
            options: const [ThemeMode.system, ThemeMode.light, ThemeMode.dark],
            labels:  const ['System', 'Light', 'Dark'],
            icons:   const [Icons.brightness_auto, Icons.light_mode_outlined, Icons.dark_mode_outlined],
            current: settings.themeMode,
            onSelect: manager.setThemeMode,
          ),
          const SizedBox(height: AppSpacing.x6),

          // ── Card Style ─────────────────────────────────────────────────────
          const _SectionHeader('Card Style'),
          const SizedBox(height: AppSpacing.x3),
          _SegmentRow<AppCardStyle>(
            options: AppCardStyle.values,
            labels:  const ['Rounded', 'Square', 'Soft'],
            icons:   const [
              Icons.rounded_corner,
              Icons.crop_square_outlined,
              Icons.blur_on_outlined,
            ],
            current:  settings.cardStyle,
            onSelect: manager.setCardStyle,
          ),
          const SizedBox(height: AppSpacing.x6),

          // ── Icon Style ─────────────────────────────────────────────────────
          const _SectionHeader('Icon Style'),
          const SizedBox(height: AppSpacing.x3),
          _SegmentRow<AppIconStyle>(
            options: AppIconStyle.values,
            labels:  const ['Filled', 'Outlined'],
            icons:   const [Icons.star, Icons.star_outline],
            current:  settings.iconStyle,
            onSelect: manager.setIconStyle,
          ),
          const SizedBox(height: AppSpacing.x6),

          // ── Text Size ──────────────────────────────────────────────────────
          const _SectionHeader('Text Size'),
          const SizedBox(height: AppSpacing.x3),
          _SegmentRow<AppTextSize>(
            options: AppTextSize.values,
            labels:  const ['Small', 'Medium', 'Large', 'X-Large'],
            icons:   const [
              Icons.text_fields,
              Icons.format_size,
              Icons.text_increase,
              Icons.zoom_in,
            ],
            current:  settings.textSize,
            onSelect: manager.setTextSize,
          ),
          const SizedBox(height: AppSpacing.x6),

          // ── Display Density ────────────────────────────────────────────────
          const _SectionHeader('Display Density'),
          const SizedBox(height: AppSpacing.x3),
          _SegmentRow<AppDisplayDensity>(
            options: AppDisplayDensity.values,
            labels:  const ['Compact', 'Comfortable', 'Spacious'],
            icons:   const [
              Icons.density_small,
              Icons.density_medium,
              Icons.density_large,
            ],
            current:  settings.density,
            onSelect: manager.setDensity,
          ),
          const SizedBox(height: AppSpacing.x6),

          // ── Animations ─────────────────────────────────────────────────────
          const _SectionHeader('Animations'),
          const SizedBox(height: AppSpacing.x3),
          _SegmentRow<AppAnimationSpeed>(
            options: AppAnimationSpeed.values,
            labels:  const ['Normal', 'Reduced', 'Off'],
            icons:   const [
              Icons.animation,
              Icons.slow_motion_video_outlined,
              Icons.motion_photos_off_outlined,
            ],
            current:  settings.animationSpeed,
            onSelect: manager.setAnimationSpeed,
          ),
          const SizedBox(height: AppSpacing.x8),

          // ── Reset ──────────────────────────────────────────────────────────
          OutlinedButton.icon(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Reset Appearance'),
                  content: const Text(
                    'This will restore all appearance settings to their defaults.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(l10n.cancel),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Reset'),
                    ),
                  ],
                ),
              );
              if (confirm == true) manager.resetToDefaults();
            },
            icon: const Icon(Icons.restore),
            label: const Text('Reset to Defaults'),
            style: OutlinedButton.styleFrom(
              foregroundColor: cs.error,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _onLanguageSelected(
  BuildContext context,
  LocaleController localeCtl,
  AppLocalizations l10n,
  String? code,
) async {
  if (code == null) {
    await localeCtl.useSystemLocale();
  } else {
    await localeCtl.setLocale(Locale(code));
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.settingsSaved)),
    );
  }
}

// ─── Subwidgets ───────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      );
}

class _SegmentRow<T> extends StatelessWidget {
  const _SegmentRow({
    required this.options,
    required this.labels,
    required this.icons,
    required this.current,
    required this.onSelect,
  });

  final List<T> options;
  final List<String> labels;
  final List<IconData> icons;
  final T current;
  final void Function(T) onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Wrap(
      spacing: AppSpacing.x2,
      runSpacing: AppSpacing.x2,
      children: List.generate(options.length, (i) {
        final selected = options[i] == current;
        return InkWell(
          onTap: () => onSelect(options[i]),
          borderRadius: AppRadius.brMd,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.x3,
              vertical:   AppSpacing.x2,
            ),
            decoration: BoxDecoration(
              color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
              borderRadius: AppRadius.brMd,
              border: Border.all(
                color: selected ? cs.primary : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icons[i],
                  size:  16,
                  color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.x1),
                Text(
                  labels[i],
                  style: tt.labelMedium?.copyWith(
                    color:      selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _ThemeDescription extends StatelessWidget {
  const _ThemeDescription({super.key, required this.settings});
  final AppThemeSettings settings;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v  = settings.variant;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.x3),
      decoration: BoxDecoration(
        color:        v.swatch.withValues(alpha: 0.08),
        borderRadius: AppRadius.brMd,
        border: Border.all(
          color: v.swatch.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color:        v.swatch,
              borderRadius: AppRadius.brFull,
            ),
            child: Icon(
              _iconFor(v),
              size:  16,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: AppSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color:      v.swatch,
                    )),
                Text(v.description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(AppThemeVariant v) => switch (v) {
    AppThemeVariant.healthcareClassic  => Icons.local_hospital_outlined,
    AppThemeVariant.modernBlue         => Icons.business_center_outlined,
    AppThemeVariant.wellnessGreen      => Icons.spa_outlined,
    AppThemeVariant.professionalDark   => Icons.nights_stay_outlined,
    AppThemeVariant.accessibility      => Icons.accessibility_new,
    AppThemeVariant.australianClinical => Icons.health_and_safety_outlined,
  };
}
