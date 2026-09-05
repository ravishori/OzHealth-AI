/// Sprint 3 Slice 1 — HN-FAMILY-002 device QA on emulator-5554.
///
///   flutter test integration_test/family_edit_device_test.dart -d emulator-5554 \
///     --dart-define=SOS_QA_ACCESS_TOKEN=... --dart-define=SOS_QA_USER_ID=2 \
///     --dart-define=SOS_QA_USER_NAME=QA
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/utils/auth_storage.dart';
import 'package:vitapulse_ai/features/family/presentation/edit_family_screen.dart';
import 'package:vitapulse_ai/features/family/presentation/family_screen.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

Future<void> _loadQaAuth() async {
  const token = String.fromEnvironment('SOS_QA_ACCESS_TOKEN');
  const userIdRaw = String.fromEnvironment('SOS_QA_USER_ID');
  const userName =
      String.fromEnvironment('SOS_QA_USER_NAME', defaultValue: 'QA User');
  if (token.isEmpty || userIdRaw.isEmpty) {
    fail('Pass SOS_QA_ACCESS_TOKEN and SOS_QA_USER_ID dart-defines');
  }
  await AuthStorage.saveTokens(
    accessToken: token,
    refreshToken: 'family-qa-refresh-unused',
    userId: int.parse(userIdRaw),
    name: userName,
  );
}

Future<void> _pumpUi(WidgetTester tester,
    [Duration d = const Duration(seconds: 2)]) async {
  await tester.pump();
  await tester.pump(d);
}

Widget _app(Widget home) {
  return MaterialApp(
    theme: AppThemeBuilder.light(const AppThemeSettings()),
    home: home,
  );
}

/// Host route so Cancel/Back can pop without emptying the navigator.
Widget _stackHost(Widget editScreen) {
  return MaterialApp(
    theme: AppThemeBuilder.light(const AppThemeSettings()),
    home: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Host')),
        body: Center(
          child: FilledButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<bool>(builder: (_) => editScreen),
              );
            },
            child: const Text('Open Edit'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FAMILY device QA matrix FAMILY-UI-01..10', (tester) async {
    await _loadQaAuth();

    final stamp = DateTime.now().millisecondsSinceEpoch % 100000;
    final create = await ApiClient.post('/family/', data: {
      'name': 'Family QA $stamp',
      'relationship': 'Child',
      'age': 8,
      'gender': 'Male',
      'blood_group': 'O+',
      'medical_conditions': ['None'],
      'allergies': [],
    });
    final member = Map<String, dynamic>.from(create.data as Map);
    final id = member['id'] as int;
    tester.printToConsole('FAMILY_UI_SEEDED_ID=$id');

    // FAMILY-UI-01 list
    await tester.pumpWidget(_app(const FamilyScreen()));
    await _pumpUi(tester, const Duration(seconds: 4));
    expect(find.text('Family Members'), findsOneWidget);
    expect(find.text('Family QA $stamp'), findsOneWidget);
    tester.printToConsole('FAMILY-UI-01_LIST=PASS');

    // FAMILY-UI-02/03 open edit with populated values
    await tester.pumpWidget(
      _app(
        EditFamilyMemberScreen(
          memberId: id,
          initialMember: member,
        ),
      ),
    );
    await _pumpUi(tester);
    expect(find.text('Edit Family Member'), findsOneWidget);
    expect(find.text('Family QA $stamp'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    tester.printToConsole('FAMILY-UI-02_EDIT_OPEN=PASS');
    tester.printToConsole('FAMILY-UI-03_POPULATED=PASS');

    // FAMILY-UI-09 invalid age
    await tester.enterText(find.byType(TextFormField).at(1), '999');
    await tester.tap(find.text('Save Changes'));
    await _pumpUi(tester);
    expect(find.text('Enter a valid age'), findsOneWidget);
    tester.printToConsole('FAMILY-UI-09_INVALID=PASS');

    // FAMILY-UI-04/05 change + save (verify via API — honest success)
    await tester.enterText(find.byType(TextFormField).at(1), '9');
    final newName = 'Family QA Edited $stamp';
    await tester.enterText(find.byType(TextFormField).first, newName);
    await tester.tap(find.text('Save Changes'));
    await _pumpUi(tester, const Duration(seconds: 4));
    final get = await ApiClient.get('/family/$id');
    final refreshed = Map<String, dynamic>.from(get.data as Map);
    expect(refreshed['name'], newName);
    expect(refreshed['age'], 9);
    tester.printToConsole('FAMILY-UI-04_CHANGE=PASS');
    tester.printToConsole('FAMILY-UI-05_SAVE=PASS');
    tester.printToConsole('FAMILY-UI-06_PERSISTED=PASS');

    // FAMILY-UI-07 reopen
    await tester.pumpWidget(
      _stackHost(
        EditFamilyMemberScreen(
          memberId: id,
          initialMember: refreshed,
        ),
      ),
    );
    await _pumpUi(tester);
    await tester.tap(find.text('Open Edit'));
    await _pumpUi(tester);
    expect(find.text(newName), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    tester.printToConsole('FAMILY-UI-07_REOPEN=PASS');

    // FAMILY-UI-08 cancel does not save further edits
    await tester.enterText(find.byType(TextFormField).first, 'SHOULD NOT SAVE');
    await tester.tap(find.text('Cancel'));
    await _pumpUi(tester);
    expect(find.text('Open Edit'), findsOneWidget);
    final afterCancel = await ApiClient.get('/family/$id');
    expect(afterCancel.data['name'], newName);
    tester.printToConsole('FAMILY-UI-08_CANCEL=PASS');

    // FAMILY-UI-10 API/error honesty (missing member)
    await tester.pumpWidget(
      _app(const EditFamilyMemberScreen(memberId: 999999001)),
    );
    await _pumpUi(tester, const Duration(seconds: 5));
    // Prefer Retry CTA; also accept Back when error UI rendered.
    final hasRetry = find.text('Retry').evaluate().isNotEmpty;
    final hasBack = find.text('Back').evaluate().isNotEmpty;
    expect(hasRetry || hasBack, isTrue,
        reason: 'Expected load-error UI for missing family member');
    expect(find.text('Family member updated'), findsNothing);
    tester.printToConsole('FAMILY-UI-10_API_ERROR=PASS');

    await ApiClient.delete('/family/$id');
    tester.printToConsole('FAMILY_DEVICE_QA_MATRIX=COMPLETE');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
