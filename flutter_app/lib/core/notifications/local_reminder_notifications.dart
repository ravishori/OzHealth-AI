import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// On-device medication reminders.
///
/// Server FCM is NOT required for local alerts and is not claimed as complete.
/// Local scheduling is the Sprint 1 delivery path for medication reminders.
class LocalReminderNotifications {
  LocalReminderNotifications._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _ready = false;
  static const _channelId = 'vitapulse_reminders';
  static const _channelName = 'Medication reminders';
  // Keep channel id stable for existing installs (technical identifier).

  static Future<void> init() async {
    if (_ready) return;
    tz.initializeTimeZones();
    // Align tz.local with the device wall clock (TimeOfDay picker times).
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      // Keep default location if native timezone lookup fails.
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Medication reminder alerts',
        importance: Importance.high,
      ),
    );

    // Do not call requestExactAlarmsPermission() here — it opens a system
    // settings UI and can hang headless/instrumentation runs. Exact alarms are
    // requested via SCHEDULE_EXACT_ALARM in the manifest; grant with ADB/settings.
    _ready = true;
  }

  /// Request POST_NOTIFICATIONS on Android 13+.
  static Future<bool> ensurePermission() async {
    if (kIsWeb) return false;
    if (Platform.isAndroid) {
      final status = await Permission.notification.status;
      if (status.isGranted) return true;
      final req = await Permission.notification.request();
      return req.isGranted;
    }
    return true;
  }

  /// Dose notification IDs use `scheduleId * 10 + 0..3`.
  /// Refill one-shot uses `scheduleId * 10 + 9` — outside the dose range and
  /// before the next schedule's decade block (`(scheduleId+1)*10`).
  static int refillNotificationId(int scheduleId) => scheduleId * 10 + 9;

  /// Cancel dose slots (0..3) and the refill one-shot (+9) for [scheduleId].
  static Future<void> cancelForSchedule(int scheduleId) async {
    await init();
    final base = scheduleId * 10;
    for (var i = 0; i < 4; i++) {
      await _plugin.cancel(base + i);
    }
    await _plugin.cancel(refillNotificationId(scheduleId));
  }

  /// Cancel only the refill one-shot for [scheduleId].
  static Future<void> cancelRefillNotification(int scheduleId) async {
    await init();
    await _plugin.cancel(refillNotificationId(scheduleId));
  }

  /// Schedule reminders. Returns false if notification permission denied
  /// or Android notifications are disabled for the app.
  ///
  /// [frequencyApi] is the canonical API value (`daily`, `weekly`, …).
  /// Weekly/monthly use [startDate] as the calendar anchor when provided.
  ///
  /// [refillDate] schedules a one-shot local refill alert (HN-REM-009).
  /// Past/invalid refill times are skipped (not moved). No FCM.
  static Future<bool> scheduleMedicationReminders({
    required int scheduleId,
    required String medicineName,
    required List<String> times,
    String? dosage,
    String frequencyApi = 'daily',
    DateTime? startDate,
    DateTime? refillDate,
    int refillHour = 9,
    int refillMinute = 0,
  }) async {
    await init();
    // Always clear prior slots for this schedule to avoid duplicates on update.
    await cancelForSchedule(scheduleId);

    final allowed = await ensurePermission();
    if (!allowed) return false;

    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final enabled = await androidPlugin?.areNotificationsEnabled();
      if (enabled == false) return false;
    }

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Medication reminder alerts',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details =
        NotificationDetails(android: androidDetails, iOS: iosDetails);

    final matchComponents = _matchComponents(frequencyApi);
    final now = tz.TZDateTime.now(tz.local);
    const slotLimit = 4;
    final notifIdBase = scheduleId * 10;

    for (var i = 0; i < times.length && i < slotLimit; i++) {
      final parts = times[i].split(':');
      if (parts.length < 2) continue;
      final hour = int.tryParse(parts[0]) ?? 8;
      final minute = int.tryParse(parts[1]) ?? 0;

      var when = _nextOccurrence(
        now: now,
        hour: hour,
        minute: minute,
        frequencyApi: frequencyApi,
        startDate: startDate,
      );

      const title = 'Medication reminder';
      final body = dosage == null || dosage.isEmpty
          ? 'Time to take $medicineName'
          : 'Time to take $medicineName ($dosage)';

      await _plugin.zonedSchedule(
        notifIdBase + i,
        title,
        body,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: matchComponents,
      );
    }

    await _scheduleRefillOneShot(
      scheduleId: scheduleId,
      medicineName: medicineName,
      dosage: dosage,
      refillDate: refillDate,
      hour: refillHour,
      minute: refillMinute,
      details: details,
    );
    return true;
  }

  /// Schedule (or skip) a one-shot refill notification.
  /// Returns false only when permission/channel blocks scheduling of a
  /// future refill; returns true when there is nothing to schedule
  /// (null/past date) or when the one-shot was queued.
  static Future<bool> scheduleRefillReminder({
    required int scheduleId,
    required String medicineName,
    DateTime? refillDate,
    String? dosage,
    int hour = 9,
    int minute = 0,
  }) async {
    await init();
    await cancelRefillNotification(scheduleId);
    if (refillDate == null) return true;

    final allowed = await ensurePermission();
    if (!allowed) return false;

    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final enabled = await androidPlugin?.areNotificationsEnabled();
      if (enabled == false) return false;
    }

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Medication reminder alerts',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    return _scheduleRefillOneShot(
      scheduleId: scheduleId,
      medicineName: medicineName,
      dosage: dosage,
      refillDate: refillDate,
      hour: hour,
      minute: minute,
      details: details,
    );
  }

  /// Returns true if scheduled or intentionally skipped; false if blocked.
  static Future<bool> _scheduleRefillOneShot({
    required int scheduleId,
    required String medicineName,
    required String? dosage,
    required DateTime? refillDate,
    required int hour,
    required int minute,
    required NotificationDetails details,
  }) async {
    if (refillDate == null) return true;

    final now = tz.TZDateTime.now(tz.local);
    final when = tz.TZDateTime(
      tz.local,
      refillDate.year,
      refillDate.month,
      refillDate.day,
      hour,
      minute,
    );
    // Past-date safety: never silently move the user's selected date.
    if (!when.isAfter(now)) {
      return true;
    }

    final body = dosage == null || dosage.isEmpty
        ? 'Time to refill $medicineName'
        : 'Time to refill $medicineName ($dosage)';

    await _plugin.zonedSchedule(
      refillNotificationId(scheduleId),
      'Refill reminder',
      body,
      when,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      // One-shot — no DateTimeComponents match.
    );
    return true;
  }

  static DateTimeComponents? _matchComponents(String frequencyApi) {
    switch (frequencyApi) {
      case 'weekly':
      case 'fortnightly':
        // Plugin has no fortnightly match; weekly day-of-week is the closest.
        return DateTimeComponents.dayOfWeekAndTime;
      case 'monthly':
        return DateTimeComponents.dayOfMonthAndTime;
      case 'as_needed':
        return null; // one-shot next occurrence only
      default:
        return DateTimeComponents.time; // daily / multi-daily
    }
  }

  static tz.TZDateTime _nextOccurrence({
    required tz.TZDateTime now,
    required int hour,
    required int minute,
    required String frequencyApi,
    DateTime? startDate,
  }) {
    var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);

    if (frequencyApi == 'weekly' || frequencyApi == 'fortnightly') {
      final targetWeekday = (startDate ?? now).weekday; // 1=Mon … 7=Sun
      while (when.weekday != targetWeekday || !when.isAfter(now)) {
        when = when.add(const Duration(days: 1));
      }
      return when;
    }

    if (frequencyApi == 'monthly') {
      final targetDay = (startDate ?? now).day;
      when = tz.TZDateTime(tz.local, now.year, now.month, targetDay, hour, minute);
      if (!when.isAfter(now)) {
        final nextMonth = now.month == 12 ? 1 : now.month + 1;
        final nextYear = now.month == 12 ? now.year + 1 : now.year;
        final lastDay = DateTime(nextYear, nextMonth + 1, 0).day;
        final day = targetDay > lastDay ? lastDay : targetDay;
        when = tz.TZDateTime(tz.local, nextYear, nextMonth, day, hour, minute);
      }
      return when;
    }

    if (!when.isAfter(now)) {
      when = when.add(const Duration(days: 1));
    }
    return when;
  }
}
