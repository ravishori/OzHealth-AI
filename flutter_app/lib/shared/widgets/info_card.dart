import 'package:flutter/material.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_spacing.dart';

/// Section card with a coloured icon header, optional trailing widget,
/// and arbitrary child content. Replaces the scattered _card() helper
/// patterns across profile and other feature screens.
class InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color? iconColor;
  final Widget? trailing;
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  const InfoCard({
    super.key,
    required this.title,
    required this.icon,
    this.iconColor,
    this.trailing,
    required this.children,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final ic = iconColor ?? Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: padding ?? const EdgeInsets.all(AppSpacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: ic.withValues(alpha: 0.1),
                    borderRadius: AppRadius.brSm,
                  ),
                  child: Icon(icon, size: 18, color: ic),
                ),
                const SizedBox(width: AppSpacing.x2),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            if (children.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.x4),
              ...children,
            ],
          ],
        ),
      ),
    );
  }
}
