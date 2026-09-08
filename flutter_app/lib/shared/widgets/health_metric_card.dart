import 'package:flutter/material.dart';
import 'package:vitapulse_ai/shared/widgets/premium_surface.dart';
import 'package:vitapulse_ai/shared/widgets/shimmer_box.dart';
import 'package:vitapulse_ai/shared/widgets/tap_scale.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_spacing.dart';

/// Compact Apple Health / Google Fit–style metric chip for dashboards.
class HealthMetricCard extends StatelessWidget {
  const HealthMetricCard({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.onTap,
    this.loading = false,
    this.width = 118,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final VoidCallback onTap;
  final bool loading;
  final double width;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Semantics(
      label: loading ? '$label loading' : '$label: $value',
      button: true,
      child: SizedBox(
        width: width,
        child: TapScale(
          onTap: onTap,
          child: SoftSurface(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.x3,
              vertical: AppSpacing.x2,
            ),
            borderRadius: AppRadius.brLg,
            elevation: SoftSurfaceElevation.level1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 70),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: AppRadius.brSm,
                    ),
                    child: Icon(icon, size: 14, color: color),
                  ),
                  if (loading)
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShimmerLine(width: 56, height: 12, radius: 4),
                        SizedBox(height: 4),
                        ShimmerLine(width: 40, height: 10, radius: 4),
                      ],
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          value,
                          style: tt.titleSmall!.copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            height: 1.1,
                            color: cs.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          label,
                          style: tt.labelSmall!.copyWith(
                            color: cs.onSurfaceVariant,
                            fontSize: 10,
                            height: 1.1,
                          ),
                          maxLines: 1,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
