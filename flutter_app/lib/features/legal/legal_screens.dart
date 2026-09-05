import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vitapulse_ai/core/config/app_env.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/utils/auth_storage.dart';
import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:vitapulse_ai/features/legal/legal_copy.dart';
import 'package:vitapulse_ai/shared/widgets/loading_button.dart';

const kLegalConsentKey = 'legal_consent_v1';

class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _accepted = false;

  Future<void> _continue() async {
    await Hive.box('app_preferences').put(kLegalConsentKey, true);
    if (!mounted) return;
    final loggedIn = await AuthStorage.isLoggedIn();
    if (!mounted) return;
    context.go(loggedIn ? '/home' : '/auth/welcome');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text(LegalCopy.medicalDisclaimerTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    LegalCopy.medicalDisclaimer,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ),
              CheckboxListTile(
                value: _accepted,
                onChanged: (v) => setState(() => _accepted = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'I understand this is not a medical device and I should consult a health professional.',
                ),
              ),
              TextButton(
                onPressed: () => context.push('/legal/privacy'),
                child: const Text('Privacy policy'),
              ),
              TextButton(
                onPressed: () => context.push('/legal/terms'),
                child: const Text('Terms of use'),
              ),
              const SizedBox(height: 8),
              LoadingButton(
                text: 'Continue',
                loading: false,
                color: cs.primary,
                onPressed: _accepted ? _continue : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _LegalTextScreen(
      title: 'Privacy policy',
      body: LegalCopy.privacyPolicy,
      externalUrl: AppEnv.publicPrivacyUrl,
    );
  }
}

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalTextScreen(
      title: 'Terms of use',
      body: LegalCopy.terms,
    );
  }
}

class _LegalTextScreen extends StatelessWidget {
  final String title;
  final String body;
  final String? externalUrl;

  const _LegalTextScreen({
    required this.title,
    required this.body,
    this.externalUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(body, style: Theme.of(context).textTheme.bodyLarge),
          if (externalUrl != null && externalUrl!.isNotEmpty) ...[
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse(externalUrl!),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text('Open hosted privacy policy'),
            ),
          ],
        ],
      ),
    );
  }
}

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes your account and associated app data. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ApiClient.delete('/users/me');
      await AuthStorage.clearAll();
      if (!mounted) return;
      context.go('/auth/welcome');
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = ErrorHandler.getMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final web = AppEnv.publicDeletionUrl;
    return Scaffold(
      appBar: AppBar(title: const Text('Delete account')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'You can delete your HealthNest account and the health data '
              'stored with it. Google Play also requires a web page for '
              'deletion requests if you have uninstalled the app.',
            ),
            if (web != null) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse(web),
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text('Web deletion request'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: cs.error)),
            ],
            const Spacer(),
            LoadingButton(
              text: 'Delete my account',
              loading: _loading,
              color: cs.error,
              onPressed: _loading ? null : _delete,
            ),
          ],
        ),
      ),
    );
  }
}
