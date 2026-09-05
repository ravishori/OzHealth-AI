import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/records/data/records_api.dart';

/// HN-RECORD-009 Flutter contracts — encryption stays on backend.
void main() {
  final screenSrc =
      File('lib/features/records/presentation/records_screen.dart')
          .readAsStringSync();
  final uploadSrc =
      File('lib/features/records/presentation/upload_record_screen.dart')
          .readAsStringSync();
  final apiSrc =
      File('lib/features/records/data/records_api.dart').readAsStringSync();
  final providerSrc =
      File('lib/features/records/providers/records_provider.dart')
          .readAsStringSync();

  test('RECORD-UI-01 Records screen loads records via API', () {
    expect(screenSrc.contains("_loadRecords"), isTrue);
    expect(screenSrc.contains("ApiClient.get('/records/'"), isTrue);
    expect(providerSrc.contains('RecordsApi.getRecords'), isTrue);
  });

  test('RECORD-UI-02 Upload continues to POST /records/upload', () {
    expect(apiSrc.contains("/records/upload"), isTrue);
    expect(apiSrc.contains('uploadRecord'), isTrue);
    expect(uploadSrc.contains("/records/upload"), isTrue);
    expect(RecordsApi.uploadRecord, isA<Function>());
  });

  test('RECORD-UI-03 Open/download uses GET /records/{id}/file', () {
    expect(screenSrc.contains("downloadBytes('/records/\$id/file')"), isTrue);
  });

  test('RECORD-UI-04 Returned bytes go to temp file / external viewer', () {
    expect(screenSrc.contains('getTemporaryDirectory'), isTrue);
    expect(screenSrc.contains('writeAsBytes'), isTrue);
    expect(screenSrc.contains('launchUrl'), isTrue);
    expect(screenSrc.contains('LaunchMode.externalApplication'), isTrue);
  });

  test('RECORD-UI-05 Delete continues to DELETE /records/{id}', () {
    expect(screenSrc.contains("ApiClient.delete('/records/\$id')"), isTrue);
    expect(apiSrc.contains('deleteRecord'), isTrue);
    expect(providerSrc.contains('RecordsApi.deleteRecord'), isTrue);
  });

  test('RECORD-UI-06 No raw filesystem storage path exposed in Flutter', () {
    expect(screenSrc.contains('LOCAL_UPLOAD_DIR'), isFalse);
    expect(screenSrc.contains('uploads/records'), isFalse);
    expect(apiSrc.contains('uploads/records'), isFalse);
    // API returns authenticated download URL pattern, not disk path
    expect(screenSrc.contains('_viewRecordFile'), isTrue);
  });

  test('RECORD-UI-07 Safe error when download/decrypt fails', () {
    expect(
      screenSrc.contains(
          'Could not open file. Access denied or missing.'),
      isTrue,
    );
    // No Flutter-side crypto
    expect(screenSrc.contains('encrypt'), isFalse);
    expect(screenSrc.contains('decrypt'), isFalse);
    expect(apiSrc.contains('encrypt'), isFalse);
    expect(apiSrc.contains('decrypt'), isFalse);
  });
}
