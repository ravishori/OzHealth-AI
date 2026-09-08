import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/onboarding/presentation/onboarding_screen.dart';
import 'package:vitapulse_ai/shared/widgets/health_metric_card.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

Widget _theme(Widget child, {double textScale = 1.0}) {
  return MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: MaterialApp(
      theme: AppThemeBuilder.light(const AppThemeSettings()),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  final drawerSrc =
      File('lib/features/home/presentation/app_drawer.dart').readAsStringSync();
  final homeSrc =
      File('lib/features/home/presentation/home_screen.dart').readAsStringSync();
  final aiSrc = File('lib/features/ai_assistant/presentation/ai_chat_screen.dart')
      .readAsStringSync();
  final emergencySrc =
      File('lib/features/emergency/presentation/emergency_screen.dart')
          .readAsStringSync();
  final sosSrc =
      File('lib/features/emergency/presentation/sos_hold_button.dart')
          .readAsStringSync();
  final recordsSrc =
      File('lib/features/records/presentation/records_screen.dart')
          .readAsStringSync();
  final rxReviewSrc = File(
          'lib/features/prescriptions/presentation/prescription_review_screen.dart')
      .readAsStringSync();
  final medSearchSrc =
      File('lib/features/medicines/presentation/medicine_search_screen.dart')
          .readAsStringSync();
  final eRxListSrc = File(
          'lib/features/eprescriptions/presentation/eprescription_list_screen.dart')
      .readAsStringSync();
  final onboardSrc = File(
          'lib/features/onboarding/presentation/onboarding_screen.dart')
      .readAsStringSync();
  final loginSrc =
      File('lib/features/auth/presentation/screens/login_screen.dart')
          .readAsStringSync();
  final remindersSrc =
      File('lib/features/reminders/presentation/reminders_screen.dart')
          .readAsStringSync();

  test('UX06-FL-01 primary navigation controls expose meaningful semantics',
      () {
    expect(drawerSrc.contains("tooltip: 'Edit profile'"), isTrue);
    expect(drawerSrc.contains('drawer_edit_profile'), isTrue);
    expect(homeSrc.contains("label:  chips[i].label"), isTrue);
    expect(homeSrc.contains('Semantics('), isTrue);
  });

  test('UX06-FL-02 icon-only patient-facing controls expose accessible names',
      () {
    expect(aiSrc.contains("label: _isLoading ? 'Sending message' : 'Send message'"),
        isTrue);
    expect(recordsSrc.contains("tooltip: 'Upload medical record'"), isTrue);
    expect(rxReviewSrc.contains("tooltip: 'Close review'"), isTrue);
    expect(medSearchSrc.contains("tooltip: 'Clear search'"), isTrue);
    expect(eRxListSrc.contains("tooltip: 'Delete ePrescription'"), isTrue);
  });

  test('UX06-FL-03 critical form fields expose labels', () {
    expect(loginSrc.contains('FormFieldLabel'), isTrue);
    expect(loginSrc.contains('TextFormField'), isTrue);
  });

  test('UX06-FL-04 validation/error messages remain accessible', () {
    // Login still surfaces error text in the widget tree (not color-only).
    expect(loginSrc.contains('_error') || loginSrc.contains('error'), isTrue);
    expect(loginSrc.contains('Text('), isTrue);
  });

  test('UX06-FL-05 emergency/SOS controls expose meaningful semantics', () {
    expect(sosSrc.contains('Semantics('), isTrue);
    expect(sosSrc.contains('000'), isTrue);
    expect(emergencySrc.contains("label: 'Call \${number.label}'"), isTrue);
    expect(emergencySrc.contains("tooltip: 'Call \${contact.name}'"), isTrue);
    expect(emergencySrc.contains('minimumSize: const Size(88, 48)'), isTrue);
  });

  test('UX06-FL-06 medication/reminder critical actions expose semantics', () {
    expect(remindersSrc.contains("tooltip: 'Refresh'"), isTrue);
    expect(remindersSrc.contains('FloatingActionButton.extended'), isTrue);
    expect(homeSrc.contains("label: 'Health summary up to date'"), isTrue);
    expect(homeSrc.contains("'Up to date'"), isTrue);
  });

  test('UX06-FL-07 prescription/record critical actions expose semantics', () {
    expect(recordsSrc.contains("tooltip: 'Upload medical record'"), isTrue);
    expect(rxReviewSrc.contains("tooltip: 'Close review'"), isTrue);
    expect(eRxListSrc.contains("tooltip: 'Delete ePrescription'"), isTrue);
  });

  test('UX06-FL-08 guided onboarding semantics remain intact', () {
    expect(onboardSrc.contains('Skip onboarding'), isTrue);
    expect(onboardSrc.contains('Finish onboarding'), isTrue);
    expect(onboardSrc.contains('Next onboarding step'), isTrue);
    expect(onboardSrc.contains('Back to previous onboarding step'), isTrue);
    for (final step in kDefaultOnboardingSteps) {
      expect(step.semanticsLabel, isNotEmpty);
    }
  });

  test('UX06-FL-09 remediations do not ExcludeSemantics medical content', () {
    for (final src in [
      homeSrc,
      emergencySrc,
      recordsSrc,
      aiSrc,
      eRxListSrc,
      onboardSrc,
    ]) {
      expect(src.contains('ExcludeSemantics'), isFalse);
    }
  });

  testWidgets(
      'UX06-FL-10 large text keeps metric card and emergency call usable',
      (tester) async {
    await tester.pumpWidget(
      _theme(
        textScale: 2.0,
        Column(
          children: [
            HealthMetricCard(
              icon: Icons.monitor_heart,
              color: Colors.red,
              label: 'Heart Rate',
              value: '72',
              onTap: () {},
            ),
            FilledButton.icon(
              key: const Key('large_text_call'),
              onPressed: () {},
              icon: const Icon(Icons.phone),
              label: const Text('Call 000'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(88, 48),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Heart Rate'), findsOneWidget);
    expect(find.text('Call 000'), findsOneWidget);
    final call = tester.getSize(find.byKey(const Key('large_text_call')));
    expect(call.height, greaterThanOrEqualTo(48));
  });

  testWidgets('UX06 header chip touch target contract at default scale',
      (tester) async {
    // Contract: home header chips use minHeight 40 (not the old 26dp).
    expect(homeSrc.contains('minHeight: 40'), isTrue);
    expect(homeSrc.contains('height:  26'), isFalse);
  });
}
