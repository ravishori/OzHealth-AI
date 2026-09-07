import 'package:flutter/material.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_spacing.dart';

/// Time-of-day greeting + first-name hero text (no emoji for a11y/contrast).
class DynamicGreeting {
  DynamicGreeting._();

  static String phrase([DateTime? now]) {
    final hour = (now ?? DateTime.now()).hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  static IconData icon([DateTime? now]) {
    final hour = (now ?? DateTime.now()).hour;
    if (hour < 12) return Icons.wb_sunny_outlined;
    if (hour < 17) return Icons.wb_twilight_outlined;
    return Icons.nights_stay_outlined;
  }

  static String firstName(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? 'there' : parts.first;
  }
}

/// Compact greeting column for app bars / dashboards.
class DynamicGreetingText extends StatelessWidget {
  const DynamicGreetingText({
    super.key,
    required this.userName,
    this.onPrimary = true,
    this.now,
  });

  final String userName;
  final bool onPrimary;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final greeting = DynamicGreeting.phrase(now);
    final name = DynamicGreeting.firstName(userName);
    final icon = DynamicGreeting.icon(now);
    final muted = onPrimary ? Colors.white70 : Theme.of(context).colorScheme.onSurfaceVariant;
    final strong = onPrimary ? Colors.white : Theme.of(context).colorScheme.onSurface;

    return Semantics(
      header: true,
      label: '$greeting, $name',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: muted),
              const SizedBox(width: AppSpacing.x1),
              Text(
                greeting,
                style: TextStyle(
                  color: muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            name,
            style: TextStyle(
              color: strong,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              height: 1.1,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
