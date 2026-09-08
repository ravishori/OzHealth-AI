import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:vitapulse_ai/features/auth/presentation/screens/welcome_screen.dart';
import 'package:vitapulse_ai/features/legal/legal_screens.dart';
import 'package:vitapulse_ai/features/onboarding/onboarding_prefs.dart';
import 'package:vitapulse_ai/features/onboarding/presentation/onboarding_screen.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

Widget _theme(Widget child) {
  return MaterialApp(
    theme: AppThemeBuilder.light(const AppThemeSettings()),
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Box prefs;
  late Directory hiveDir;

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('hn_ux002_hive_');
    Hive.init(hiveDir.path);
    if (Hive.isBoxOpen('app_preferences')) {
      prefs = Hive.box('app_preferences');
      await prefs.clear();
    } else {
      prefs = await Hive.openBox('app_preferences');
    }
  });

  tearDown(() async {
    if (Hive.isBoxOpen('app_preferences')) {
      await Hive.box('app_preferences').clear();
      await Hive.box('app_preferences').close();
    }
  });

  test('UX02-FL-10 onboarding flag stores only completion bool — no PHI', () {
    expect(kOnboardingCompletedKey, 'onboarding_completed');
    final src =
        File('lib/features/onboarding/onboarding_prefs.dart').readAsStringSync();
    expect(src.contains('put(kOnboardingCompletedKey'), isTrue);
    expect(src.contains("'user_id'"), isFalse);
    expect(src.contains('"user_id"'), isFalse);
    expect(src.contains("'email'"), isFalse);
    expect(src.contains('access_token'), isFalse);
    expect(src.contains("'phone'"), isFalse);
    expect(src.contains('password'), isFalse);
  });

  test('UX02 default steps only reference existing feature routes', () {
    final router =
        File('lib/core/router/app_router.dart').readAsStringSync();
    for (final step in kDefaultOnboardingSteps) {
      final leaf = step.featureRoute.split('/').last;
      expect(router.contains("path: '$leaf'"), isTrue,
          reason: 'missing route for ${step.featureRoute}');
    }
    expect(kDefaultOnboardingSteps.length, 5);
  });

  testWidgets('UX02-FL-01 Welcome and onboarding entry render', (tester) async {
    await tester.pumpWidget(_theme(const WelcomeScreen()));
    await tester.pumpAndSettle();
    expect(find.text('HealthNest'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);

    await tester.pumpWidget(
      _theme(
        OnboardingScreen(
          onCompleted: () async {},
          exitLoggedIn: false,
          onExitNavigate: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('onboarding_screen')), findsOneWidget);
    expect(find.text('Medicines & reminders'), findsOneWidget);
  });

  testWidgets('UX02-FL-02 Next advances to the next step', (tester) async {
    await tester.pumpWidget(
      _theme(
        OnboardingScreen(
          onCompleted: () async {},
          exitLoggedIn: false,
          onExitNavigate: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboarding_next')));
    await tester.pumpAndSettle();
    expect(find.text('Prescriptions & records'), findsOneWidget);
    expect(find.textContaining('Step 2 of'), findsOneWidget);
  });

  testWidgets('UX02-FL-03 Back returns to the previous step', (tester) async {
    await tester.pumpWidget(
      _theme(
        OnboardingScreen(
          onCompleted: () async {},
          exitLoggedIn: false,
          onExitNavigate: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboarding_next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboarding_back')));
    await tester.pumpAndSettle();
    expect(find.text('Medicines & reminders'), findsOneWidget);
  });

  testWidgets('UX02-FL-04 Skip exits onboarding', (tester) async {
    var completed = false;
    String? exitedTo;
    await tester.pumpWidget(
      _theme(
        OnboardingScreen(
          onCompleted: () async {
            completed = true;
          },
          exitLoggedIn: false,
          onExitNavigate: (loc) => exitedTo = loc,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(completed, isTrue);
    expect(exitedTo, '/auth/welcome');
  });

  testWidgets('UX02-FL-05 Finish records completion and exits', (tester) async {
    var completed = false;
    String? exitedTo;
    await tester.pumpWidget(
      _theme(
        OnboardingScreen(
          onCompleted: () async {
            completed = true;
          },
          exitLoggedIn: false,
          onExitNavigate: (loc) => exitedTo = loc,
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < kDefaultOnboardingSteps.length - 1; i++) {
      await tester.tap(find.byKey(const Key('onboarding_next')));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const Key('onboarding_finish')), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboarding_finish')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(completed, isTrue);
    expect(exitedTo, '/auth/welcome');
    // Completion persistence is covered by UX02-FL-06 (Hive put).
  });

  test('UX02-FL-06 completed onboarding is not shown again (prefs gate)',
      () async {
    expect(isOnboardingCompleted(box: prefs), isFalse);
    await markOnboardingCompleted(box: prefs);
    expect(isOnboardingCompleted(box: prefs), isTrue);
    final splash =
        File('lib/features/splash/splash_screen.dart').readAsStringSync();
    expect(splash.contains('isOnboardingCompleted()'), isTrue);
    expect(splash.contains('/auth/onboarding'), isTrue);
    expect(
      splash.contains('if (!isOnboardingCompleted())'),
      isTrue,
    );
  });

  test('UX02-FL-07 legal consent gate remains authoritative', () {
    final splash =
        File('lib/features/splash/splash_screen.dart').readAsStringSync();
    final consentIdx = splash.indexOf('/legal/consent');
    final onboardIdx = splash.indexOf('/auth/onboarding');
    expect(consentIdx, greaterThan(-1));
    expect(onboardIdx, greaterThan(consentIdx));
    expect(splash.contains('kLegalConsentKey'), isTrue);

    final consent =
        File('lib/features/legal/legal_screens.dart').readAsStringSync();
    expect(consent.contains("put(kLegalConsentKey, true)"), isTrue);
    expect(
      consent.indexOf("put(kLegalConsentKey, true)"),
      lessThan(consent.indexOf('/auth/onboarding')),
    );
  });

  testWidgets('UX02-FL-08 authenticated user reaches home after onboarding',
      (tester) async {
    String? exitedTo;
    await tester.pumpWidget(
      _theme(
        OnboardingScreen(
          onCompleted: () async {},
          exitLoggedIn: true,
          onExitNavigate: (loc) => exitedTo = loc,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(exitedTo, '/home');
  });

  testWidgets('UX02-FL-09 accessibility semantics for primary controls',
      (tester) async {
    await tester.pumpWidget(
      _theme(
        OnboardingScreen(
          onCompleted: () async {},
          exitLoggedIn: false,
          onExitNavigate: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Skip onboarding'), findsOneWidget);
    expect(find.bySemanticsLabel('Next onboarding step'), findsOneWidget);

    for (var i = 0; i < kDefaultOnboardingSteps.length - 1; i++) {
      await tester.tap(find.byKey(const Key('onboarding_next')));
      await tester.pumpAndSettle();
    }
    expect(find.bySemanticsLabel('Finish onboarding'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Back to previous onboarding step'),
      findsOneWidget,
    );
    // Every default step declares a screen-reader description.
    for (final step in kDefaultOnboardingSteps) {
      expect(step.semanticsLabel, isNotEmpty);
    }
    final formSrc = File(
            'lib/features/onboarding/presentation/onboarding_screen.dart')
        .readAsStringSync();
    expect(formSrc.contains('Skip onboarding'), isTrue);
    expect(formSrc.contains('Finish onboarding'), isTrue);
    expect(formSrc.contains('semanticsLabel'), isTrue);
  });

  test('UX02 router + consent wiring present', () {
    final router =
        File('lib/core/router/app_router.dart').readAsStringSync();
    expect(router.contains('/auth/onboarding'), isTrue);
    expect(router.contains('OnboardingScreen'), isTrue);
    expect(kLegalConsentKey, 'legal_consent_v1');
  });
}
