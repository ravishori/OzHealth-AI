import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/features/legal/legal_copy.dart';
import 'package:vitapulse_ai/features/settings/data/app_info.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_spacing.dart';

/// HN-SET-006 — About. Only repository-backed product metadata.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: AppSpacing.screenPadding,
        children: [
          Text(
            AppInfo.appName,
            key: const Key('about-app-name'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            AppInfo.tagline,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
          ),
          const SizedBox(height: 16),
          const Text(
            AppInfo.versionLabel,
            key: Key('about-version'),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          Text(
            LegalCopy.medicalDisclaimer,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy policy'),
            onTap: () => context.push('/legal/privacy'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('Terms of use'),
            onTap: () => context.push('/legal/terms'),
          ),
        ],
      ),
    );
  }
}
