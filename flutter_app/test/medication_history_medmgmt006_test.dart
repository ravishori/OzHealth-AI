import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/reminders/presentation/medication_history_screen.dart';
import 'package:vitapulse_ai/shared/widgets/empty_state.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppThemeBuilder.light(const AppThemeSettings()),
    home: child,
  );
}

Map<String, dynamic> _event({
  int id = 1,
  String status = 'taken',
  String name = 'Paracetamol',
  int scheduleId = 10,
}) {
  return {
    'id': id,
    'medication_schedule_id': scheduleId,
    'medicine_name': name,
    'dosage': '500mg',
    'status': status,
    'scheduled_for': '2026-09-08T08:00:00Z',
    'recorded_at': '2026-09-08T08:04:00Z',
    'created_at': '2026-09-08T08:04:00Z',
  };
}

void main() {
  final historySrc = File(
    'lib/features/reminders/presentation/medication_history_screen.dart',
  ).readAsStringSync();
  final apiSrc = File(
    'lib/features/reminders/data/medication_history_api.dart',
  ).readAsStringSync();
  final remindersSrc = File(
    'lib/features/reminders/presentation/reminders_screen.dart',
  ).readAsStringSync();
  final routerSrc = File('lib/core/router/app_router.dart').readAsStringSync();

  testWidgets('MEDHIST-F01 medication history screen opens', (tester) async {
    await tester.pumpWidget(
      _wrap(
        MedicationHistoryScreen(
          loadHistory: ({medicationScheduleId}) async => [],
          loadSummary: ({medicationScheduleId}) async => {
            'taken': 0,
            'skipped': 0,
            'missed': 0,
            'total': 0,
            'adherence_percent': null,
          },
          loadReminders: () async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('medication_history_screen')), findsOneWidget);
    expect(find.text('Medication History'), findsOneWidget);
  });

  testWidgets('MEDHIST-F02 taken action submits correctly', (tester) async {
    String? submitted;
    await tester.pumpWidget(
      _wrap(
        MedicationHistoryScreen(
          initialScheduleId: 10,
          loadHistory: ({medicationScheduleId}) async => [],
          loadSummary: ({medicationScheduleId}) async => {
            'taken': 0,
            'skipped': 0,
            'missed': 0,
            'total': 0,
          },
          loadReminders: () async => [
            {
              'id': 10,
              'medicine_name': 'Paracetamol',
              'times': ['08:00'],
            }
          ],
          recordDose: ({
            required medicationScheduleId,
            required status,
            required scheduledFor,
          }) async {
            submitted = status;
            return _event(status: status, scheduleId: medicationScheduleId);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dose_taken_button')));
    await tester.pumpAndSettle();
    expect(submitted, 'taken');
  });

  testWidgets('MEDHIST-F03 skipped action submits correctly', (tester) async {
    String? submitted;
    await tester.pumpWidget(
      _wrap(
        MedicationHistoryScreen(
          initialScheduleId: 10,
          loadHistory: ({medicationScheduleId}) async => [],
          loadSummary: ({medicationScheduleId}) async => {
            'taken': 0,
            'skipped': 0,
            'missed': 0,
            'total': 0,
          },
          loadReminders: () async => [
            {'id': 10, 'medicine_name': 'Paracetamol', 'times': ['08:00']}
          ],
          recordDose: ({
            required medicationScheduleId,
            required status,
            required scheduledFor,
          }) async {
            submitted = status;
            return _event(status: status);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dose_skipped_button')));
    await tester.pumpAndSettle();
    expect(submitted, 'skipped');
  });

  testWidgets('MEDHIST-F04 missed status renders correctly', (tester) async {
    await tester.pumpWidget(
      _wrap(
        MedicationHistoryScreen(
          loadHistory: ({medicationScheduleId}) async => [
            _event(id: 3, status: 'missed'),
          ],
          loadSummary: ({medicationScheduleId}) async => {
            'taken': 0,
            'skipped': 0,
            'missed': 1,
            'total': 1,
            'adherence_percent': 0.0,
          },
          loadReminders: () async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Missed'), findsWidgets);
    expect(find.byKey(const Key('dose_status_3_Missed')), findsOneWidget);
  });

  testWidgets('MEDHIST-F05 history timeline renders returned events',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        MedicationHistoryScreen(
          loadHistory: ({medicationScheduleId}) async => [
            _event(id: 1, status: 'taken', name: 'Paracetamol'),
            _event(id: 2, status: 'skipped', name: 'Ibuprofen'),
          ],
          loadSummary: ({medicationScheduleId}) async => {
            'taken': 1,
            'skipped': 1,
            'missed': 0,
            'total': 2,
            'adherence_percent': 50.0,
          },
          loadReminders: () async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('medication_history_timeline')), findsOneWidget);
    expect(find.text('Paracetamol'), findsOneWidget);
    expect(find.text('Ibuprofen'), findsOneWidget);
    expect(find.text('Taken'), findsWidgets);
    expect(find.text('Skipped'), findsWidgets);
  });

  testWidgets('MEDHIST-F06 empty state works', (tester) async {
    await tester.pumpWidget(
      _wrap(
        MedicationHistoryScreen(
          loadHistory: ({medicationScheduleId}) async => [],
          loadSummary: ({medicationScheduleId}) async => {
            'taken': 0,
            'skipped': 0,
            'missed': 0,
            'total': 0,
          },
          loadReminders: () async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('medication_history_empty')), findsOneWidget);
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('No dose history yet'), findsOneWidget);
  });

  testWidgets('MEDHIST-F07 API error is handled safely', (tester) async {
    await tester.pumpWidget(
      _wrap(
        MedicationHistoryScreen(
          loadHistory: ({medicationScheduleId}) async {
            throw Exception('network');
          },
          loadSummary: ({medicationScheduleId}) async => {},
          loadReminders: () async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('medication_history_error')), findsOneWidget);
    expect(find.textContaining('Failed to load'), findsOneWidget);
  });

  testWidgets('MEDHIST-F08 double submission is prevented', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _wrap(
        MedicationHistoryScreen(
          initialScheduleId: 10,
          loadHistory: ({medicationScheduleId}) async => [],
          loadSummary: ({medicationScheduleId}) async => {
            'taken': 0,
            'skipped': 0,
            'missed': 0,
            'total': 0,
          },
          loadReminders: () async => [
            {'id': 10, 'medicine_name': 'Paracetamol', 'times': ['08:00']}
          ],
          recordDose: ({
            required medicationScheduleId,
            required status,
            required scheduledFor,
          }) async {
            calls++;
            await Future<void>.delayed(const Duration(milliseconds: 300));
            return _event(status: status);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dose_taken_button')));
    await tester.pump(); // start submit
    await tester.tap(find.byKey(const Key('dose_taken_button')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('MEDHIST-F09 medication-specific filtering works', (tester) async {
    int? lastFilter;
    await tester.pumpWidget(
      _wrap(
        MedicationHistoryScreen(
          loadHistory: ({medicationScheduleId}) async {
            lastFilter = medicationScheduleId;
            if (medicationScheduleId == 10) {
              return [_event(id: 1, scheduleId: 10, name: 'Paracetamol')];
            }
            return [
              _event(id: 1, scheduleId: 10, name: 'Paracetamol'),
              _event(id: 2, scheduleId: 11, name: 'Ibuprofen'),
            ];
          },
          loadSummary: ({medicationScheduleId}) async => {
            'taken': 1,
            'skipped': 0,
            'missed': 0,
            'total': 1,
          },
          loadReminders: () async => [
            {'id': 10, 'medicine_name': 'Paracetamol', 'times': ['08:00']},
            {'id': 11, 'medicine_name': 'Ibuprofen', 'times': ['20:00']},
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ibuprofen'), findsWidgets);
    await tester.tap(find.byKey(const Key('medication_history_filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paracetamol').last);
    await tester.pumpAndSettle();
    expect(lastFilter, 10);
    expect(find.byKey(const Key('dose_taken_button')), findsOneWidget);
  });

  testWidgets('MEDHIST-F10 logout clears previous user history from UI',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        MedicationHistoryScreen(
          key: const Key('history_user_a'),
          loadHistory: ({medicationScheduleId}) async =>
              [_event(id: 1, name: 'UserA Med')],
          loadSummary: ({medicationScheduleId}) async => {
            'taken': 1,
            'skipped': 0,
            'missed': 0,
            'total': 1,
          },
          loadReminders: () async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('UserA Med'), findsOneWidget);

    // New session / user switch — distinct key forces fresh State (no stale events).
    await tester.pumpWidget(
      _wrap(
        MedicationHistoryScreen(
          key: const Key('history_user_b'),
          loadHistory: ({medicationScheduleId}) async => [],
          loadSummary: ({medicationScheduleId}) async => {
            'taken': 0,
            'skipped': 0,
            'missed': 0,
            'total': 0,
          },
          loadReminders: () async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('UserA Med'), findsNothing);
    expect(find.byKey(const Key('medication_history_empty')), findsOneWidget);

    // Source contract: screen does not persist events across widget identity.
    expect(historySrc.contains('clearLocalHistory'), isTrue);
    expect(apiSrc.contains('ApiClient.get'), isTrue);
  });

  test('MEDHIST-F API never sends client owner_id', () {
    expect(apiSrc.contains("'user_id'"), isFalse);
    expect(apiSrc.contains('"user_id"'), isFalse);
    expect(apiSrc.contains('owner_id'), isFalse);
    expect(apiSrc.contains('/medication-history/'), isTrue);
    expect(apiSrc.contains('scheduled_for'), isTrue);
  });

  test('MEDHIST-F navigation wired from reminders', () {
    expect(remindersSrc.contains('medication_history_nav'), isTrue);
    expect(remindersSrc.contains('/home/reminders/history'), isTrue);
    expect(routerSrc.contains("path: 'reminders/history'"), isTrue);
    expect(routerSrc.contains('MedicationHistoryScreen'), isTrue);
    expect(historySrc.contains('Taken'), isTrue);
    expect(historySrc.contains('Skipped'), isTrue);
    expect(historySrc.contains('Missed'), isTrue);
    expect(historySrc.contains('_submitting'), isTrue);
  });

  testWidgets('MEDHIST-F11 family subject context available via API filter',
      (tester) async {
    // Screen displays medicine timeline; API supports family_member_id filter
    // without letting the client invent ownership.
    expect(apiSrc.contains('familyMemberId'), isTrue);
    expect(apiSrc.contains('family_member_id'), isTrue);
    expect(apiSrc.contains("'user_id'"), isFalse);
    expect(historySrc.contains('MedicationHistoryScreen'), isTrue);
    // History does not accept a client owner override parameter.
    expect(historySrc.contains('ownerId'), isFalse);
    expect(historySrc.contains('userId'), isFalse);
  });

  testWidgets('MEDHIST-F12 history does not silently switch family subjects',
      (tester) async {
    expect(historySrc.contains('clearLocalHistory'), isTrue);
    // Filter is explicit schedule selection — not an implicit subject swap.
    expect(historySrc.contains('_filterScheduleId'), isTrue);
    expect(historySrc.contains('family_member_id='), isFalse);
    expect(historySrc.contains('?user_id='), isFalse);
  });

  testWidgets('MEDHIST-F13 no-event state is not rendered as 100% adherence',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        MedicationHistoryScreen(
          loadHistory: ({medicationScheduleId}) async => [],
          loadSummary: ({medicationScheduleId}) async => {
            'taken': 0,
            'skipped': 0,
            'missed': 0,
            'total': 0,
            'adherence_percent': null,
          },
          loadReminders: () async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('medication_adherence_summary')), findsOneWidget);
    expect(find.text('—'), findsWidgets);
    expect(find.text('100%'), findsNothing);
    expect(find.text('100.0%'), findsNothing);
    expect(historySrc.contains("pct == null ? '—'"), isTrue);
  });

  test('MEDHIST-F Missed action wiring + summary refresh after record', () {
    expect(historySrc.contains("'missed'"), isTrue);
    expect(historySrc.contains('_recordStatus'), isTrue);
    expect(historySrc.contains('await _reload()'), isTrue);
    expect(historySrc.contains('loadSummary'), isTrue);
    expect(historySrc.toLowerCase().contains('stop medication'), isFalse);
    expect(historySrc.toLowerCase().contains('double the next dose'), isFalse);
    expect(RegExp(r'\bai\b', caseSensitive: false).hasMatch(historySrc), isFalse);
  });
}
