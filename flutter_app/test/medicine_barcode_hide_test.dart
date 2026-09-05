import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/medicines/data/medicine_api.dart';
import 'package:vitapulse_ai/features/medicines/presentation/medicine_detail_screen.dart';
import 'package:vitapulse_ai/features/medicines/presentation/medicine_search_screen.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

void main() {
  test('MED-BARCODE-01/02 Medicine Information does not expose Scan Barcode',
      () {
    final src = File(
            'lib/features/medicines/presentation/medicine_search_screen.dart')
        .readAsStringSync();
    expect(src.contains('Scan Barcode'), isFalse);
    expect(src.contains('scan barcode'), isFalse);
    expect(src.contains('qr_code_scanner'), isFalse);
    expect(src.contains('_BarcodeScannerPage'), isFalse);
    expect(src.contains('_openBarcodeScanner'), isFalse);
    expect(src.contains('MobileScanner'), isFalse);
    expect(src.contains('mobile_scanner'), isFalse);
  });

  test('MED-BARCODE-03 UI does not call /medicines/barcode', () {
    final searchSrc = File(
            'lib/features/medicines/presentation/medicine_search_screen.dart')
        .readAsStringSync();
    final apiSrc =
        File('lib/features/medicines/data/medicine_api.dart').readAsStringSync();
    expect(searchSrc.contains('/medicines/barcode'), isFalse);
    expect(apiSrc.contains('/medicines/barcode'), isFalse);
    expect(apiSrc.contains('getByBarcode'), isFalse);
  });

  test('MED-BARCODE-04/07 Medicine search + API surface remain', () {
    final src = File(
            'lib/features/medicines/presentation/medicine_search_screen.dart')
        .readAsStringSync();
    expect(src.contains('/medicines/search'), isTrue);
    expect(src.contains('Medicine Information'), isTrue);
    expect(src.contains('Search medicines by name'), isTrue);
    expect(MedicineApi.search, isA<Function>());
    expect(MedicineApi.getMedicine, isA<Function>());
  });

  test('MED-BARCODE-05 Medicine detail screen remains present', () {
    final src = File(
            'lib/features/medicines/presentation/medicine_detail_screen.dart')
        .readAsStringSync();
    expect(src.contains('class MedicineDetailScreen'), isTrue);
    expect(MedicineDetailScreen, isA<Type>());
  });

  test('MED-BARCODE-06 MedicineApi still uses authenticated ApiClient paths',
      () {
    final src =
        File('lib/features/medicines/data/medicine_api.dart').readAsStringSync();
    expect(src.contains('ApiClient.get'), isTrue);
    expect(src.contains('/medicines/search'), isTrue);
    expect(src.contains('/medicines/\$id') || src.contains("/medicines/\$id"),
        isTrue);
  });

  testWidgets('MED-BARCODE-01 widget: no barcode AppBar action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.light(const AppThemeSettings()),
        home: const MedicineSearchScreen(),
      ),
    );
    await tester.pump();
    expect(find.text('Medicine Information'), findsOneWidget);
    expect(find.byTooltip('Scan Barcode'), findsNothing);
    expect(find.byIcon(Icons.qr_code_scanner), findsNothing);
    expect(find.textContaining('scan barcode'), findsNothing);
    expect(find.text('Search medicines by name'), findsOneWidget);
  });
}
