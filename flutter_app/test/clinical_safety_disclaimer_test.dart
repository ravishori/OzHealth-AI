import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/legal/legal_copy.dart';
import 'package:vitapulse_ai/shared/widgets/clinical_safety_banner.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppThemeBuilder.light(const AppThemeSettings()),
    home: Scaffold(body: child),
  );
}

void main() {
  group('HN-LEGAL-004 clinical safety disclaimers', () {
    testWidgets('LEGAL-04-01 AI banner shows required AI safety messaging',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const ClinicalSafetyBanner(kind: ClinicalDisclaimerKind.ai)),
      );
      expect(find.text(LegalCopy.aiBanner), findsOneWidget);
      expect(LegalCopy.aiBanner.contains('does not diagnose'), isTrue);
      expect(LegalCopy.aiBanner.contains('000'), isTrue);
      expect(LegalCopy.aiBanner.toLowerCase().contains('this diagnosis'),
          isFalse);
    });

    testWidgets('LEGAL-04-02 medicine banner for detail coverage',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
            const ClinicalSafetyBanner(kind: ClinicalDisclaimerKind.medicine)),
      );
      expect(find.text(LegalCopy.medicineBanner), findsOneWidget);
      expect(LegalCopy.medicineBanner.contains('general information'), isTrue);
      expect(LegalCopy.medicineBanner.contains('pharmacist'), isTrue);
      expect(
        LegalCopy.medicineBanner.toLowerCase().contains('safe for you'),
        isFalse,
      );
      expect(
        LegalCopy.medicineBanner.toLowerCase().contains('healthnest prescribed'),
        isFalse,
      );
    });

    test('LEGAL-04-03 medicine search uses shared medicine banner once', () {
      final src =
          File('lib/features/medicines/presentation/medicine_search_screen.dart')
              .readAsStringSync();
      expect(src.contains('ClinicalDisclaimerKind.medicine'), isTrue);
      expect(src.contains('ClinicalSafetyBanner'), isTrue);
      // Single banner wiring — not stacked duplicate kinds.
      expect(
        RegExp(r'ClinicalSafetyBanner').allMatches(src).length,
        1,
      );
      expect(src.toLowerCase().contains('this medicine is safe for you'),
          isFalse);
    });

    testWidgets('LEGAL-04-04 symptom banner is non-diagnostic', (tester) async {
      await tester.pumpWidget(
        _wrap(
            const ClinicalSafetyBanner(kind: ClinicalDisclaimerKind.symptom)),
      );
      expect(find.text(LegalCopy.symptomBanner), findsOneWidget);
      expect(LegalCopy.symptomBanner.contains('not a diagnosis'), isTrue);
      expect(LegalCopy.symptomBanner.contains('000'), isTrue);
      expect(LegalCopy.symptomBanner.toLowerCase().contains('ai has diagnosed'),
          isFalse);
    });

    test('LEGAL-04-05 prescription review uses OCR verification banner', () {
      final src = File(
              'lib/features/prescriptions/presentation/prescription_review_screen.dart')
          .readAsStringSync();
      expect(src.contains('ClinicalDisclaimerKind.prescriptionOcr'), isTrue);
      expect(LegalCopy.prescriptionOcrBanner.contains('unconfirmed'), isTrue);
      expect(LegalCopy.prescriptionOcrBanner.contains('Do not rely on OCR'),
          isTrue);
    });

    test('LEGAL-04-06 emergency/SOS retains dial-first + 000 disclaimer', () {
      expect(LegalCopy.emergencyBanner.contains('Medical emergency disclaimer'),
          isTrue);
      expect(LegalCopy.emergencyBanner.contains('call 000'), isTrue);
      expect(
        LegalCopy.emergencyBanner
            .contains('does not automatically SMS or push-notify contacts'),
        isTrue,
      );
      final screenSrc =
          File('lib/features/emergency/presentation/emergency_screen.dart')
              .readAsStringSync();
      expect(screenSrc.contains('ClinicalDisclaimerKind.emergency'), isTrue);
      expect(screenSrc.contains('SosHoldButton'), isTrue);
      expect(screenSrc.contains('tel:'), isTrue);
    });

    testWidgets('LEGAL-04-07 lab banner remains informational', (tester) async {
      await tester.pumpWidget(
        _wrap(const ClinicalSafetyBanner(kind: ClinicalDisclaimerKind.lab)),
      );
      expect(find.text(LegalCopy.labBanner), findsOneWidget);
      expect(LegalCopy.labBanner.contains('informational'), isTrue);
      expect(LegalCopy.labBanner.contains('does not diagnose'), isTrue);
      final src =
          File('lib/features/lab_analysis/presentation/lab_analysis_screen.dart')
              .readAsStringSync();
      expect(src.contains('ClinicalDisclaimerKind.lab'), isTrue);
      // One ClinicalSafetyBanner only (no stacked footer duplicate).
      expect(RegExp(r'ClinicalSafetyBanner').allMatches(src).length, 1);
    });

    test('LEGAL-04-08 disclaimer wording sourced from LegalCopy', () {
      expect(
        ClinicalSafetyBanner.textFor(ClinicalDisclaimerKind.ai),
        LegalCopy.aiBanner,
      );
      expect(
        ClinicalSafetyBanner.textFor(ClinicalDisclaimerKind.medicine),
        LegalCopy.medicineBanner,
      );
      expect(
        ClinicalSafetyBanner.textFor(ClinicalDisclaimerKind.prescriptionOcr),
        LegalCopy.prescriptionOcrBanner,
      );
      expect(
        ClinicalSafetyBanner.textFor(ClinicalDisclaimerKind.symptom),
        LegalCopy.symptomBanner,
      );
      expect(
        ClinicalSafetyBanner.textFor(ClinicalDisclaimerKind.lab),
        LegalCopy.labBanner,
      );
      expect(
        ClinicalSafetyBanner.textFor(ClinicalDisclaimerKind.emergency),
        LegalCopy.emergencyBanner,
      );
      expect(
        ClinicalSafetyBanner.textFor(ClinicalDisclaimerKind.interaction),
        LegalCopy.interactionBanner,
      );
    });

    testWidgets('LEGAL-04-09 single banner instance — no accidental stack',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const Column(
            children: [
              ClinicalSafetyBanner(kind: ClinicalDisclaimerKind.medicine),
            ],
          ),
        ),
      );
      expect(find.byType(ClinicalSafetyBanner), findsOneWidget);
      expect(find.text(LegalCopy.medicineBanner), findsOneWidget);
      expect(find.text(LegalCopy.aiBanner), findsNothing);
    });

    test('LEGAL-04-10 primary actions remain wired on clinical screens', () {
      final ai =
          File('lib/features/ai_assistant/presentation/ai_chat_screen.dart')
              .readAsStringSync();
      final med =
          File('lib/features/medicines/presentation/medicine_detail_screen.dart')
              .readAsStringSync();
      final search =
          File('lib/features/medicines/presentation/medicine_search_screen.dart')
              .readAsStringSync();
      final emergency =
          File('lib/features/emergency/presentation/emergency_screen.dart')
              .readAsStringSync();
      expect(ai.contains('ClinicalDisclaimerKind.ai'), isTrue);
      expect(ai.contains('_sendMessage') || ai.contains('_send'), isTrue);
      expect(med.contains('ClinicalDisclaimerKind.medicine'), isTrue);
      expect(med.contains('_buildBottomBar'), isTrue);
      expect(search.contains('_onMedicineTap'), isTrue);
      expect(emergency.contains('_buildEmergencyDisclaimer'), isTrue);
      expect(emergency.contains('SosHoldButton'), isTrue);

      const banned = [
        'This diagnosis is',
        'This medicine is safe for you',
        'You should stop taking',
        'HealthNest prescribed',
        'AI has diagnosed',
      ];
      for (final phrase in banned) {
        expect(LegalCopy.aiBanner.contains(phrase), isFalse);
        expect(LegalCopy.medicineBanner.contains(phrase), isFalse);
        expect(LegalCopy.symptomBanner.contains(phrase), isFalse);
        expect(LegalCopy.labBanner.contains(phrase), isFalse);
        expect(LegalCopy.prescriptionOcrBanner.contains(phrase), isFalse);
        expect(LegalCopy.emergencyBanner.contains(phrase), isFalse);
      }
    });
  });
}
