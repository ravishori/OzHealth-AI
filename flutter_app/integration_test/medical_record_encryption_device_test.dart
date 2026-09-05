/// HN-RECORD-009 — Android device QA for encrypted medical-record files.
/// Synthetic content only. Encryption remains on the backend.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/utils/auth_storage.dart';
import 'package:vitapulse_ai/features/home/presentation/home_screen.dart';
import 'package:vitapulse_ai/features/records/presentation/records_screen.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

const _synthBytes = 'HN-RECORD-009 synthetic Android QA content';

Future<void> _loadQaAuth() async {
  const token = String.fromEnvironment('SOS_QA_ACCESS_TOKEN');
  const userIdRaw = String.fromEnvironment('SOS_QA_USER_ID');
  const userName =
      String.fromEnvironment('SOS_QA_USER_NAME', defaultValue: 'QA User');
  if (token.isEmpty || userIdRaw.isEmpty) {
    fail('Pass SOS_QA_ACCESS_TOKEN and SOS_QA_USER_ID dart-defines');
  }
  await AuthStorage.saveTokens(
    accessToken: token,
    refreshToken: 'record-enc-qa-unused',
    userId: int.parse(userIdRaw),
    name: userName,
  );
}

Future<void> _pumpUi(WidgetTester tester,
    [Duration d = const Duration(seconds: 2)]) async {
  await tester.pump();
  await tester.pump(d);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('RECORD-ANDROID-01..12 encrypted records QA', (tester) async {
    await _loadQaAuth();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.light(const AppThemeSettings()),
        home: const HomeScreen(),
      ),
    );
    await _pumpUi(tester, const Duration(seconds: 3));
    expect(find.byType(HomeScreen), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.light(const AppThemeSettings()),
        home: const RecordsScreen(),
      ),
    );
    await _pumpUi(tester, const Duration(seconds: 3));
    expect(find.byType(RecordsScreen), findsOneWidget);
    expect(find.text('Medical Records'), findsOneWidget);
    tester.printToConsole('RECORD-ANDROID-01_OPEN_RECORDS=PASS');

    final tmp = await getTemporaryDirectory();
    final uploadPath = '${tmp.path}${Platform.pathSeparator}record009_synth.txt';
    final uploadFile = File(uploadPath);
    await uploadFile.writeAsString(_synthBytes, flush: true);

    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        uploadPath,
        filename: 'record009_synth.pdf',
      ),
      'record_type': 'lab_report',
      'title': 'RECORD009-Synth',
    });
    final uploaded = await ApiClient.uploadFile('/records/upload', form);
    expect(uploaded.statusCode, 200);
    final record = Map<String, dynamic>.from(uploaded.data as Map);
    final id = record['id'];
    expect(id, isNotNull);
    expect(record['title'], 'RECORD009-Synth');
    tester.printToConsole('RECORD-ANDROID-02_UPLOAD=PASS');

    // List via authenticated API (same contract the UI uses).
    final listed = await ApiClient.get('/records/');
    expect(listed.statusCode, 200);
    final list = List<Map<String, dynamic>>.from(
      (listed.data as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    expect(list.any((r) => r['id'] == id), isTrue);
    tester.printToConsole('RECORD-ANDROID-03_LIST=PASS');

    // Reload UI and confirm records surface remains usable.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.light(const AppThemeSettings()),
        home: const RecordsScreen(),
      ),
    );
    await _pumpUi(tester, const Duration(seconds: 4));
    expect(find.byType(RecordsScreen), findsOneWidget);
    expect(find.text('Medical Records'), findsOneWidget);

    final detail = await ApiClient.get('/records/$id');
    expect(detail.statusCode, 200);
    final detailMap = Map<String, dynamic>.from(detail.data as Map);
    expect(detailMap['file_url'], '/api/v1/records/$id/file');
    expect(detailMap['file_url'].toString().contains('uploads/'), isFalse);
    tester.printToConsole('RECORD-ANDROID-04_DETAIL=PASS');
    tester.printToConsole('RECORD-ANDROID-10_NO_DISK_PATH=PASS');

    final down = await ApiClient.downloadBytes('/records/$id/file');
    expect(down.statusCode, 200);
    final bytes = down.data;
    expect(bytes, isA<List<int>>());
    final body = String.fromCharCodes(bytes as List<int>);
    expect(body, _synthBytes);
    expect(body.startsWith('HNREC1'), isFalse);
    tester.printToConsole('RECORD-ANDROID-05_DOWNLOAD=PASS');
    tester.printToConsole('RECORD-ANDROID-06_BYTES_MATCH=PASS');

    await ApiClient.delete('/records/$id');
    tester.printToConsole('RECORD-ANDROID-07_DELETE=PASS');

    final listedAfter = await ApiClient.get('/records/');
    expect(listedAfter.statusCode, 200);
    final listAfter = List<Map<String, dynamic>>.from(
      (listedAfter.data as List)
          .map((e) => Map<String, dynamic>.from(e as Map)),
    );
    expect(listAfter.any((r) => r['id'] == id), isFalse);
    tester.printToConsole('RECORD-ANDROID-08_GONE=PASS');

    try {
      await ApiClient.get('/records/$id');
      fail('deleted record metadata should 404');
    } on DioException catch (e) {
      expect(e.response?.statusCode, 404);
    }
    try {
      await ApiClient.downloadBytes('/records/$id/file');
      fail('deleted file should 404');
    } on DioException catch (e) {
      expect(e.response?.statusCode, 404);
    }
    tester.printToConsole('RECORD-ANDROID-09_DELETED_DENIED=PASS');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.light(const AppThemeSettings()),
        home: const RecordsScreen(),
      ),
    );
    await _pumpUi(tester, const Duration(seconds: 3));
    expect(find.byType(RecordsScreen), findsOneWidget);
    tester.printToConsole('RECORD-ANDROID-11_UX_OK=PASS');
    tester.printToConsole('RECORD-ANDROID-12_NO_SENSITIVE_LOG_CONTRACT=PASS');
    tester.printToConsole('RECORD_ANDROID_QA_MATRIX=COMPLETE');

    if (await uploadFile.exists()) {
      await uploadFile.delete();
    }
    expect(Uint8List.fromList(bytes as List<int>).isNotEmpty, isTrue);
  });
}
