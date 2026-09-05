import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/profile/data/user_api.dart';

void main() {
  final profileSrc = File(
          'lib/features/profile/presentation/profile_screen.dart')
      .readAsStringSync();
  final apiSrc =
      File('lib/features/profile/data/user_api.dart').readAsStringSync();

  test('LEGAL-S4-05 Export my data control is on Profile screen', () {
    expect(profileSrc.contains('Export my data'), isTrue);
    expect(profileSrc.contains('_exportMyData'), isTrue);
    expect(profileSrc.contains('UserApi.exportMyData'), isTrue);
    expect(profileSrc.contains('UserApi.shareDataExport'), isTrue);
    expect(profileSrc.contains('_exportingData'), isTrue);
  });

  test('LEGAL-S4-05 API uses authenticated data-export path', () {
    expect(apiSrc.contains('/users/me/data-export'), isTrue);
    expect(apiSrc.contains('exportMyData'), isTrue);
    expect(apiSrc.contains('shareDataExport'), isTrue);
    expect(UserApi.exportMyData, isA<Function>());
    expect(UserApi.shareDataExport, isA<Function>());
  });

  test('LEGAL-S4-05 success and failure UX present', () {
    expect(profileSrc.contains('Your data export is ready to save or share.'),
        isTrue);
    expect(profileSrc.contains('ErrorHandler.getMessage'), isTrue);
    expect(profileSrc.contains('CircularProgressIndicator'), isTrue);
  });

  test('LEGAL-S4-05 does not log export payload', () {
    expect(apiSrc.contains('DebugLogger'), isFalse);
    expect(apiSrc.contains('print('), isFalse);
    expect(apiSrc.contains('debugPrint'), isFalse);
    // Profile handler must not print payload either
    final exportFn = profileSrc.substring(
      profileSrc.indexOf('Future<void> _exportMyData'),
      profileSrc.indexOf('// ── Logout'),
    );
    expect(exportFn.contains('print('), isFalse);
    expect(exportFn.contains('debugPrint'), isFalse);
    expect(exportFn.contains('payload.toString'), isFalse);
  });
}
