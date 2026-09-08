/// HN-SET-004 focused Flutter tests (SET004-FL-01..10).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/settings/domain/app_lock_service.dart';
import 'package:vitapulse_ai/features/settings/domain/device_authenticator.dart';
import 'package:vitapulse_ai/features/settings/presentation/security_settings_screen.dart';
import 'package:vitapulse_ai/l10n/app_localizations.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

class _FakeAuth implements DeviceAuthenticator {
  _FakeAuth({
    this.available = true,
    this.next = DeviceAuthResult.success,
  });

  bool available;
  DeviceAuthResult next;
  int authCalls = 0;

  @override
  Future<bool> canAuthenticate() async => available;

  @override
  Future<DeviceAuthResult> authenticate({required String localizedReason}) async {
    authCalls += 1;
    expect(localizedReason.isNotEmpty, isTrue);
    return next;
  }
}

Future<void> _pumpSecurity(WidgetTester tester, _FakeAuth auth) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppThemeBuilder.light(const AppThemeSettings()),
      home: SecuritySettingsScreen(authenticator: auth),
    ),
  );
  // Allow async _refresh() without waiting on unbounded animations.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLockService.debugUseInMemoryPreference(enabled: false);
    AppLockService.debugResetSession(unlocked: false);
    AppLockService.debugReplaceAuthenticator(LocalAuthDeviceAuthenticator());
  });

  tearDown(() {
    AppLockService.debugClearInMemoryPreference();
    AppLockService.debugResetSession(unlocked: false);
    AppLockService.debugReplaceAuthenticator(LocalAuthDeviceAuthenticator());
  });

  testWidgets('SET004-FL-01 security settings screen is reachable/renders',
      (tester) async {
    final auth = _FakeAuth();
    await _pumpSecurity(tester, auth);
    expect(find.text('Security'), findsOneWidget);
    expect(find.byKey(const Key('security_biometric_toggle')), findsOneWidget);
  });

  testWidgets('SET004-FL-02 current security state displayed accurately',
      (tester) async {
    AppLockService.debugUseInMemoryPreference(enabled: true);
    final auth = _FakeAuth();
    await _pumpSecurity(tester, auth);
    final toggle = tester.widget<SwitchListTile>(
      find.byKey(const Key('security_biometric_toggle')),
    );
    expect(toggle.value, isTrue);
  });

  testWidgets('SET004-FL-03 enabling requires successful authentication',
      (tester) async {
    final auth = _FakeAuth(next: DeviceAuthResult.success);
    await _pumpSecurity(tester, auth);
    await tester.tap(find.byKey(const Key('security_biometric_toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(auth.authCalls, 1);
    expect(AppLockService.isBiometricLockEnabled(), isTrue);
    expect(find.textContaining('enabled'), findsWidgets);
  });

  testWidgets('SET004-FL-04 failed biometric does not enable protection',
      (tester) async {
    final auth = _FakeAuth(next: DeviceAuthResult.failed);
    await _pumpSecurity(tester, auth);
    await tester.tap(find.byKey(const Key('security_biometric_toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(AppLockService.isBiometricLockEnabled(), isFalse);
    expect(find.byKey(const Key('security_status_message')), findsOneWidget);
  });

  testWidgets('SET004-FL-05 cancelled biometric does not enable protection',
      (tester) async {
    final auth = _FakeAuth(next: DeviceAuthResult.cancelled);
    await _pumpSecurity(tester, auth);
    await tester.tap(find.byKey(const Key('security_biometric_toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(AppLockService.isBiometricLockEnabled(), isFalse);
  });

  testWidgets('SET004-FL-06 unavailable biometrics handled safely',
      (tester) async {
    final auth = _FakeAuth(available: false);
    await _pumpSecurity(tester, auth);
    await tester.tap(find.byKey(const Key('security_biometric_toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(auth.authCalls, 0);
    expect(AppLockService.isBiometricLockEnabled(), isFalse);
    expect(find.textContaining('not available'), findsWidgets);
  });

  testWidgets('SET004-FL-07 disable requires authentication', (tester) async {
    AppLockService.debugUseInMemoryPreference(enabled: true);
    AppLockService.debugResetSession(unlocked: true);
    final auth = _FakeAuth(next: DeviceAuthResult.success);
    await _pumpSecurity(tester, auth);
    await tester.tap(find.byKey(const Key('security_biometric_toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(auth.authCalls, 1);
    expect(AppLockService.isBiometricLockEnabled(), isFalse);
  });

  testWidgets('SET004-FL-08 failed disable keeps protection enabled',
      (tester) async {
    AppLockService.debugUseInMemoryPreference(enabled: true);
    final auth = _FakeAuth(next: DeviceAuthResult.failed);
    await _pumpSecurity(tester, auth);
    await tester.tap(find.byKey(const Key('security_biometric_toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(AppLockService.isBiometricLockEnabled(), isTrue);
  });

  test('SET004-FL-09 protected boundary session unlock gate', () {
    AppLockService.debugUseInMemoryPreference(enabled: true);
    AppLockService.debugResetSession(unlocked: false);
    expect(AppLockService.isSessionUnlocked, isFalse);
    AppLockService.unlockSession();
    expect(AppLockService.isSessionUnlocked, isTrue);
    AppLockService.lockSession();
    expect(AppLockService.isSessionUnlocked, isFalse);
  });

  test('SET004-FL-10 no PIN plaintext path / preference is non-secret boolean',
      () {
    AppLockService.debugUseInMemoryPreference(enabled: true);
    expect(AppLockService.isBiometricLockEnabled(), isTrue);
    // Contract: SET-004 stores only a non-secret boolean preference key.
    // Remaining AC does not require PIN — ensure no PIN credential storage.
    final serviceSrc =
        File('lib/features/settings/domain/app_lock_service.dart')
            .readAsStringSync();
    expect(serviceSrc.contains("'app_lock_biometrics_enabled'"), isTrue);
    expect(serviceSrc.contains('app_lock_pin'), isFalse);
    expect(serviceSrc.contains('pin_hash'), isFalse);
    expect(serviceSrc.contains('plaintext'), isFalse);
    expect(
      File('lib/features/settings/presentation/security_settings_screen.dart')
          .readAsStringSync()
          .contains('TextField'),
      isFalse,
    );
  });

  testWidgets('SET004 accessibility semantics on toggle', (tester) async {
    final auth = _FakeAuth();
    await _pumpSecurity(tester, auth);
    expect(find.bySemanticsLabel('Biometric app lock'), findsWidgets);
  });

  testWidgets('SET004 large text does not overflow settings title',
      (tester) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppThemeBuilder.light(const AppThemeSettings()),
          home: SecuritySettingsScreen(authenticator: auth),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    expect(find.text('Security'), findsOneWidget);
  });

  testWidgets('SET004 localization Hindi security label', (tester) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('hi'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppThemeBuilder.light(const AppThemeSettings()),
        home: SecuritySettingsScreen(authenticator: auth),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('सुरक्षा'), findsOneWidget);
  });

  testWidgets('SET004 localization Marathi security label', (tester) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('mr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppThemeBuilder.light(const AppThemeSettings()),
        home: SecuritySettingsScreen(authenticator: auth),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('सुरक्षा'), findsOneWidget);
  });

  test('SET004 router wires security + app-lock routes', () {
    final router = File('lib/core/router/app_router.dart').readAsStringSync();
    expect(router.contains("path: 'settings/security'"), isTrue);
    expect(router.contains("path: '/auth/app-lock'"), isTrue);
    expect(router.contains('AppLockService.requiresUnlock'), isTrue);
  });

  test('SET004 logout locks session before clearAll', () {
    final src = File('lib/features/auth/data/auth_api.dart').readAsStringSync();
    expect(src.contains('AppLockService.lockSession()'), isTrue);
    expect(src.contains('AuthStorage.clearAll()'), isTrue);
    final lockIdx = src.indexOf('AppLockService.lockSession()');
    final clearIdx = src.indexOf('AuthStorage.clearAll()');
    expect(lockIdx, lessThan(clearIdx));
  });

  test('SET004 drawer exposes security entry', () {
    final src =
        File('lib/features/home/presentation/app_drawer.dart').readAsStringSync();
    expect(src.contains('/home/settings/security'), isTrue);
    expect(src.contains('l10n.security'), isTrue);
  });
}
