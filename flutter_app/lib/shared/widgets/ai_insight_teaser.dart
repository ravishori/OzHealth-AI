import 'package:flutter/material.dart';
import 'package:vitapulse_ai/shared/widgets/premium_surface.dart';
import 'package:vitapulse_ai/shared/widgets/tap_scale.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_spacing.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

/// Presentation-only AI insights teaser — navigates to existing insights route.
/// Does not invent clinical claims; copy stays advisory.
class AiInsightTeaser extends StatelessWidget {
  const AiInsightTeaser({
    super.key,
    required this.onOpen,
    this.title = 'AI health insights',
    this.body =
        'Review trends and gentle nudges based on your logged vitals and reminders.',
  });

  final VoidCallback onOpen;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);
    final tt = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      label: '$title. $body',
      child: TapScale(
        onTap: onOpen,
        child: SoftSurface(
          elevation: SoftSurfaceElevation.level2,
          borderRadius: AppRadius.brLg,
          padding: const EdgeInsets.all(AppSpacing.x4),
          color: hc.aiContainer.withValues(alpha: 0.55),
          border: Border.all(color: hc.aiAccent.withValues(alpha: 0.22)),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: hc.aiAccent.withValues(alpha: 0.16),
                  borderRadius: AppRadius.brMd,
                ),
                child: Icon(Icons.auto_awesome_rounded,
                    color: hc.aiAccent, size: 22),
              ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: tt.titleSmall!.copyWith(
                        fontWeight: FontWeight.w700,
                        color: hc.onAiContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: tt.bodySmall!.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: hc.aiAccent),
            ],
          ),
        ),
      ),
    );
  }
}
