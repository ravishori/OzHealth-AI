import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vitapulse_ai/features/settings/presentation/privacy_settings_screen.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

Future<void> _pumpPrivacy(
  WidgetTester tester, {
  required bool consent,
  required PermissionStatus notif,
  Future<bool> Function()? openSettings,
  Future<Map<String, dynamic>> Function()? exportMyData,
  Future<void> Function(Map<String, dynamic>)? shareExport,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppThemeBuilder.light(const AppThemeSettings()),
      home: PrivacySettingsScreen(
        readConsentCompleted: () => consent,
        readNotificationStatus: () async => notif,
        openSystemSettings: openSettings ?? () async => true,
        exportMyData: exportMyData ?? () async => <String, dynamic>{},
        shareExport: shareExport ?? (_) async {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  final screenSrc = File(
          'lib/features/settings/presentation/privacy_settings_screen.dart')
      .readAsStringSync();
  final routerSrc =
      File('lib/core/router/app_router.dart').readAsStringSync();
  final drawerSrc =
      File('lib/features/home/presentation/app_drawer.dart').readAsStringSync();

  testWidgets('SET03-01 privacy settings screen loads', (tester) async {
    await _pumpPrivacy(
      tester,
      consent: true,
      notif: PermissionStatus.granted,
    );
    expect(find.byKey(const Key('privacy_settings_screen')), findsOneWidget);
    expect(find.text('Privacy actions'), findsOneWidget);
  });

  testWidgets('SET03-02 current consent + notification state rendered',
      (tester) async {
    await _pumpPrivacy(
      tester,
      consent: true,
      notif: PermissionStatus.denied,
    );
    expect(find.textContaining('Recorded on this device'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('privacy_notification_status')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Not allowed'), findsOneWidget);
  });

  testWidgets('SET03-03/08 system notification settings action is invoked',
      (tester) async {
    var opened = false;
    await _pumpPrivacy(
      tester,
      consent: true,
      notif: PermissionStatus.denied,
      openSettings: () async {
        opened = true;
        return true;
      },
    );
    await _tapKey(tester, const Key('privacy_open_notification_settings'));
    expect(opened, isTrue);
  });

  testWidgets('SET03-04/07 export invokes export + share (real path)',
      (tester) async {
    var exported = false;
    var shared = false;
    await _pumpPrivacy(
      tester,
      consent: false,
      notif: PermissionStatus.granted,
      exportMyData: () async {
        exported = true;
        return {'user_id': 9, 'exported_at': '2026-09-08'};
      },
      shareExport: (payload) async {
        shared = true;
        expect(payload['user_id'], 9);
      },
    );
    await _tapKey(tester, const Key('privacy_export_data'));
    expect(exported, isTrue);
    expect(shared, isTrue);
    expect(find.textContaining('ready to save or share'), findsOneWidget);
  });

  test('SET03-05/06 backend ownership remains on existing export API', () {
    final api =
        File('lib/features/profile/data/user_api.dart').readAsStringSync();
    expect(api.contains("/users/me/data-export"), isTrue);
    expect(api.contains('exportMyData'), isTrue);
  });

  test('SET03-09 no sensitive preference logging in privacy screen', () {
    expect(screenSrc.contains('DebugLogger'), isFalse);
    expect(screenSrc.contains('print('), isFalse);
    expect(screenSrc.contains('debugPrint('), isFalse);
    expect(screenSrc.contains('jsonEncode'), isFalse);
  });

  testWidgets('SET03-10 accessibility semantics for primary controls',
      (tester) async {
    await _pumpPrivacy(
      tester,
      consent: true,
      notif: PermissionStatus.granted,
    );
    await tester.ensureVisible(
        find.byKey(const Key('privacy_open_notification_settings')));
    await tester.pumpAndSettle();
    expect(find.text('System settings'), findsOneWidget);
    expect(find.byKey(const Key('privacy_export_data')), findsOneWidget);
    expect(find.byKey(const Key('privacy_delete_account')), findsOneWidget);
    expect(find.byKey(const Key('privacy_consent_status')), findsOneWidget);
  });

  test('SET03 no fake analytics/AI/sharing toggles', () {
    expect(screenSrc.contains('Analytics'), isFalse);
    expect(screenSrc.contains('Firebase'), isFalse);
    expect(screenSrc.contains('Use my data for AI'), isFalse);
    expect(screenSrc.contains('Share my health data'), isFalse);
    expect(screenSrc.contains('Switch('), isFalse);
    expect(screenSrc.contains('SwitchListTile'), isFalse);
  });

  test('SET03 legal consent remains authoritative (status only)', () {
    expect(screenSrc.contains('kLegalConsentKey'), isTrue);
    expect(screenSrc.contains("put(kLegalConsentKey"), isFalse);
    expect(screenSrc.contains('Required before using the app'), isTrue);
  });

  test('SET03 navigation wiring', () {
    expect(routerSrc.contains('settings/privacy'), isTrue);
    expect(routerSrc.contains('PrivacySettingsScreen'), isTrue);
    expect(drawerSrc.contains('/home/settings/privacy'), isTrue);
    expect(
      drawerSrc.contains("label: 'Privacy'") ||
          drawerSrc.contains('label: l10n.privacy'),
      isTrue,
    );
  });

  testWidgets('SET03 delete account deep-link is present', (tester) async {
    final router = GoRouter(
      initialLocation: '/home/settings/privacy',
      routes: [
        GoRoute(
          path: '/home/settings/privacy',
          builder: (_, __) => PrivacySettingsScreen(
            readConsentCompleted: () => true,
            readNotificationStatus: () async => PermissionStatus.granted,
            openSystemSettings: () async => true,
            exportMyData: () async => {},
            shareExport: (_) async {},
          ),
        ),
        GoRoute(
          path: '/legal/delete-account',
          builder: (_, __) => const Scaffold(
            key: Key('delete_dest'),
            body: Text('delete_dest'),
          ),
        ),
        GoRoute(
          path: '/legal/privacy',
          builder: (_, __) => const Scaffold(body: Text('privacy_dest')),
        ),
        GoRoute(
          path: '/legal/terms',
          builder: (_, __) => const Scaffold(body: Text('terms_dest')),
        ),
        GoRoute(
          path: '/legal/consent',
          builder: (_, __) => const Scaffold(body: Text('consent_dest')),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppThemeBuilder.light(const AppThemeSettings()),
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();
    await _tapKey(tester, const Key('privacy_delete_account'));
    expect(find.byKey(const Key('delete_dest')), findsOneWidget);
  });
}
