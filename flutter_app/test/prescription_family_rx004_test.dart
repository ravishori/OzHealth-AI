import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/prescriptions/presentation/prescription_review_screen.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

void main() {
  final scanSrc = File(
          'lib/features/prescriptions/presentation/prescription_scan_screen.dart')
      .readAsStringSync();
  final reviewSrc = File(
          'lib/features/prescriptions/presentation/prescription_review_screen.dart')
      .readAsStringSync();
  final routerSrc = File('lib/core/router/app_router.dart').readAsStringSync();
  final detailSrc = File(
          'lib/features/prescriptions/presentation/prescription_detail_screen.dart')
      .readAsStringSync();

  Map<String, dynamic> ocrResult({
    required double? confidence,
    bool available = true,
    bool lowConfidence = false,
    bool needsReview = false,
    List<Map<String, dynamic>> medicines = const [],
  }) {
    return {
      'ocr': {
        'text': available ? 'synth' : '',
        'confidence': confidence,
        'confidence_scale': 'unit',
        'low_confidence': lowConfidence,
        'needs_review': needsReview,
        'available': available,
        'provider': 'test',
        'warnings': <String>[],
      },
      'summary': {
        'ocr_available': available,
        'low_confidence': lowConfidence,
        'needs_review': needsReview,
      },
      'medicines': medicines,
    };
  }

  Future<void> pumpReview(
    WidgetTester tester, {
    required Map<String, dynamic> ocrResult,
    int? initialFamilyMemberId,
    List<Map<String, dynamic>> familyMembers = const [],
  }) async {
    final tmp = Directory.systemTemp.createTempSync('rx004_');
    final file = File('${tmp.path}/synth.pdf');
    file.writeAsStringSync('%PDF-1.4 synth');
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.light(const AppThemeSettings()),
        home: PrescriptionReviewScreen(
          filePath: file.path,
          ocrResult: ocrResult,
          initialFamilyMemberId: initialFamilyMemberId,
          familyMembers: familyMembers,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  test('RX-FAMILY-FL-01 selector source Self + owned names', () {
    expect(scanSrc.contains("'Myself'"), isTrue);
    expect(reviewSrc.contains("'Myself'"), isTrue);
    expect(scanSrc.contains("m['name']"), isTrue);
    expect(reviewSrc.contains("m['name']"), isTrue);
    expect(scanSrc.contains("GET /family/") || scanSrc.contains("'/family/'"),
        isTrue);
  });

  test('RX-FAMILY-FL-02 does not expose arbitrary IDs as labels', () {
    expect(scanSrc.contains('Family member #\${'), isFalse);
    expect(reviewSrc.contains('family_member_id.toString()'), isFalse);
    expect(detailSrc.contains('Logged for:'), isTrue);
    expect(detailSrc.contains("return 'Family member'"), isTrue);
    expect(detailSrc.contains('familyMemberId.toString()'), isFalse);
  });

  test('RX-FAMILY-FL-03 self omits family_member_id', () {
    expect(reviewSrc.contains('if (_selectedFamilyMemberId != null)'), isTrue);
    expect(reviewSrc.contains("'family_member_id': _selectedFamilyMemberId"),
        isTrue);
  });

  test('RX-FAMILY-FL-04 owned selection produces family_member_id', () {
    expect(
      ownedPrescriptionFamilySelection(
        requestedId: 10,
        ownedMembers: [
          {'id': 10, 'name': 'Alex'},
        ],
      ),
      10,
    );
    expect(
      ownedPrescriptionFamilySelection(
        requestedId: 99,
        ownedMembers: [
          {'id': 10, 'name': 'Alex'},
        ],
      ),
      isNull,
    );
  });

  test('RX-FAMILY-FL-05 scan extra survives to review route', () {
    expect(scanSrc.contains("'familyMemberId': _selectedFamilyMemberId"),
        isTrue);
    expect(scanSrc.contains("'familyMembers': _familyMembers"), isTrue);
    expect(routerSrc.contains('initialFamilyMemberId: familyMemberId'), isTrue);
    expect(routerSrc.contains('familyMembers: familyMembers'), isTrue);
    expect(reviewSrc.contains('ownedPrescriptionFamilySelection'), isTrue);
  });

  test('RX-FAMILY-FL-06 confirm sends selected subject', () {
    expect(reviewSrc.contains("/prescriptions/confirm"), isTrue);
    expect(reviewSrc.contains("'family_member_id': _selectedFamilyMemberId"),
        isTrue);
  });

  test('RX-FAMILY-FL-07 OCR confirm gate remains intact', () {
    expect(reviewSrc.contains('_acknowledgeUncertainty'), isTrue);
    expect(reviewSrc.contains('_requiresReviewAcknowledgement'), isTrue);
    expect(scanSrc.contains("/prescriptions/ocr"), isTrue);
    expect(scanSrc.contains('persist'), isFalse);
  });

  test('RX-FAMILY-FL-08 scan family load failure stays on Self', () {
    expect(scanSrc.contains('_loadFamilyMembers'), isTrue);
    expect(scanSrc.contains('catch (_)'), isTrue);
    expect(scanSrc.contains('_loadingFamily = false'), isTrue);
  });

  testWidgets('RX-FAMILY-FL-01 widget Self and owned names', (tester) async {
    await pumpReview(
      tester,
      ocrResult: ocrResult(
        confidence: 0.95,
        medicines: [
          {
            'extracted_name': 'Panadol',
            'match_status': 'MATCHED',
            'candidates': [
              {'medicine_id': 1, 'name': 'Panadol'},
            ],
          },
        ],
      ),
      familyMembers: [
        {'id': 10, 'name': 'Alex'},
      ],
    );
    expect(find.text('Myself'), findsWidgets);
    expect(find.textContaining('saved for Myself'), findsOneWidget);
    await tester.tap(find.byKey(const Key('prescription_family_selector')));
    await tester.pumpAndSettle();
    expect(find.text('Alex'), findsWidgets);
  });

  testWidgets('RX-FAMILY-FL-04 widget owned id applied when owned',
      (tester) async {
    await pumpReview(
      tester,
      ocrResult: ocrResult(
        confidence: 0.95,
        medicines: [
          {
            'extracted_name': 'Panadol',
            'match_status': 'MATCHED',
            'candidates': [
              {'medicine_id': 1, 'name': 'Panadol'},
            ],
          },
        ],
      ),
      initialFamilyMemberId: 10,
      familyMembers: [
        {'id': 10, 'name': 'Alex'},
      ],
    );
    expect(find.textContaining('saved for Alex'), findsOneWidget);
  });

  testWidgets('RX-FAMILY-FL-04 unowned id falls back to Self', (tester) async {
    await pumpReview(
      tester,
      ocrResult: ocrResult(
        confidence: 0.95,
        medicines: [
          {
            'extracted_name': 'Panadol',
            'match_status': 'MATCHED',
            'candidates': [
              {'medicine_id': 1, 'name': 'Panadol'},
            ],
          },
        ],
      ),
      initialFamilyMemberId: 99,
      familyMembers: [
        {'id': 10, 'name': 'Alex'},
      ],
    );
    expect(find.textContaining('saved for Myself'), findsOneWidget);
  });

  testWidgets('RX-FAMILY-FL-07 high confidence Confirm & save still present',
      (tester) async {
    await pumpReview(
      tester,
      ocrResult: ocrResult(
        confidence: 0.95,
        medicines: [
          {
            'extracted_name': 'Panadol',
            'match_status': 'MATCHED',
            'candidates': [
              {'medicine_id': 1, 'name': 'Panadol'},
            ],
          },
        ],
      ),
    );
    expect(find.text('Confirm & save'), findsOneWidget);
    expect(find.text('Myself'), findsWidgets);
  });
}
