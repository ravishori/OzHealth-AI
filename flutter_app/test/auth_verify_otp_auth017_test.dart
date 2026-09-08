import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/auth/presentation/screens/otp_screen.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

Widget _theme(Widget child) {
  return MaterialApp(
    theme: AppThemeBuilder.light(const AppThemeSettings()),
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AUTH17-FL client verifyOtp posts purpose-bound body to /auth/verify-otp', () {
    final src =
        File('lib/features/auth/data/auth_api.dart').readAsStringSync();
    expect(src.contains("ApiClient.post('/auth/verify-otp'"), isTrue);
    expect(src.contains("'otp_code': otpCode"), isTrue);
    expect(src.contains("'purpose': purpose"), isTrue);
    expect(src.contains('static Future<Map<String, dynamic>> verifyOtp'), isTrue);
    // Must not claim client-side validity / token issuance.
    expect(src.contains('access_token'), isTrue); // login/register only
    final verifyIdx = src.indexOf('static Future<Map<String, dynamic>> verifyOtp');
    final verifyBlock = src.substring(verifyIdx, src.indexOf('static Future<LogoutOutcome> logout'));
    expect(verifyBlock.contains('access_token'), isFalse);
    expect(verifyBlock.contains('AuthStorage.saveTokens'), isFalse);
  });

  test('AUTH17-FL session paths remain login/register (token issuance)', () {
    final otpUi =
        File('lib/features/auth/presentation/screens/otp_screen.dart')
            .readAsStringSync();
    expect(otpUi.contains('AuthApi.login'), isTrue);
    expect(otpUi.contains('AuthApi.register'), isTrue);
    // Standalone verify is API-level; login/register consume OTP + issue tokens.
    expect(otpUi.contains('AuthApi.verifyOtp'), isFalse);
  });

  testWidgets('AUTH17-FL-01 OTP entry screen renders', (tester) async {
    await tester.pumpWidget(
      _theme(
        const OtpScreen(
          identifier: 'auth17@example.com',
          purpose: 'auth',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Enter 6-Digit Code'), findsOneWidget);
    expect(find.text('Verify Code'), findsOneWidget);
  });

  testWidgets('AUTH17-FL-02 OTP input accepts digits only (6 boxes)', (tester) async {
    await tester.pumpWidget(
      _theme(
        const OtpScreen(
          identifier: 'auth17@example.com',
          purpose: 'auth',
        ),
      ),
    );
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(6));
    await tester.enterText(fields.at(0), 'a');
    await tester.pump();
    expect(tester.widget<TextFormField>(fields.at(0)).controller?.text ?? '', '');
    await tester.enterText(fields.at(0), '4');
    await tester.pump();
    expect(tester.widget<TextFormField>(fields.at(0)).controller?.text, '4');
  });

  testWidgets('AUTH17-FL-06 loading state blocks duplicate Verify press', (tester) async {
    final src =
        File('lib/features/auth/presentation/screens/otp_screen.dart')
            .readAsStringSync();
    expect(src.contains('if (_loading) return;'), isTrue);
    expect(src.contains('loading: _loading'), isTrue);
  });

  testWidgets('AUTH17-FL-07 resend obeys cooldown UX', (tester) async {
    await tester.pumpWidget(
      _theme(
        const OtpScreen(
          identifier: 'auth17@example.com',
          purpose: 'auth',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Resend OTP in'), findsOneWidget);
    final src =
        File('lib/features/auth/presentation/screens/otp_screen.dart')
            .readAsStringSync();
    expect(src.contains('if (_secondsLeft > 0) return;'), isTrue);
  });

  testWidgets('AUTH17-FL-08 OTP controls have accessibility semantics', (tester) async {
    await tester.pumpWidget(
      _theme(
        const OtpScreen(
          identifier: '+61400000017',
          purpose: 'auth',
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 1; i <= 6; i++) {
      expect(find.bySemanticsLabel('OTP digit $i'), findsOneWidget);
    }
  });

  test('AUTH17-FL-03/04 safe error UX contracts present', () {
    final src =
        File('lib/features/auth/presentation/screens/otp_screen.dart')
            .readAsStringSync();
    expect(src.contains('AppErrorBanner'), isTrue);
    expect(src.contains('ErrorHandler.getMessage'), isTrue);
    expect(src.contains('_triggerShake'), isTrue);
  });
}
