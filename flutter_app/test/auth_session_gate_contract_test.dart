import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// HN-AUTH-008 splash / session gate contracts + logout/tv regression hooks.
void main() {
  test('AUTH8 splash uses AuthStorage.isLoggedIn for home vs welcome', () {
    final splash =
        File('lib/features/splash/splash_screen.dart').readAsStringSync();
    expect(splash.contains('AuthStorage.isLoggedIn()'), isTrue);
    expect(splash.contains("context.go(loggedIn ? '/home' : '/auth/welcome')"),
        isTrue);
    // Unused import that previously warned must stay gone when splash is touched.
    expect(
      splash.contains("theme/design_tokens/app_radius.dart"),
      isFalse,
    );
  });

  test('AUTH8 AuthStorage clears session when local JWT is invalid', () {
    final src = File('lib/core/utils/auth_storage.dart').readAsStringSync();
    expect(src.contains('JwtLocalSession.isValidForLocalStartup'), isTrue);
    expect(src.contains('clearAll()'), isTrue);
    expect(src.contains('isLoggedIn'), isTrue);
  });

  test('AUTH8-09 logout contract remains (server then clear)', () {
    final src =
        File('lib/features/auth/data/auth_api.dart').readAsStringSync();
    expect(src.contains("ApiClient.post('/auth/logout')"), isTrue);
    expect(src.contains('AuthStorage.clearAll()'), isTrue);
    final postIdx = src.indexOf("ApiClient.post('/auth/logout')");
    final clearIdx = src.indexOf('AuthStorage.clearAll()');
    expect(clearIdx, greaterThan(postIdx));
  });

  test('AUTH8 consent screen also uses AuthStorage.isLoggedIn gate', () {
    final src =
        File('lib/features/legal/legal_screens.dart').readAsStringSync();
    expect(src.contains('AuthStorage.isLoggedIn()'), isTrue);
  });

  test('AUTH8-11 splash and jwt helper do not log token/JWT payloads', () {
    final splash =
        File('lib/features/splash/splash_screen.dart').readAsStringSync();
    final jwt =
        File('lib/core/utils/jwt_local_session.dart').readAsStringSync();
    final auth =
        File('lib/core/utils/auth_storage.dart').readAsStringSync();
    for (final src in [splash, jwt, auth]) {
      expect(src.contains('DebugLogger'), isFalse);
      expect(src.contains('print('), isFalse);
      expect(src.contains('debugPrint('), isFalse);
    }
  });
}
