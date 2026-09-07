import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/core/config/app_env.dart';

void main() {
  group('AppEnv.normalizeApiBaseUrl', () {
    test('appends /api/v1 when missing', () {
      expect(
        AppEnv.normalizeApiBaseUrl(
          'https://aihealthcompanion-api-staging.azurewebsites.net',
        ),
        'https://aihealthcompanion-api-staging.azurewebsites.net/api/v1',
      );
    });

    test('strips trailing slash before appending', () {
      expect(
        AppEnv.normalizeApiBaseUrl('https://example.azurewebsites.net/'),
        'https://example.azurewebsites.net/api/v1',
      );
    });

    test('keeps existing /api/v1 suffix', () {
      expect(
        AppEnv.normalizeApiBaseUrl('https://example.azurewebsites.net/api/v1'),
        'https://example.azurewebsites.net/api/v1',
      );
    });

    test('empty stays empty', () {
      expect(AppEnv.normalizeApiBaseUrl(''), '');
      expect(AppEnv.normalizeApiBaseUrl('   '), '');
    });
  });

  test('hasInjectedApiBase tracks compile-time define presence contract', () {
    // Without --dart-define in this test process, default is empty.
    expect(AppEnv.apiBaseUrl, isA<String>());
    expect(AppEnv.hasInjectedApiBase, AppEnv.apiBaseUrl.trim().isNotEmpty);
  });
}
