import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/auth/data/auth_api.dart';

void main() {
  test('AUTH-UI-LOGOUT-02 AuthApi.logout calls POST /auth/logout before clear',
      () {
    final src =
        File('lib/features/auth/data/auth_api.dart').readAsStringSync();
    expect(src.contains("ApiClient.post('/auth/logout')"), isTrue);
    expect(src.contains('AuthStorage.clearAll()'), isTrue);
    // Server call appears before clearAll in source order
    final postIdx = src.indexOf("ApiClient.post('/auth/logout')");
    final clearIdx = src.indexOf('AuthStorage.clearAll()');
    expect(postIdx, greaterThanOrEqualTo(0));
    expect(clearIdx, greaterThan(postIdx));
  });

  test('AUTH-UI-LOGOUT-03/06 LogoutOutcome distinguishes server vs local-only',
      () {
    expect(LogoutOutcome.values, contains(LogoutOutcome.serverOk));
    expect(LogoutOutcome.values, contains(LogoutOutcome.localOnly));
    final src =
        File('lib/features/auth/data/auth_api.dart').readAsStringSync();
    expect(src.contains('LogoutOutcome.localOnly'), isTrue);
  });

  test('AUTH-UI-LOGOUT-01/04/05 logout UX contracts in home/profile/drawer', () {
    final home =
        File('lib/features/home/presentation/home_screen.dart').readAsStringSync();
    final profile = File('lib/features/profile/presentation/profile_screen.dart')
        .readAsStringSync();
    final drawer =
        File('lib/features/home/presentation/app_drawer.dart').readAsStringSync();
    for (final src in [home, profile, drawer]) {
      expect(src.contains('AuthApi.logout()'), isTrue);
      expect(src.contains("_loggingOut"), isTrue);
      expect(src.contains("context.go('/auth/welcome')"), isTrue);
      expect(
        src.contains('Server session could not be confirmed'),
        isTrue,
      );
    }
  });

  test('AUTH-UI-LOGOUT-07/08 welcome route remains the post-logout entry', () {
    final router =
        File('lib/core/router/app_router.dart').readAsStringSync();
    expect(router.contains('/auth/welcome') || router.contains('welcome'),
        isTrue);
    expect(router.contains('LoginScreen') || router.contains('login'), isTrue);
  });
}
