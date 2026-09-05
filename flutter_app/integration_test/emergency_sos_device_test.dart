/// Sprint 2 SOS Device QA — interactive Emergency screen on emulator-5554.
///
/// Safety rules:
/// - Never taps Call on 000 / emergency services.
/// - Does not invoke adb from the device process (permission denied).
/// - Does not send SMS/FCM to real contacts.
///
/// Host prep:
///   1. Mint JWT → dart-defines
///   2. adb pm grant LOCATION
///   3. Optional host dialer probe: am start -a DIAL -d tel:5550100 then BACK
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vitapulse_ai/core/utils/auth_storage.dart';
import 'package:vitapulse_ai/features/emergency/presentation/emergency_screen.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

Future<void> _loadQaAuth() async {
  const token = String.fromEnvironment('SOS_QA_ACCESS_TOKEN');
  const userIdRaw = String.fromEnvironment('SOS_QA_USER_ID');
  const userName =
      String.fromEnvironment('SOS_QA_USER_NAME', defaultValue: 'QA User');
  if (token.isNotEmpty && userIdRaw.isNotEmpty) {
    await AuthStorage.saveTokens(
      accessToken: token,
      refreshToken: 'sos-qa-refresh-unused',
      userId: int.parse(userIdRaw),
      name: userName,
    );
    return;
  }
  fail(
    'Pass --dart-define=SOS_QA_ACCESS_TOKEN=... '
    '--dart-define=SOS_QA_USER_ID=... '
    '--dart-define=SOS_QA_USER_NAME=...',
  );
}

Widget _wrap(Widget child) {
  final settings = const AppThemeSettings();
  return MaterialApp(
    theme: AppThemeBuilder.light(settings),
    home: child,
  );
}

/// SOS header uses a repeating AnimationController — avoid pumpAndSettle.
Future<void> _pumpUi(WidgetTester tester,
    [Duration d = const Duration(seconds: 2)]) async {
  await tester.pump();
  await tester.pump(d);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SOS device QA matrix SOS-01..06', (tester) async {
    await _loadQaAuth();

    // ── SOS-01 / SOS-05 ────────────────────────────────────────────────
    await tester.pumpWidget(_wrap(const EmergencyScreen()));
    await _pumpUi(tester, const Duration(seconds: 4));

    expect(find.text('Emergency'), findsOneWidget);
    expect(
      find.textContaining('Medical emergency disclaimer'),
      findsOneWidget,
    );
    expect(find.textContaining('call 000'), findsWidgets);
    expect(find.textContaining('NOT auto-notified'), findsOneWidget);
    expect(find.text('000'), findsOneWidget);
    expect(find.text('13 11 26'), findsOneWidget);
    expect(find.text('1800 022 222'), findsOneWidget);
    // Dial-first Call affordances present (do not tap 000)
    expect(find.widgetWithText(FilledButton, 'Call'), findsWidgets);
    tester.printToConsole('SOS-01_SCREEN_OPEN=PASS');
    tester.printToConsole('SOS-05_DISCLAIMER=PASS');
    tester.printToConsole(
        'SOS-02_DIAL_FIRST_UI=PASS (Call buttons visible; 000 not auto-invoked)');

    final hasSeeded = find.text('SOS QA Contact').evaluate().isNotEmpty;
    tester.printToConsole('SOS-03_SEEDED=$hasSeeded');

    // ── SOS-03 add if needed ───────────────────────────────────────────
    if (!hasSeeded) {
      await tester.ensureVisible(find.text('Add'));
      await tester.tap(find.text('Add').first);
      await _pumpUi(tester);
      final fields = find.byType(TextFormField);
      expect(fields, findsNWidgets(3));
      await tester.enterText(fields.at(0), 'SOS QA Contact');
      await tester.enterText(fields.at(1), '5550100');
      await tester.enterText(fields.at(2), 'Friend');
      // Dialog confirm label is "Add" (not Save)
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await _pumpUi(tester, const Duration(seconds: 4));
      expect(find.text('SOS QA Contact'), findsOneWidget);
      tester.printToConsole('SOS-03_ADD=PASS');
    } else {
      tester.printToConsole('SOS-03_ADD=SKIP_ALREADY_PRESENT');
    }

    // Scroll contact into view (below fold on short emulator viewports)
    await tester.scrollUntilVisible(
      find.text('SOS QA Contact'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await _pumpUi(tester);
    expect(find.text('SOS QA Contact'), findsOneWidget);
    expect(find.text('5550100'), findsOneWidget);
    expect(find.byTooltip('Remove contact'), findsOneWidget);
    tester.printToConsole('SOS-03_CONTACT_VISIBLE=PASS');

    // ── SOS-03 delete ──────────────────────────────────────────────────
    await tester.ensureVisible(find.byTooltip('Remove contact'));
    await tester.tap(find.byTooltip('Remove contact'));
    await _pumpUi(tester);
    expect(find.text('Remove contact?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await _pumpUi(tester);
    expect(find.text('SOS QA Contact'), findsOneWidget);
    tester.printToConsole('SOS-03_DELETE_CANCEL=PASS');

    await tester.tap(find.byTooltip('Remove contact'));
    await _pumpUi(tester);
    await tester.tap(find.text('Remove'));
    await _pumpUi(tester, const Duration(seconds: 4));
    expect(find.text('SOS QA Contact'), findsNothing);
    expect(find.textContaining('No emergency contacts'), findsOneWidget);
    expect(
      find.textContaining('Add contacts you can dial manually'),
      findsOneWidget,
    );
    tester.printToConsole('SOS-03_DELETE=PASS');
    tester.printToConsole('SOS-04_EMPTY_STATE=PASS');

    // ── SOS timed hold honesty (empty contacts) ────────────────────────
    // Scroll back to SOS button
    await tester.scrollUntilVisible(
      find.bySemanticsLabel(RegExp(r'Emergency SOS button')),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await _pumpUi(tester);
    final sosBtn = find.bySemanticsLabel(RegExp(r'Emergency SOS button'));
    expect(sosBtn, findsOneWidget);
    // True 3s hold (not Flutter default longPress ~500ms)
    final center = tester.getCenter(sosBtn);
    final hold = await tester.startGesture(center);
    await Future<void>.delayed(const Duration(seconds: 3, milliseconds: 200));
    await tester.pump();
    await hold.up();
    await _pumpUi(tester, const Duration(seconds: 12));

    final recorded = find.text('SOS recorded');
    if (recorded.evaluate().isNotEmpty) {
      final dialogText = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Text),
      );
      final texts = dialogText.evaluate().map((e) {
        final w = e.widget;
        return w is Text ? (w.data ?? '') : '';
      }).join(' ');
      expect(
          texts.toLowerCase().contains('notified with your location'), isFalse);
      expect(
        texts.contains('NOT automatically') ||
            texts.contains('No emergency contacts') ||
            texts.contains('Call 000'),
        isTrue,
      );
      await tester.tap(find.text('OK'));
      await _pumpUi(tester);
      tester.printToConsole('SOS-04_SOS_ACTION_EMPTY_HONESTY=PASS');
    } else {
      expect(find.textContaining('will be shared with contacts'), findsNothing);
      tester.printToConsole(
          'SOS-04_SOS_ACTION=HANDLED_WITHOUT_FALSE_SHARE_CLAIM');
    }

    expect(find.textContaining('will be shared with contacts'), findsNothing);

    // ── SOS-06 back navigation ─────────────────────────────────────────
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.light(const AppThemeSettings()),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const EmergencyScreen()),
                  );
                },
                child: const Text('Open Emergency'),
              ),
            ),
          ),
        ),
      ),
    );
    await _pumpUi(tester);
    await tester.tap(find.text('Open Emergency'));
    await _pumpUi(tester, const Duration(seconds: 3));
    expect(find.text('Emergency'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await _pumpUi(tester);
    expect(find.text('Open Emergency'), findsOneWidget);
    expect(find.text('Emergency'), findsNothing);
    tester.printToConsole('SOS-06_BACK_NAV=PASS');

    tester.printToConsole('SOS_DEVICE_QA_MATRIX=COMPLETE');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
