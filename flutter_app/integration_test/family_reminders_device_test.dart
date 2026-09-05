/// Sprint 3 Slice 6 — HN-FAMILY-009 device QA.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/utils/auth_storage.dart';
import 'package:vitapulse_ai/features/reminders/presentation/add_reminder_screen.dart';
import 'package:vitapulse_ai/features/reminders/presentation/reminders_screen.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

Future<void> _loadQaAuth() async {
  const token = String.fromEnvironment('SOS_QA_ACCESS_TOKEN');
  const refresh = String.fromEnvironment('SOS_QA_REFRESH_TOKEN');
  const userIdRaw = String.fromEnvironment('SOS_QA_USER_ID');
  const userName =
      String.fromEnvironment('SOS_QA_USER_NAME', defaultValue: 'QA User');
  if (token.isEmpty || userIdRaw.isEmpty) {
    fail('Pass SOS_QA_ACCESS_TOKEN and SOS_QA_USER_ID dart-defines');
  }
  await AuthStorage.saveTokens(
    accessToken: token,
    refreshToken: refresh.isEmpty ? 'unused-refresh' : refresh,
    userId: int.parse(userIdRaw),
    name: userName,
  );
}

Future<void> _pumpUi(WidgetTester tester,
    [Duration d = const Duration(seconds: 2)]) async {
  await tester.pump();
  await Future<void>.delayed(d);
  await tester.pump();
}

Widget _app(Widget home) {
  return MaterialApp(
    theme: AppThemeBuilder.light(const AppThemeSettings()),
    home: home,
  );
}

Future<void> _waitForText(
  WidgetTester tester,
  String text, {
  int attempts = 40,
}) async {
  for (var i = 0; i < attempts; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await tester.pump();
    if (find.text(text).evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for text: $text');
}

Future<void> _ensureVisibleText(WidgetTester tester, String text) async {
  final list = find.byType(ListView);
  if (list.evaluate().isEmpty) return;
  for (var i = 0; i < 10; i++) {
    if (find.text(text).evaluate().isNotEmpty) return;
    await tester.drag(list, const Offset(0, -240));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await tester.pump();
  }
}

Future<void> _refreshReminders(WidgetTester tester) async {
  final refresh = find.byTooltip('Refresh');
  expect(refresh, findsOneWidget);
  await tester.tap(refresh);
  await tester.pump();
  await Future<void>.delayed(const Duration(seconds: 2));
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FAMILY-REM Android QA matrix 01..15', (tester) async {
    await _loadQaAuth();
    tester.printToConsole('FAMILY-REM-ANDROID-01_LAUNCH=PASS');

    final me = await ApiClient.get('/users/me');
    expect(me.statusCode, 200);
    tester.printToConsole('FAMILY-REM-ANDROID-02_AUTH=PASS');

    final fam = await ApiClient.get('/family/');
    expect(fam.statusCode, 200);
    var members = List<Map<String, dynamic>>.from(
      fam.data is List ? fam.data as List : [],
    );
    if (members.isEmpty) {
      final created = await ApiClient.post('/family/', data: {
        'name': 'QA Family Member',
        'relationship': 'Child',
        'age': 10,
      });
      expect(created.statusCode, anyOf(200, 201));
      members = [Map<String, dynamic>.from(created.data as Map)];
    }
    final memberId = members.first['id'] as int;
    final memberName = members.first['name']?.toString() ?? 'Member';

    await tester.pumpWidget(_app(const RemindersScreen()));
    await _waitForText(tester, 'Medication Reminders');
    await _pumpUi(tester, const Duration(seconds: 2));
    tester.printToConsole('FAMILY-REM-ANDROID-03_REMINDERS=PASS');

    final stamp = DateTime.now().millisecondsSinceEpoch % 100000;
    final personalName = 'QA Personal Med $stamp';
    final familyMedName = 'QA Family Med $stamp';

    final personal = await ApiClient.post('/reminders/', data: {
      'medicine_name': personalName,
      'frequency': 'daily',
      'times': ['07:30'],
      'dosage': '1 tablet',
    });
    expect(personal.statusCode, 200);
    final personalBody = Map<String, dynamic>.from(personal.data as Map);
    expect(personalBody['family_member_id'], isNull);
    expect(personalBody['family_member_name'], isNull);
    tester.printToConsole('FAMILY-REM-ANDROID-04_PERSONAL=PASS');

    final linked = await ApiClient.post('/reminders/', data: {
      'medicine_name': familyMedName,
      'frequency': 'daily',
      'times': ['08:00'],
      'dosage': '1 tablet',
      'family_member_id': memberId,
    });
    expect(linked.statusCode, 200);
    final linkedBody = Map<String, dynamic>.from(linked.data as Map);
    expect(linkedBody['family_member_id'], memberId);
    expect(linkedBody['family_member_name'], memberName);
    final linkedId = linkedBody['id'] as int;
    tester.printToConsole('FAMILY-REM-ANDROID-05_FAMILY_LINKED=PASS');

    await _refreshReminders(tester);
    await _waitForText(tester, familyMedName);
    await _ensureVisibleText(tester, familyMedName);
    expect(find.textContaining('For $memberName'), findsWidgets);
    await _ensureVisibleText(tester, personalName);
    expect(find.text(personalName), findsWidgets);
    expect(find.text('Personal'), findsWidgets);
    tester.printToConsole('FAMILY-REM-ANDROID-06_LIST_NAMES=PASS');

    final detail = await ApiClient.get('/reminders/$linkedId');
    expect(detail.statusCode, 200);
    final detailBody = Map<String, dynamic>.from(detail.data as Map);
    expect(detailBody['family_member_name'], memberName);
    tester.printToConsole('FAMILY-REM-ANDROID-07_DETAIL=PASS');

    await tester.pumpWidget(
      _app(AddReminderScreen(initialReminder: detailBody)),
    );
    await _waitForText(tester, 'Edit Reminder');
    expect(find.text(familyMedName), findsOneWidget);
    tester.printToConsole('FAMILY-REM-ANDROID-08_EDIT_LOAD=PASS');

    final updated = await ApiClient.put('/reminders/$linkedId', data: {
      'times': ['09:15'],
      'frequency': 'daily',
      'family_member_id': memberId,
    });
    expect(updated.statusCode, 200);
    tester.printToConsole('FAMILY-REM-ANDROID-09_RESCHEDULE=PASS');

    final off = await ApiClient.put('/reminders/$linkedId', data: {
      'is_active': false,
    });
    expect(off.statusCode, 200);
    expect(Map<String, dynamic>.from(off.data as Map)['is_active'], isFalse);
    tester.printToConsole('FAMILY-REM-ANDROID-10_TOGGLE_OFF=PASS');

    final on = await ApiClient.put('/reminders/$linkedId', data: {
      'is_active': true,
    });
    expect(on.statusCode, 200);
    expect(Map<String, dynamic>.from(on.data as Map)['is_active'], isTrue);
    tester.printToConsole('FAMILY-REM-ANDROID-11_TOGGLE_ON=PASS');

    final del = await ApiClient.delete('/reminders/$linkedId');
    expect(del.statusCode, 200);
    tester.printToConsole('FAMILY-REM-ANDROID-12_DELETE=PASS');

    await tester.pumpWidget(_app(const RemindersScreen()));
    await _waitForText(tester, 'Medication Reminders');
    await _pumpUi(tester, const Duration(seconds: 3));
    await _refreshReminders(tester);
    await _waitForText(tester, personalName);
    expect(find.text(familyMedName), findsNothing);
    tester.printToConsole('FAMILY-REM-ANDROID-13_LIST_OK=PASS');

    final personalId = personalBody['id'] as int;
    final personalGet = await ApiClient.get('/reminders/$personalId');
    expect(personalGet.statusCode, 200);
    final pb = Map<String, dynamic>.from(personalGet.data as Map);
    expect(pb['family_member_name'], isNull);
    tester.printToConsole('FAMILY-REM-ANDROID-14_PERSONAL_OK=PASS');
    tester.printToConsole('FAMILY-REM-ANDROID-15_NO_CRASH=PASS');
    tester.printToConsole('FAMILY_REM_DEVICE_QA_MATRIX=COMPLETE');
  });
}
