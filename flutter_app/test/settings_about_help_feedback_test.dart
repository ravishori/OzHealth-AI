import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/legal/legal_copy.dart';
import 'package:vitapulse_ai/features/settings/data/app_info.dart';
import 'package:vitapulse_ai/features/settings/presentation/about_screen.dart';
import 'package:vitapulse_ai/features/settings/presentation/feedback_screen.dart';
import 'package:vitapulse_ai/features/settings/presentation/help_screen.dart';
import 'package:vitapulse_ai/shared/widgets/clinical_safety_banner.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppThemeBuilder.light(const AppThemeSettings()),
    home: child,
  );
}

void main() {
  final routerSrc =
      File('lib/core/router/app_router.dart').readAsStringSync();
  final drawerSrc =
      File('lib/features/home/presentation/app_drawer.dart').readAsStringSync();
  final moreSrc =
      File('lib/features/home/presentation/home_screen.dart').readAsStringSync();
  final aboutSrc = File(
          'lib/features/settings/presentation/about_screen.dart')
      .readAsStringSync();
  final helpSrc =
      File('lib/features/settings/presentation/help_screen.dart')
          .readAsStringSync();
  final feedbackSrc = File(
          'lib/features/settings/presentation/feedback_screen.dart')
      .readAsStringSync();
  final infoSrc =
      File('lib/features/settings/data/app_info.dart').readAsStringSync();

  test('SET-006-FL-01 Settings navigation exposes About/Help/Feedback', () {
    expect(routerSrc.contains("path: 'settings/about'"), isTrue);
    expect(routerSrc.contains("path: 'settings/help'"), isTrue);
    expect(routerSrc.contains("path: 'settings/feedback'"), isTrue);
    expect(routerSrc.contains('AboutScreen'), isTrue);
    expect(routerSrc.contains('HelpScreen'), isTrue);
    expect(routerSrc.contains('FeedbackScreen'), isTrue);

    expect(drawerSrc.contains("label: 'About'"), isTrue);
    expect(drawerSrc.contains("label: 'Help'"), isTrue);
    expect(drawerSrc.contains("label: 'Feedback'"), isTrue);
    expect(drawerSrc.contains("/home/settings/about"), isTrue);
    expect(drawerSrc.contains("/home/settings/help"), isTrue);
    expect(drawerSrc.contains("/home/settings/feedback"), isTrue);

    expect(moreSrc.contains("title: 'About'"), isTrue);
    expect(moreSrc.contains("title: 'Help'"), isTrue);
    expect(moreSrc.contains("title: 'Feedback'"), isTrue);
    expect(moreSrc.contains("/home/settings/about"), isTrue);
  });

  testWidgets('SET-006-FL-02 About screen displays supported metadata',
      (tester) async {
    await tester.pumpWidget(_wrap(const AboutScreen()));
    expect(find.text(AppInfo.appName), findsOneWidget);
    expect(find.text(AppInfo.tagline), findsOneWidget);
    expect(find.text(AppInfo.versionLabel), findsOneWidget);
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('Terms of use'), findsOneWidget);
    expect(find.textContaining(LegalCopy.medicalDisclaimer.substring(0, 40)),
        findsOneWidget);
    expect(aboutSrc.toLowerCase().contains('tga'), isFalse);
    expect(aboutSrc.toLowerCase().contains('accredited'), isFalse);
    expect(aboutSrc.toLowerCase().contains('endorsed'), isFalse);
    expect(aboutSrc.toLowerCase().contains('pbs'), isFalse);
  });

  testWidgets('SET-006-FL-03 Help covers current features only', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_wrap(const HelpScreen()));
    expect(find.text('Help'), findsOneWidget);
    expect(find.text('Prescriptions'), findsOneWidget);
    expect(find.text('Medicines'), findsOneWidget);
    expect(find.text('Records'), findsOneWidget);
    expect(find.text('Reminders'), findsOneWidget);
    expect(find.text('Health metrics'), findsOneWidget);
    expect(find.text('Emergency'), findsOneWidget);
    expect(find.text(LegalCopy.emergencyBanner), findsOneWidget);
    expect(find.byType(ClinicalSafetyBanner), findsOneWidget);
    final helpBody = HelpScreen.sections
        .map((s) => '${s.$1} ${s.$2}')
        .join(' ')
        .toLowerCase();
    expect(helpBody.contains('eprescription'), isFalse);
    expect(helpBody.contains('inbox'), isFalse);
    expect(helpBody.contains('biometric'), isFalse);
    expect(helpBody.contains('tga approved'), isFalse);
    expect(helpBody.contains('you have'), isFalse);
  });

  testWidgets('SET-006-FL-04 Feedback uses mailto and does not claim delivery',
      (tester) async {
    Uri? launched;
    await tester.pumpWidget(
      _wrap(
        FeedbackScreen(
          launchEmail: (uri) async {
            launched = uri;
            return true;
          },
        ),
      ),
    );
    expect(
      find.textContaining('HealthNest does not store feedback on the server'),
      findsOneWidget,
    );
    await tester.enterText(
        find.byKey(const Key('feedback-message')), 'Please improve reminders');
    await tester.tap(find.byKey(const Key('feedback-category-Bug')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('feedback-open-email')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(launched, isNotNull);
    expect(launched!.scheme, 'mailto');
    expect(launched!.path, AppInfo.supportEmail);
    expect(launched.toString(), contains('Bug'));
    expect(find.textContaining('Feedback is sent only if you send the email'),
        findsOneWidget);
    expect(find.text('Feedback sent'), findsNothing);
    expect(feedbackSrc.contains("post('/errors/report'"), isFalse);
    expect(feedbackSrc.contains('ApiClient'), isFalse);
  });

  testWidgets('SET-006-FL-05 duplicate open is prevented while launching',
      (tester) async {
    var launches = 0;
    final gate = Completer<bool>();
    await tester.pumpWidget(
      _wrap(
        FeedbackScreen(
          launchEmail: (_) {
            launches += 1;
            return gate.future;
          },
        ),
      ),
    );
    await tester.enterText(
        find.byKey(const Key('feedback-message')), 'Hello');
    await tester.tap(find.byKey(const Key('feedback-open-email')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('feedback-open-email')));
    await tester.pump();
    expect(launches, 1);
    gate.complete(true);
    await tester.pump();
  });

  testWidgets('SET-006-FL-06 launch failure is handled without claiming send',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        FeedbackScreen(launchEmail: (_) async => false),
      ),
    );
    await tester.enterText(
        find.byKey(const Key('feedback-message')), 'Broken mailer');
    await tester.tap(find.byKey(const Key('feedback-open-email')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('Feedback was not sent'), findsOneWidget);
    expect(find.text('Feedback sent'), findsNothing);
  });

  test('SET-006-FL-07 no sensitive payload logging', () {
    expect(feedbackSrc.contains('debugPrint'), isFalse);
    expect(feedbackSrc.contains('print('), isFalse);
    expect(feedbackSrc.contains('DebugLogger'), isFalse);
    expect(feedbackSrc.contains('ErrorReporter'), isFalse);
    expect(infoSrc.contains('debugPrint'), isFalse);
    expect(aboutSrc.contains('debugPrint'), isFalse);
    expect(helpSrc.contains('debugPrint'), isFalse);
    expect(FeedbackScreen.buildMailto(
      category: 'General',
      message: 'hello',
    ).toString(), contains(AppInfo.supportEmail));
  });
}
