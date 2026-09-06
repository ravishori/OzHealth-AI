import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vitapulse_ai/features/settings/data/app_info.dart';
import 'package:vitapulse_ai/shared/widgets/loading_button.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_spacing.dart';

typedef FeedbackEmailLauncher = Future<bool> Function(Uri uri);

/// HN-SET-006 — Feedback via the existing device mailto path.
///
/// Does not POST crash-report payloads (those handlers log message text).
/// Does not claim delivery unless the email app opens. The user still
/// has to send the message from their mail client.
class FeedbackScreen extends StatefulWidget {
  final FeedbackEmailLauncher? launchEmail;

  const FeedbackScreen({super.key, this.launchEmail});

  static const categories = ['General', 'Bug', 'Suggestion'];

  static Uri buildMailto({
    required String category,
    required String message,
  }) {
    final subject = Uri.encodeComponent(
      '${AppInfo.appName} feedback — $category',
    );
    final body = Uri.encodeComponent(
      '$message\n\n'
      '──────────────────────────────────────────\n'
      '${AppInfo.appName} ${AppInfo.versionLabel}',
    );
    return Uri.parse(
      'mailto:${AppInfo.supportEmail}?subject=$subject&body=$body',
    );
  }

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _message = TextEditingController();
  String _category = FeedbackScreen.categories.first;
  bool _launching = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _openEmail() async {
    if (_launching) return;
    final text = _message.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a message.')),
      );
      return;
    }

    setState(() => _launching = true);
    try {
      final uri = FeedbackScreen.buildMailto(
        category: _category,
        message: text,
      );
      final launcher = widget.launchEmail ?? _defaultLaunch;
      final opened = await launcher(uri);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            opened
                ? 'Your email app opened. Feedback is sent only if you send the email.'
                : 'Could not open the email app. Feedback was not sent.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  static Future<bool> _defaultLaunch(Uri uri) async {
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Feedback')),
      body: ListView(
        padding: AppSpacing.screenPadding,
        children: [
          Text(
            'Feedback is sent with your device email app. '
            'HealthNest does not store feedback on the server.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Text('Topic', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final c in FeedbackScreen.categories)
                ChoiceChip(
                  key: Key('feedback-category-$c'),
                  label: Text(c),
                  selected: _category == c,
                  onSelected: _launching
                      ? null
                      : (selected) {
                          if (selected) setState(() => _category = c);
                        },
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('feedback-message'),
            controller: _message,
            enabled: !_launching,
            minLines: 5,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Message',
              hintText: 'Tell us what we can improve',
              alignLabelWithHint: true,
              border: OutlineInputBorder(borderRadius: AppRadius.brMd),
            ),
          ),
          const SizedBox(height: 20),
          LoadingButton(
            key: const Key('feedback-open-email'),
            text: 'Open email app',
            loading: _launching,
            onPressed: _openEmail,
          ),
        ],
      ),
    );
  }
}
