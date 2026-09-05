/// Fire verification for Sprint 1 notification E2E.
///   flutter test integration_test/notification_fire_test.dart -d emulator-5554
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:vitapulse_ai/core/notifications/local_reminder_notifications.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('N02b daily notification fires within ~2 minutes', (tester) async {
    await LocalReminderNotifications.init();
    expect(await LocalReminderNotifications.ensurePermission(), isTrue);

    // Sanity: channel can post immediately.
    await FlutterLocalNotificationsPlugin().show(
      91999,
      'Medication reminder',
      'Immediate channel check',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'vitapulse_reminders',
          'Medication reminders',
          channelDescription: 'Medication reminder alerts',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    final immediate = await FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.getActiveNotifications();
    expect(
      immediate?.any((n) => (n.body ?? '').contains('Immediate channel check')),
      isTrue,
      reason: 'Notification channel must be able to display',
    );
    await FlutterLocalNotificationsPlugin().cancel(91999);

    const scheduleId = 92001;
    await LocalReminderNotifications.cancelForSchedule(scheduleId);

    // Target the next whole minute + 1 so HH:mm scheduling is unambiguous.
    final now = DateTime.now();
    final target = DateTime(now.year, now.month, now.day, now.hour, now.minute)
        .add(const Duration(minutes: 2));
    final hh = target.hour.toString().padLeft(2, '0');
    final mm = target.minute.toString().padLeft(2, '0');

    final ok = await LocalReminderNotifications.scheduleMedicationReminders(
      scheduleId: scheduleId,
      medicineName: 'Sprint1 Fire Daily',
      times: ['$hh:$mm'],
      dosage: '1 tab',
      frequencyApi: 'daily',
      startDate: DateTime.now(),
    );
    expect(ok, isTrue);

    final pending = await FlutterLocalNotificationsPlugin()
        .pendingNotificationRequests();
    expect(
      pending.any((p) => p.id >= scheduleId * 10 && p.id < scheduleId * 10 + 4),
      isTrue,
    );

    // Wait until shortly after the scheduled minute (tz.local aligned).
    final waitUntil = tz.TZDateTime(
      tz.local,
      target.year,
      target.month,
      target.day,
      target.hour,
      target.minute,
    ).add(const Duration(seconds: 25));
    while (tz.TZDateTime.now(tz.local).isBefore(waitUntil)) {
      await Future<void>.delayed(const Duration(seconds: 5));
    }

    var fired = false;
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(deadline)) {
      final active = await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.getActiveNotifications();
      if (active != null &&
          active.any((n) =>
              (n.title ?? '').contains('Medication reminder') ||
              (n.body ?? '').contains('Sprint1 Fire Daily'))) {
        fired = true;
        break;
      }
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    expect(fired, isTrue,
        reason:
            'Expected scheduled daily notification at $hh:$mm (tz=${tz.local.name})');
  }, timeout: const Timeout(Duration(minutes: 5)));

  /// N04b — actual Android fire for a monthly reminder.
  ///
  /// Uses the production scheduler (`frequencyApi: monthly` +
  /// `DateTimeComponents.dayOfMonthAndTime`). The due day is today
  /// (`startDate.day`); the due time is the next whole minute + 1 so the
  /// first monthly occurrence is imminent. This is the same pattern as N02b
  /// (first occurrence of the real recurrence), not a daily substitute and
  /// not a manual `show()`.
  testWidgets('N04b monthly notification fires within ~2 minutes', (tester) async {
    await LocalReminderNotifications.init();
    expect(await LocalReminderNotifications.ensurePermission(), isTrue);

    const scheduleId = 92004;
    await LocalReminderNotifications.cancelForSchedule(scheduleId);

    final now = DateTime.now();
    final target = DateTime(now.year, now.month, now.day, now.hour, now.minute)
        .add(const Duration(minutes: 2));
    final hh = target.hour.toString().padLeft(2, '0');
    final mm = target.minute.toString().padLeft(2, '0');
    final startDate = DateTime(now.year, now.month, now.day);

    tester.printToConsole('N04b scheduleId=$scheduleId frequency=monthly '
        'start_date=${startDate.toIso8601String().split('T').first} '
        'due_day=${startDate.day} next=$hh:$mm tz=${tz.local.name}');

    final ok = await LocalReminderNotifications.scheduleMedicationReminders(
      scheduleId: scheduleId,
      medicineName: 'Sprint1 Fire Monthly',
      times: ['$hh:$mm'],
      dosage: '1 tab',
      frequencyApi: 'monthly',
      startDate: startDate,
    );
    expect(ok, isTrue);

    final pending = await FlutterLocalNotificationsPlugin()
        .pendingNotificationRequests();
    final mine = pending.where((p) =>
        p.id >= scheduleId * 10 &&
        p.id < scheduleId * 10 + 4 &&
        (p.body ?? '').contains('Sprint1 Fire Monthly'));
    expect(mine.isNotEmpty, isTrue, reason: 'Expected pending monthly notif');
    expect(mine.length, 1, reason: 'Single monthly slot; no duplicates');

    final waitUntil = tz.TZDateTime(
      tz.local,
      target.year,
      target.month,
      target.day,
      target.hour,
      target.minute,
    ).add(const Duration(seconds: 25));
    while (tz.TZDateTime.now(tz.local).isBefore(waitUntil)) {
      await Future<void>.delayed(const Duration(seconds: 5));
    }

    var firedCount = 0;
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(deadline)) {
      final active = await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.getActiveNotifications();
      final matches = (active ?? const <ActiveNotification>[])
          .where((n) => (n.body ?? '').contains('Sprint1 Fire Monthly'))
          .toList();
      if (matches.isNotEmpty) {
        firedCount = matches.length;
        expect(matches.first.title, contains('Medication reminder'));
        break;
      }
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    expect(firedCount, 1,
        reason:
            'Expected one monthly fire at $hh:$mm on day ${startDate.day} '
            '(tz=${tz.local.name}); schedule-only is not sufficient');

    await LocalReminderNotifications.cancelForSchedule(scheduleId);
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('N08a schedule survives for reboot check (pending present)',
      (tester) async {
    await LocalReminderNotifications.init();
    expect(await LocalReminderNotifications.ensurePermission(), isTrue);
    const scheduleId = 92008;
    await LocalReminderNotifications.cancelForSchedule(scheduleId);
    final when = DateTime.now().add(const Duration(minutes: 5));
    final hh = when.hour.toString().padLeft(2, '0');
    final mm = when.minute.toString().padLeft(2, '0');
    final ok = await LocalReminderNotifications.scheduleMedicationReminders(
      scheduleId: scheduleId,
      medicineName: 'Sprint1 Reboot Persist',
      times: ['$hh:$mm'],
      frequencyApi: 'daily',
    );
    expect(ok, isTrue);
    final pending = await FlutterLocalNotificationsPlugin()
        .pendingNotificationRequests();
    expect(
      pending.any((p) =>
          p.id >= scheduleId * 10 &&
          (p.body ?? '').contains('Sprint1 Reboot Persist')),
      isTrue,
    );
  });
}
