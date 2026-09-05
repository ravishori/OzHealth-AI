import 'package:flutter/material.dart';
import '../theme_manager.dart';
import '../design_tokens/app_colors.dart';
import '../design_tokens/app_radius.dart';
import '../design_tokens/app_spacing.dart';

/// Compact visual preview of a theme variant.
/// Shows a mini AppBar, sample card, colors and a health card snippet.
class ThemePreviewCard extends StatelessWidget {
  const ThemePreviewCard({
    super.key,
    required this.variant,
    required this.isSelected,
    required this.onTap,
  });

  final AppThemeVariant variant;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final light    = AppColors.lightScheme(variant);
    final dark     = AppColors.darkScheme(variant);
    final isDark   = variant == AppThemeVariant.professionalDark;
    final scheme   = isDark ? dark : light;
    final surface  = isDark ? dark.surface : light.surface;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        width: 172,
        decoration: BoxDecoration(
          color:        Theme.of(context).colorScheme.surface,
          borderRadius: AppRadius.brLg,
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
            width: isSelected ? 2.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Mini AppBar ─────────────────────────────────────────────────
            Container(
              height: 36,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg - 1)),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.x2),
                child: Row(
                  children: [
                    Icon(Icons.menu, color: Colors.white, size: 14),
                    SizedBox(width: AppSpacing.x1),
                    Text(
                      'HealthNest',
                      style: TextStyle(
                        color:      Colors.white,
                        fontSize:   11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Spacer(),
                    Icon(Icons.person_outline, color: Colors.white, size: 14),
                  ],
                ),
              ),
            ),

            // ── Preview body ────────────────────────────────────────────────
            Container(
              color: isDark ? scheme.surface : const Color(0xFFF5F5F5),
              padding: const EdgeInsets.all(AppSpacing.x2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Color swatches
                  Row(
                    children: [
                      _Swatch(scheme.primary),
                      const SizedBox(width: 4),
                      _Swatch(scheme.secondary),
                      const SizedBox(width: 4),
                      _Swatch(scheme.tertiary),
                      const SizedBox(width: 4),
                      _Swatch(scheme.error),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.x2),

                  // Mini card
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.x2),
                    decoration: BoxDecoration(
                      color:        surface,
                      borderRadius: AppRadius.brMd,
                      border: Border.all(
                        color: scheme.outlineVariant,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Mini health card row
                        Row(
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color:        scheme.primaryContainer,
                                borderRadius: AppRadius.brSm,
                              ),
                              child: Icon(
                                Icons.favorite,
                                size: 11,
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    height: 5,
                                    width: 60,
                                    decoration: BoxDecoration(
                                      color:        scheme.onSurface.withValues(alpha: 0.8),
                                      borderRadius: AppRadius.brFull,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Container(
                                    height: 4,
                                    width: 44,
                                    decoration: BoxDecoration(
                                      color:        scheme.onSurfaceVariant.withValues(alpha: 0.5),
                                      borderRadius: AppRadius.brFull,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.x2),

                        // Mini button
                        Container(
                          height: 20,
                          decoration: BoxDecoration(
                            color:        scheme.primary,
                            borderRadius: AppRadius.brMd,
                          ),
                          child: Center(
                            child: Text(
                              'Book Appointment',
                              style: TextStyle(
                                color:      scheme.onPrimary,
                                fontSize:   7,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Footer: name + selected indicator ───────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.x3,
                vertical:   AppSpacing.x2,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(AppRadius.lg - 1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      variant.label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isSelected)
                    Icon(
                      Icons.check_circle,
                      size:  16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width:  16,
        height: 16,
        decoration: BoxDecoration(
          color:        color,
          borderRadius: AppRadius.brFull,
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.1),
            width: 0.5,
          ),
        ),
      );
}
