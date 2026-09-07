import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/notifications/data/in_app_notification_inbox.dart';
import 'package:vitapulse_ai/features/notifications/presentation/notifications_screen.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppThemeBuilder.light(const AppThemeSettings()),
    home: child,
  );
}

void main() {
  final homeSrc =
      File('lib/features/home/presentation/home_screen.dart').readAsStringSync();
  final routerSrc =
      File('lib/core/router/app_router.dart').readAsStringSync();
  final screenSrc = File(
          'lib/features/notifications/presentation/notifications_screen.dart')
      .readAsStringSync();
  final inboxSrc = File(
          'lib/features/notifications/data/in_app_notification_inbox.dart')
      .readAsStringSync();

  test('NOTIF-006-FL-01 Home bell opens Notifications', () {
    expect(homeSrc.contains("tooltip: 'Notifications'"), isTrue);
    expect(homeSrc.contains("context.push('/home/notifications')"), isTrue);
    expect(homeSrc.contains('home-notifications-bell'), isTrue);
    expect(homeSrc.contains('placeholder — screen not yet implemented'), isFalse);
    expect(routerSrc.contains("path: 'notifications'"), isTrue);
    expect(routerSrc.contains('NotificationsScreen'), isTrue);
  });

  test('NOTIF-006-FL-02 authoritative source is empty (no persisted inbox)',
      () async {
    final items = await InAppNotificationInbox.load();
    expect(items, isEmpty);
    expect(inboxSrc.contains('notification_logs'), isTrue);
    expect(inboxSrc.contains('return const [];'), isTrue);
    expect(screenSrc.contains('pendingNotificationRequests'), isFalse);
    expect(screenSrc.contains('FirebaseMessaging'), isFalse);
    expect(inboxSrc.contains('FirebaseMessaging'), isFalse);
  });

  testWidgets('NOTIF-006-FL-03 loading state displays', (tester) async {
    final gate = Completer<List<InAppNotification>>();
    await tester.pumpWidget(
      _wrap(NotificationsScreen(loader: () => gate.future)),
    );
    await tester.pump();
    expect(find.byKey(const Key('notifications-loading')), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    gate.complete(const []);
    await tester.pump();
  });

  testWidgets('NOTIF-006-FL-04 empty state when there are no notifications',
      (tester) async {
    await tester.pumpWidget(
      _wrap(NotificationsScreen(loader: () async => const [])),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('notifications-empty')), findsOneWidget);
    expect(find.text('No in-app notifications yet'), findsOneWidget);
    expect(find.text('View medication reminders'), findsOneWidget);
    expect(find.text('Unread'), findsNothing);
  });

  testWidgets('NOTIF-006-FL-05 error state and retry', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _wrap(
        NotificationsScreen(
          loader: () async {
            calls += 1;
            if (calls == 1) throw Exception('unavailable');
            return const [];
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('notifications-error')), findsOneWidget);
    expect(find.byKey(const Key('notifications-retry')), findsOneWidget);
    await tester.tap(find.byKey(const Key('notifications-retry')));
    await tester.pump();
    await tester.pump();
    expect(calls, 2);
    expect(find.byKey(const Key('notifications-empty')), findsOneWidget);
  });

  testWidgets('NOTIF-006-FL-06 content displayed without raw IDs',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        NotificationsScreen(
          loader: () async => const [
            InAppNotification(
              title: 'Reminder saved',
              body: 'Evening dose alert is on this device',
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Reminder saved'), findsOneWidget);
    expect(find.text('Evening dose alert is on this device'), findsOneWidget);
    expect(find.text('id'), findsNothing);
    expect(find.text('42'), findsNothing);
  });

  testWidgets(
      'NOTIF-006-FL-07 unread indicator only when source provides unread',
      (tester) async {
    await tester.pumpWidget(
      _wrap(NotificationsScreen(loader: () async => const [])),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byIcon(Icons.notifications_active_outlined), findsNothing);
    expect(screenSrc.contains('item.isUnread == true'), isTrue);
  });

  testWidgets('NOTIF-006-FL-08 duplicate load is ignored while in flight',
      (tester) async {
    var calls = 0;
    final gate = Completer<List<InAppNotification>>();
    await tester.pumpWidget(
      _wrap(
        NotificationsScreen(
          loader: () {
            calls += 1;
            return gate.future;
          },
        ),
      ),
    );
    await tester.pump();
    expect(calls, 1);
    expect(find.byKey(const Key('notifications-loading')), findsOneWidget);
    gate.complete(const []);
    await tester.pump();
  });

  test('NOTIF-006-FL-09 no notification body/health payload logging', () {
    expect(screenSrc.contains('debugPrint'), isFalse);
    expect(screenSrc.contains('print('), isFalse);
    expect(screenSrc.contains('DebugLogger'), isFalse);
    expect(inboxSrc.contains('debugPrint'), isFalse);
    expect(inboxSrc.contains('print('), isFalse);
    expect(screenSrc.contains('diagnose'), isFalse);
  });
}
