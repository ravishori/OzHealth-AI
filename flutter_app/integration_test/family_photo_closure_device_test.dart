/// Sprint 3 Slice 3 — HN-FAMILY-012 device QA (orphaned photo removed).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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
    refreshToken: 'family-photo-qa-unused',
    userId: int.parse(userIdRaw),
    name: userName,
  );
}

Future<void> _pumpUi(WidgetTester tester,
    [Duration d = const Duration(seconds: 2)]) async {
  await tester.pump();
  await tester.pump(d);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FAMILY-PHOTO device QA matrix UI-01..05', (tester) async {
    await _loadQaAuth();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.light(const AppThemeSettings()),
        home: const FamilyScreen(),
      ),
    );
    await _pumpUi(tester, const Duration(seconds: 4));
    expect(find.text('Family Members'), findsOneWidget);
    tester.printToConsole('FAMILY-PHOTO-UI-01_OPEN=PASS');

    // Members list or empty state — either is fine
    final hasList = find.byType(ListView).evaluate().isNotEmpty ||
        find.byType(ListTile).evaluate().isNotEmpty ||
        find.textContaining('No family').evaluate().isNotEmpty ||
        find.textContaining('Add').evaluate().isNotEmpty ||
        find.byType(CircleAvatar).evaluate().isNotEmpty;
    expect(hasList || find.byType(CircularProgressIndicator).evaluate().isEmpty,
        isTrue);
    tester.printToConsole('FAMILY-PHOTO-UI-02_DISPLAY=PASS');

    expect(find.byType(CircleAvatar), findsWidgets);
    tester.printToConsole('FAMILY-PHOTO-UI-03_INITIALS_AVATAR=PASS');

    expect(find.textContaining('Upload photo'), findsNothing);
    expect(find.textContaining('Change photo'), findsNothing);
    expect(find.byIcon(Icons.camera_alt), findsNothing);
    expect(find.byIcon(Icons.photo_library), findsNothing);
    tester.printToConsole('FAMILY-PHOTO-UI-04_NO_PHOTO_PICKER=PASS');

    // Edit screen still opens and shows core fields (no photo controls)
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.light(const AppThemeSettings()),
        home: const EditFamilyMemberScreen(
          memberId: 1,
          initialMember: {
            'id': 1,
            'name': 'Photo QA Member',
            'relationship': 'Child',
            'medical_conditions': <String>[],
            'allergies': <String>[],
          },
        ),
      ),
    );
    await _pumpUi(tester);
    expect(find.text('Edit Family Member'), findsOneWidget);
    expect(find.text('Photo QA Member'), findsOneWidget);
    expect(find.text('Save Changes'), findsOneWidget);
    expect(find.textContaining('Upload photo'), findsNothing);
    expect(find.byIcon(Icons.camera_alt), findsNothing);
    tester.printToConsole('FAMILY-PHOTO-UI-05_EDIT_STILL_WORKS=PASS');
    tester.printToConsole('FAMILY_PHOTO_DEVICE_QA_MATRIX=COMPLETE');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
