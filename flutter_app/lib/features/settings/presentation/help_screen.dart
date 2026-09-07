import 'package:flutter/material.dart';
import 'package:vitapulse_ai/features/legal/legal_copy.dart';
import 'package:vitapulse_ai/shared/widgets/clinical_safety_banner.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_spacing.dart';

/// HN-SET-006 — Help for features that actually exist in this app.
///
/// Omits mocked, deferred, or gated-unavailable capabilities.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const sections = <(String, String)>[
    (
      'Prescriptions',
      'You can photograph or upload a prescription, review extracted text, '
          'and save it to your account. OCR and AI extraction are unconfirmed — '
          'verify every medicine with a doctor or pharmacist before acting.',
    ),
    (
      'Medicines',
      'Search the in-app medicine catalogue for general information. '
          'This is not prescribing advice. Do not change medication without '
          'professional advice.',
    ),
    (
      'Records',
      'Upload and view your medical documents (PDF or images). You can open '
          'or share a file you own. HealthNest does not interpret records as a '
          'diagnosis.',
    ),
    (
      'Reminders',
      'Create medication reminders for doses you enter. Alerts are scheduled '
          'on this device. Reminders do not confirm that a dose was taken.',
    ),
    (
      'Health metrics',
      'Log readings such as blood pressure, heart rate, blood sugar, or weight. '
          'Charts show values you recorded. They are not a diagnosis.',
    ),
    (
      'Emergency',
      'In a life-threatening emergency call 000 (or 112 from a mobile). '
          'SOS records your location and does not automatically SMS or '
          'push-notify contacts.',
    ),
    (
      'Family',
      'Add family-member profiles you manage. Their records and reminders stay '
          'on your account. There is no separate login for family members.',
    ),
    (
      'AI tools',
      'The health assistant, symptom checker, lab explainer, and interaction '
          'checker are informational. They do not diagnose or prescribe.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help')),
      body: ListView(
        padding: AppSpacing.screenPadding,
        children: [
          const ClinicalSafetyBanner(
            kind: ClinicalDisclaimerKind.emergency,
            rounded: true,
          ),
          const SizedBox(height: 16),
          Text(
            LegalCopy.medicalDisclaimerTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'This help describes tools in HealthNest. It is not medical advice.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          for (final section in sections) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.$1,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(section.$2, style: const TextStyle(fontSize: 14)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
