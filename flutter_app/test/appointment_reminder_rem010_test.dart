import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/core/notifications/local_reminder_notifications.dart';
import 'package:vitapulse_ai/features/appointments/data/appointment_api.dart';
import 'package:vitapulse_ai/features/appointments/presentation/add_appointment_screen.dart';
import 'package:vitapulse_ai/features/appointments/presentation/appointments_screen.dart';
import 'package:vitapulse_ai/shared/widgets/empty_state.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppThemeBuilder.light(const AppThemeSettings()),
    home: child,
  );
}

Map<String, dynamic> _sample({
  int id = 1,
  String title = 'GP visit',
  String scheduledAt = '2026-09-20T10:00:00Z',
  int remind = 60,
}) =>
    {
      'id': id,
      'user_id': 1,
      'title': title,
      'scheduled_at': scheduledAt,
      'notes': null,
      'remind_before_minutes': remind,
      'is_active': true,
      'created_at': '2026-09-08T00:00:00Z',
    };

void main() {
  final apiSrc =
      File('lib/features/appointments/data/appointment_api.dart').readAsStringSync();
  final listSrc = File(
          'lib/features/appointments/presentation/appointments_screen.dart')
      .readAsStringSync();
  final formSrc = File(
          'lib/features/appointments/presentation/add_appointment_screen.dart')
      .readAsStringSync();
  final notifSrc =
      File('lib/core/notifications/local_reminder_notifications.dart')
          .readAsStringSync();
  final routerSrc = File('lib/core/router/app_router.dart').readAsStringSync();
  final drawerSrc =
      File('lib/features/home/presentation/app_drawer.dart').readAsStringSync();

  test('REM10-F01 appointment API contract — no client owner fields', () {
    expect(apiSrc.contains('/appointments/'), isTrue);
    expect(apiSrc.contains('createAppointment'), isTrue);
    expect(apiSrc.contains('updateAppointment'), isTrue);
    expect(apiSrc.contains('deleteAppointment'), isTrue);
    expect(apiSrc.contains("'user_id'"), isFalse);
    expect(apiSrc.contains('"user_id"'), isFalse);
    expect(apiSrc.contains('owner_id'), isFalse);
    expect(apiSrc.contains('buildAppointmentSavePayload'), isTrue);
  });

  test('REM10-F01b payload builder', () {
    final payload = buildAppointmentSavePayload(
      title: ' Specialist ',
      scheduledAt: DateTime.utc(2026, 10, 1, 9, 30),
      notes: ' Bring referral ',
      remindBeforeMinutes: 30,
      familyMemberId: null,
    );
    expect(payload['title'], 'Specialist');
    expect(payload['scheduled_at'], contains('2026-10-01'));
    expect(payload['remind_before_minutes'], 30);
    expect(payload['notes'], 'Bring referral');
    expect(payload['family_member_id'], isNull);
    expect(payload.containsKey('user_id'), isFalse);
  });

  testWidgets('REM10-F02 appointment list rendering', (tester) async {
    await tester.pumpWidget(
      _wrap(
        AppointmentsScreen(
          loadAppointments: () async => [
            _sample(id: 1, title: 'GP visit'),
            _sample(id: 2, title: 'Dentist'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('appointments_list')), findsOneWidget);
    expect(find.text('GP visit'), findsOneWidget);
    expect(find.text('Dentist'), findsOneWidget);
    expect(find.textContaining('1 hour before'), findsWidgets);
  });

  testWidgets('REM10-F02b empty state', (tester) async {
    await tester.pumpWidget(
      _wrap(
        AppointmentsScreen(loadAppointments: () async => []),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('appointments_empty')), findsOneWidget);
    expect(find.byType(EmptyState), findsOneWidget);
  });

  testWidgets('REM10-F02c error + loading states', (tester) async {
    await tester.pumpWidget(
      _wrap(
        AppointmentsScreen(
          loadAppointments: () async {
            throw Exception('network');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('appointments_error')), findsOneWidget);
  });

  testWidgets('REM10-F03 create form validation', (tester) async {
    await tester.pumpWidget(_wrap(const AddAppointmentScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('appointment_save_button')));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsOneWidget);
  });

  testWidgets('REM10-F04 edit behavior hydrates fields', (tester) async {
    await tester.pumpWidget(
      _wrap(
        AddAppointmentScreen(
          initialAppointment: _sample(
            title: 'Physio',
            remind: 15,
            scheduledAt: '2026-11-01T14:00:00Z',
          ),
          loadFamilyMembers: () async => [],
          updateAppointment: (id, data) async => {
            ...data,
            'id': id,
            'user_id': 1,
            'is_active': true,
            'created_at': '2026-09-08T00:00:00Z',
          },
          scheduleNotification: ({
            required appointmentId,
            required title,
            required scheduledAt,
            remindBeforeMinutes = 60,
            notes,
          }) async =>
              true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit_appointment_screen')), findsOneWidget);
    expect(find.text('Physio'), findsOneWidget);
    expect(find.text('15 minutes before'), findsOneWidget);
  });

  testWidgets('REM10-F05 delete cancels local notification', (tester) async {
    var deletedId = 0;
    var cancelledId = 0;
    await tester.pumpWidget(
      _wrap(
        AppointmentsScreen(
          loadAppointments: () async => [_sample(id: 42, title: 'Cancel me')],
          deleteAppointment: (id) async {
            deletedId = id;
          },
          cancelNotification: (id) async {
            cancelledId = id;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('appointment_tile_42')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(deletedId, 42);
    expect(cancelledId, 42);
  });

  test('REM10-F06 reminder configuration labels + allowed values', () {
    expect(kAllowedRemindBeforeMinutes, containsAll([0, 15, 30, 60, 120, 1440]));
    expect(remindBeforeLabel(0), 'At appointment time');
    expect(remindBeforeLabel(1440), '1 day before');
    expect(formSrc.contains('appointment_remind_before'), isTrue);
  });

  testWidgets('REM10-F07 create schedules notification once', (tester) async {
    var scheduleCalls = 0;
    Map<String, dynamic>? created;
    await tester.pumpWidget(
      _wrap(
        AddAppointmentScreen(
          loadFamilyMembers: () async => [],
          createAppointment: (data) async {
            created = data;
            return {
              ...data,
              'id': 77,
              'user_id': 1,
              'is_active': true,
              'created_at': '2026-09-08T00:00:00Z',
            };
          },
          scheduleNotification: ({
            required appointmentId,
            required title,
            required scheduledAt,
            remindBeforeMinutes = 60,
            notes,
          }) async {
            scheduleCalls++;
            expect(appointmentId, 77);
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('appointment_title_field')),
      'Optometrist',
    );
    await tester.tap(find.byKey(const Key('appointment_save_button')));
    await tester.pumpAndSettle();
    expect(created?['title'], 'Optometrist');
    expect(scheduleCalls, 1);
  });

  test('REM10-F08 notification ID namespace does not collide with medication', () {
    const scheduleId = 42;
    final refill = LocalReminderNotifications.refillNotificationId(scheduleId);
    final appt = LocalReminderNotifications.appointmentNotificationId(7);
    expect(appt, 2000000 + 7);
    expect(appt, isNot(refill));
    expect(appt, greaterThan((scheduleId + 1) * 10));
    expect(notifSrc.contains('cancelAppointmentNotification'), isTrue);
    expect(notifSrc.contains('scheduleAppointmentReminder'), isTrue);
    // Update path cancels before schedule (duplicate protection)
    expect(
      notifSrc.contains('await cancelAppointmentNotification(appointmentId)'),
      isTrue,
    );
    // Medication paths intact
    expect(notifSrc.contains('scheduleMedicationReminders'), isTrue);
    expect(notifSrc.contains('refillNotificationId'), isTrue);
  });

  test('REM10-F09 family selector + Self distinction', () {
    expect(formSrc.contains('appointment_family_member'), isTrue);
    expect(formSrc.contains("'Self'"), isTrue);
    expect(formSrc.contains('family_member_id'), isTrue);
  });

  test('REM10-F10 navigation + drawer wired', () {
    expect(routerSrc.contains("path: 'appointments'"), isTrue);
    expect(routerSrc.contains("path: 'appointments/add'"), isTrue);
    expect(routerSrc.contains("path: 'appointments/edit'"), isTrue);
    expect(drawerSrc.contains('/home/appointments'), isTrue);
    expect(listSrc.contains('cancelAppointmentNotification'), isTrue);
    expect(formSrc.contains('scheduleAppointmentReminder'), isTrue);
  });

  testWidgets('REM10-F11 double submit prevented', (tester) async {
    var creates = 0;
    await tester.pumpWidget(
      _wrap(
        AddAppointmentScreen(
          loadFamilyMembers: () async => [],
          createAppointment: (data) async {
            creates++;
            await Future<void>.delayed(const Duration(milliseconds: 300));
            return {
              ...data,
              'id': 1,
              'user_id': 1,
              'is_active': true,
              'created_at': '2026-09-08T00:00:00Z',
            };
          },
          scheduleNotification: ({
            required appointmentId,
            required title,
            required scheduledAt,
            remindBeforeMinutes = 60,
            notes,
          }) async =>
              true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('appointment_title_field')),
      'Clinic',
    );
    await tester.tap(find.byKey(const Key('appointment_save_button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('appointment_save_button')));
    await tester.pumpAndSettle();
    expect(creates, 1);
  });
}
