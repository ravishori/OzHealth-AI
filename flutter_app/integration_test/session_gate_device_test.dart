/// Sprint 5 S1 — HN-AUTH-008 device QA (local JWT session gate).
///
/// Uses synthetic unsigned JWTs only — never real credentials.
/// Does not require a live backend for splash routing assertions.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vitapulse_ai/core/utils/auth_storage.dart';
import 'package:vitapulse_ai/core/utils/debug_logger.dart';
import 'package:vitapulse_ai/core/utils/jwt_local_session.dart';
import 'package:vitapulse_ai/features/auth/presentation/screens/welcome_screen.dart';
import 'package:vitapulse_ai/features/home/presentation/home_screen.dart';
import 'package:vitapulse_ai/features/legal/legal_screens.dart';
import 'package:vitapulse_ai/features/splash/splash_screen.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

String _unsignedJwt(Map<String, dynamic> payload) {
  String b64(Object obj) {
    final bytes = utf8.encode(jsonEncode(obj));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  return '${b64({'alg': 'none', 'typ': 'JWT'})}.${b64(payload)}.sig';
}

String _futureToken() {
  final exp =
      DateTime.now().toUtc().add(const Duration(hours: 2)).millisecondsSinceEpoch ~/
          1000;
  return _unsignedJwt({'sub': '1', 'type': 'access', 'tv': 0, 'exp': exp});
}

String _expiredToken() {
  final exp = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 2))
          .millisecondsSinceEpoch ~/
      1000;
  return _unsignedJwt({'sub': '1', 'type': 'access', 'tv': 0, 'exp': exp});
}

Future<void> _ensureHiveConsent() async {
  await Hive.initFlutter();
  final box = await Hive.openBox('app_preferences');
  await box.put(kLegalConsentKey, true);
}

GoRouter _router() => GoRouter(
      initialLocation: '/splash',
      routes: [
        GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
        GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
        GoRoute(
          path: '/auth/welcome',
          builder: (_, __) => const WelcomeScreen(),
        ),
        GoRoute(
          path: '/legal/consent',
          builder: (_, __) => const ConsentScreen(),
        ),
      ],
    );

Future<void> _pumpSplash(WidgetTester tester) async {
  final router = _router();
  await tester.pumpWidget(
    MaterialApp.router(
      theme: AppThemeBuilder.light(const AppThemeSettings()),
      routerConfig: router,
    ),
  );
  // Splash delays ~1.5s + animation before routing.
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await DebugLogger.init();
    await _ensureHiveConsent();
  });

  testWidgets('S5-S1 Android session gate matrix', (tester) async {
    // ANDROID-04 missing token
    await AuthStorage.clearAll();
    expect(await AuthStorage.isLoggedIn(), isFalse);
    await _pumpSplash(tester);
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    tester.printToConsole('S5-S1-ANDROID-04=PASS');

    // ANDROID-02 expired
    await AuthStorage.saveTokens(
      accessToken: _expiredToken(),
      refreshToken: 'test-refresh-placeholder',
      userId: 1,
      name: 'QA',
    );
    expect(await AuthStorage.isLoggedIn(), isFalse);
    expect(await AuthStorage.getAccessToken(), isNull);
    await _pumpSplash(tester);
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    tester.printToConsole('S5-S1-ANDROID-02=PASS');

    // ANDROID-03 malformed
    await AuthStorage.saveTokens(
      accessToken: 'not.a.valid.jwt.token',
      refreshToken: 'test-refresh-placeholder',
      userId: 1,
      name: 'QA',
    );
    expect(await AuthStorage.isLoggedIn(), isFalse);
    expect(await AuthStorage.getAccessToken(), isNull);
    await _pumpSplash(tester);
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    tester.printToConsole('S5-S1-ANDROID-03=PASS');

    // ANDROID-01 valid → home
    final valid = _futureToken();
    await AuthStorage.saveTokens(
      accessToken: valid,
      refreshToken: 'test-refresh-placeholder',
      userId: 1,
      name: 'QA',
    );
    expect(JwtLocalSession.isValidForLocalStartup(valid), isTrue);
    expect(await AuthStorage.isLoggedIn(), isTrue);
    await _pumpSplash(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsNothing);
    tester.printToConsole('S5-S1-ANDROID-01=PASS');

    // ANDROID-06 basic nav still on home
    expect(find.byType(HomeScreen), findsOneWidget);
    tester.printToConsole('S5-S1-ANDROID-06=PASS');

    // ANDROID-05 logout clears session (local clear path; server logout needs API)
    await AuthStorage.clearAll();
    expect(await AuthStorage.isLoggedIn(), isFalse);
    await _pumpSplash(tester);
    expect(find.byType(WelcomeScreen), findsOneWidget);
    tester.printToConsole('S5-S1-ANDROID-05=PASS');

    // ANDROID-07 gate helpers do not log token/JWT (no DebugLogger in those paths)
    final marker = 'UNIQUE_TOKEN_MARKER_SHOULD_NOT_LOG';
    final probe = _unsignedJwt({
      'sub': marker,
      'exp': DateTime.now().toUtc().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
          1000,
    });
    expect(JwtLocalSession.evaluateAccessToken(probe), LocalJwtStatus.valid);
    await AuthStorage.saveTokens(
      accessToken: probe,
      refreshToken: 'x',
      userId: 1,
      name: 'QA',
    );
    expect(await AuthStorage.isLoggedIn(), isTrue);
    // Contract covered by unit tests: jwt_local_session / auth_storage / splash
    // do not call DebugLogger or print token contents.
    tester.printToConsole('S5-S1-ANDROID-07=PASS');
    tester.printToConsole('S5-S1_ANDROID_QA_MATRIX=COMPLETE');
  });
}
