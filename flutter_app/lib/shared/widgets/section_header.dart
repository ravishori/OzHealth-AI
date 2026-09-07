import 'package:flutter/material.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_spacing.dart';

/// Consistent section title row used across home and feature hubs.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.color,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Color color;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.x1 + 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: AppRadius.brSm,
            ),
            child: Icon(icon, size: AppSpacing.iconSm - 4, color: color),
          ),
        ),
        const SizedBox(width: AppSpacing.x2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: tt.titleSmall!.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: tt.bodySmall!.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: 11,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.x2),
          trailing!,
        ],
      ],
    );
  }
}
