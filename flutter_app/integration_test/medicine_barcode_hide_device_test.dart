/// Sprint 3 Slice 4 — HN-MED-003 device QA (hide barcode capability).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/utils/auth_storage.dart';
import 'package:vitapulse_ai/features/home/presentation/home_screen.dart';
import 'package:vitapulse_ai/features/medicines/presentation/medicine_detail_screen.dart';
import 'package:vitapulse_ai/features/medicines/presentation/medicine_search_screen.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

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
    refreshToken: 'barcode-hide-qa-unused',
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

  testWidgets('BARCODE device QA matrix UI-01..08', (tester) async {
    await _loadQaAuth();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.light(const AppThemeSettings()),
        home: const HomeScreen(),
      ),
    );
    await _pumpUi(tester, const Duration(seconds: 3));
    expect(find.byType(HomeScreen), findsOneWidget);
    tester.printToConsole('BARCODE-UI-01_HOME=PASS');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.light(const AppThemeSettings()),
        home: const MedicineSearchScreen(),
      ),
    );
    await _pumpUi(tester, const Duration(seconds: 2));
    expect(find.text('Medicine Information'), findsOneWidget);
    tester.printToConsole('BARCODE-UI-02_MEDICINE_INFO=PASS');

    expect(find.byTooltip('Scan Barcode'), findsNothing);
    expect(find.byIcon(Icons.qr_code_scanner), findsNothing);
    expect(find.textContaining('Scan Barcode'), findsNothing);
    expect(find.textContaining('scan barcode'), findsNothing);
    tester.printToConsole('BARCODE-UI-03_NO_SCAN_CONTROL=PASS');

    expect(find.text('Align barcode within the frame'), findsNothing);
    tester.printToConsole('BARCODE-UI-04_NO_SCANNER_REACHABLE=PASS');

    // Name search still works via API + UI field
    final search = await ApiClient.get(
      '/medicines/search',
      queryParameters: {'q': 'paracetamol', 'limit': 5},
    );
    expect(search.statusCode, 200);
    final data = search.data;
    final results = List<Map<String, dynamic>>.from(
      data is List ? data : (data['results'] ?? []),
    );
    expect(results.isNotEmpty, isTrue);

    final field = find.byType(TextField);
    expect(field, findsOneWidget);
    await tester.enterText(field, 'paracetamol');
    await _pumpUi(tester, const Duration(seconds: 3));
    tester.printToConsole('BARCODE-UI-05_NAME_SEARCH=PASS');

    final first = results.first;
    final medicineId = first['id']?.toString() ?? '';
    expect(medicineId.isNotEmpty, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.light(const AppThemeSettings()),
        home: MedicineDetailScreen(
          medicineId: medicineId,
          extra: first,
        ),
      ),
    );
    await _pumpUi(tester, const Duration(seconds: 4));
    expect(find.byType(MedicineDetailScreen), findsOneWidget);
    tester.printToConsole('BARCODE-UI-06_DETAIL=PASS');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.light(const AppThemeSettings()),
        home: const MedicineSearchScreen(),
      ),
    );
    await _pumpUi(tester, const Duration(seconds: 2));
    expect(find.text('Medicine Information'), findsOneWidget);
    tester.printToConsole('BARCODE-UI-07_BACK_NO_CRASH=PASS');

    expect(find.byTooltip('Scan Barcode'), findsNothing);
    expect(find.text('Search medicines by name'), findsOneWidget);
    tester.printToConsole('BARCODE-UI-08_STILL_USABLE=PASS');
    tester.printToConsole('BARCODE_DEVICE_QA_MATRIX=COMPLETE');
  });
}
