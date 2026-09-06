import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/features/family/data/family_medications.dart';
import 'package:vitapulse_ai/features/family/presentation/family_medications_screen.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppThemeBuilder.light(const AppThemeSettings()),
    home: child,
  );
}

final List<Map<String, dynamic>> _ownedMembers = [
  {
    'id': 901,
    'name': 'Alex Rivera',
    'relationship': 'Child',
  },
  {
    'id': 902,
    'name': 'Sam Rivera',
    'relationship': 'Spouse',
  },
];

final List<Map<String, dynamic>> _ownerReminders = [
  {
    'id': 701,
    'user_id': 3,
    'family_member_id': 901,
    'medicine_name': 'Metformin',
    'dosage': '500mg',
    'frequency': 'daily',
    'times': ['08:00'],
    'instructions': 'With food',
    'refill_date': '2026-10-01',
    'is_active': true,
  },
  {
    'id': 702,
    'user_id': 3,
    'family_member_id': null,
    'medicine_name': 'PersonalAspirin',
    'dosage': '100mg',
    'frequency': 'daily',
    'times': ['21:00'],
    'is_active': true,
  },
  {
    'id': 703,
    'user_id': 3,
    'family_member_id': 999,
    'medicine_name': 'UnlinkedMed',
    'dosage': '10mg',
    'frequency': 'weekly',
    'is_active': true,
  },
];

void main() {
  final familySrc =
      File('lib/features/family/presentation/family_screen.dart')
          .readAsStringSync();
  final homeSrc =
      File('lib/features/home/presentation/home_screen.dart').readAsStringSync();
  final drawerSrc =
      File('lib/features/home/presentation/app_drawer.dart').readAsStringSync();
  final routerSrc =
      File('lib/core/router/app_router.dart').readAsStringSync();
  final hubSrc = File(
          'lib/features/family/presentation/family_medications_screen.dart')
      .readAsStringSync();
  final groupSrc =
      File('lib/features/family/data/family_medications.dart').readAsStringSync();
  final remindersListSrc =
      File('lib/features/reminders/presentation/reminders_screen.dart')
          .readAsStringSync();
  final familyApiSrc =
      File('lib/features/family/data/family_api.dart').readAsStringSync();
  final reminderApiSrc =
      File('lib/features/reminders/data/reminder_api.dart').readAsStringSync();

  test('FAMILY-MEDS-FL-01 Family Medications entry/navigation works', () {
    expect(routerSrc.contains("path: 'family/medications'"), isTrue);
    expect(routerSrc.contains('FamilyMedicationsScreen'), isTrue);
    expect(familySrc.contains("context.push('/home/family/medications')"),
        isTrue);
    expect(familySrc.contains("tooltip: 'Family medications'"), isTrue);
    expect(familySrc.contains("label: const Text('Medications')"), isTrue);
    expect(homeSrc.contains("title: 'Family Medications'"), isTrue);
    expect(homeSrc.contains("context.push('/home/family/medications')"), isTrue);
    expect(drawerSrc.contains("label: 'Family Medications'"), isTrue);
    expect(drawerSrc.contains("_nav('/home/family/medications')"), isTrue);
  });

  test('FAMILY-MEDS-FL-02 owned family members are displayed from grouping',
      () {
    final groups = groupFamilyMedications(
      members: _ownedMembers,
      reminders: _ownerReminders,
    );
    expect(groups.map((g) => g.name).toList(), ['Alex Rivera', 'Sam Rivera']);
    expect(groups[0].reminders.single['medicine_name'], 'Metformin');
    expect(groups[1].reminders, isEmpty);
  });

  testWidgets('FAMILY-MEDS-FL-02 owned members render in the hub',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        FamilyMedicationsScreen(
          loadMembers: () async => _ownedMembers,
          loadReminders: () async => _ownerReminders,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Alex Rivera'), findsOneWidget);
    expect(find.text('Sam Rivera'), findsOneWidget);
    expect(find.text('Child'), findsOneWidget);
    expect(find.text('Spouse'), findsOneWidget);
  });

  test('FAMILY-MEDS-FL-03 medication data comes from owner-scoped reminders',
      () {
    expect(hubSrc.contains('FamilyApi.getMembers()'), isTrue);
    expect(hubSrc.contains('ReminderApi.getReminders()'), isTrue);
    expect(familyApiSrc.contains("ApiClient.get('/family/')"), isTrue);
    expect(reminderApiSrc.contains("ApiClient.get('/reminders/')"), isTrue);
    expect(groupSrc.contains('Personal reminders'), isTrue);
    expect(groupSrc.contains("member['id']"), isTrue);
    expect(groupSrc.contains("reminder['family_member_id']"), isTrue);

    final groups = groupFamilyMedications(
      members: _ownedMembers,
      reminders: _ownerReminders,
    );
    final names = groups
        .expand((g) => g.reminders)
        .map((r) => r['medicine_name'])
        .toSet();
    expect(names, {'Metformin'});
    expect(names.contains('PersonalAspirin'), isFalse);
    expect(names.contains('UnlinkedMed'), isFalse);
  });

  testWidgets('FAMILY-MEDS-FL-03 hub shows reminder fields from the source',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        FamilyMedicationsScreen(
          loadMembers: () async => _ownedMembers,
          loadReminders: () async => _ownerReminders,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Metformin'), findsOneWidget);
    expect(find.textContaining('500mg'), findsOneWidget);
    expect(find.textContaining('Daily'), findsOneWidget);
    expect(find.textContaining('08:00'), findsOneWidget);
    expect(find.text('With food'), findsOneWidget);
    expect(find.text('Refill 2026-10-01'), findsOneWidget);
    expect(find.text('PersonalAspirin'), findsNothing);
    expect(find.text('UnlinkedMed'), findsNothing);
  });

  testWidgets('FAMILY-MEDS-FL-04 empty family medication state is truthful',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        FamilyMedicationsScreen(
          loadMembers: () async => _ownedMembers,
          loadReminders: () async => const [],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.text('No medications are currently linked to this family member.'),
      findsNWidgets(2),
    );
    expect(find.text('Metformin'), findsNothing);
    expect(find.text('Sample medication'), findsNothing);
  });

  testWidgets('FAMILY-MEDS-FL-04 no-members empty state', (tester) async {
    await tester.pumpWidget(
      _wrap(
        FamilyMedicationsScreen(
          loadMembers: () async => const [],
          loadReminders: () async => _ownerReminders,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('family-meds-no-members')), findsOneWidget);
    expect(find.text('No family members yet'), findsOneWidget);
    expect(find.text('Metformin'), findsNothing);
  });

  testWidgets('FAMILY-MEDS-FL-05 loading state works', (tester) async {
    final gate = Completer<List<Map<String, dynamic>>>();
    await tester.pumpWidget(
      _wrap(
        FamilyMedicationsScreen(
          loadMembers: () => gate.future,
          loadReminders: () async => const [],
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('family-meds-loading')), findsOneWidget);
    expect(find.text('Family Medications'), findsOneWidget);
    gate.complete(const []);
    await tester.pump();
  });

  testWidgets('FAMILY-MEDS-FL-06 error/retry works', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _wrap(
        FamilyMedicationsScreen(
          loadMembers: () async {
            calls += 1;
            if (calls == 1) throw Exception('unavailable');
            return const [];
          },
          loadReminders: () async => const [],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('family-meds-error')), findsOneWidget);
    expect(find.byKey(const Key('family-meds-retry')), findsOneWidget);
    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('family-meds-retry')));
    await tester.pump();
    await tester.pump();
    expect(calls, 2);
    expect(find.byKey(const Key('family-meds-no-members')), findsOneWidget);
  });

  testWidgets('FAMILY-MEDS-FL-07 raw IDs are not displayed', (tester) async {
    await tester.pumpWidget(
      _wrap(
        FamilyMedicationsScreen(
          loadMembers: () async => _ownedMembers,
          loadReminders: () async => _ownerReminders,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('901'), findsNothing);
    expect(find.text('902'), findsNothing);
    expect(find.text('701'), findsNothing);
    expect(find.text('999'), findsNothing);
    expect(find.text('3'), findsNothing);
    expect(find.textContaining('family_member_id'), findsNothing);
    expect(find.textContaining('user_id'), findsNothing);
  });

  testWidgets('FAMILY-MEDS-FL-08 existing reminder edit flow is reused',
      (tester) async {
    Map<String, dynamic>? captured;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => FamilyMedicationsScreen(
            loadMembers: () async => _ownedMembers,
            loadReminders: () async => _ownerReminders,
          ),
        ),
        GoRoute(
          path: '/home/reminders/edit',
          builder: (_, state) {
            captured = state.extra is Map
                ? Map<String, dynamic>.from(state.extra as Map)
                : null;
            return const Scaffold(body: Text('Existing reminder editor'));
          },
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppThemeBuilder.light(const AppThemeSettings()),
        routerConfig: router,
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('family-meds-reminder-Metformin')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Existing reminder editor'), findsOneWidget);
    expect(captured, isNotNull);
    expect(captured!['medicine_name'], 'Metformin');
    expect(hubSrc.contains("context.push(\n      '/home/reminders/edit'"),
        isTrue);
    expect(routerSrc.contains("path: 'reminders/edit'"), isTrue);
    expect(routerSrc.contains('AddReminderScreen'), isTrue);
    expect(routerSrc.contains('initialReminder'), isTrue);
  });

  test('FAMILY-MEDS-FL-09 existing reminder delete is not duplicated on hub',
      () {
    expect(hubSrc.contains('deleteReminder'), isFalse);
    expect(hubSrc.contains('ApiClient.delete'), isFalse);
    expect(hubSrc.contains('Dismissible'), isFalse);
    expect(hubSrc.contains('_deleteReminder'), isFalse);
    expect(remindersListSrc.contains('_deleteReminder'), isTrue);
    expect(remindersListSrc.contains("ApiClient.delete('/reminders/\$"),
        isTrue);
  });

  test('FAMILY-MEDS-FL-10 no medication/clinical payload logging', () {
    expect(hubSrc.contains('debugPrint'), isFalse);
    expect(hubSrc.contains('print('), isFalse);
    expect(hubSrc.contains('DebugLogger'), isFalse);
    expect(groupSrc.contains('debugPrint'), isFalse);
    expect(groupSrc.contains('print('), isFalse);
    expect(hubSrc.contains('diagnos'), isFalse);
    expect(hubSrc.contains('treatment advice'), isFalse);
    expect(hubSrc.contains('FirebaseMessaging'), isFalse);
    expect(hubSrc.contains('FCM'), isFalse);
  });
}
