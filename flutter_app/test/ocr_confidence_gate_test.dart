import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/prescriptions/data/ocr_confidence.dart';
import 'package:vitapulse_ai/features/prescriptions/presentation/prescription_review_screen.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

void main() {
  group('OcrConfidence unit contract', () {
    test('OCR-FLUTTER-01 normalize 95 → 0.95 and display percent', () {
      expect(OcrConfidence.normalize(95), 0.95);
      expect(OcrConfidence.normalize(0.95), 0.95);
      expect(OcrConfidence.formatPercent(0.95), '95%');
      expect(OcrConfidence.ocrReviewThreshold, 0.60);
    });

    test('OCR-FLUTTER-02 high confidence not low', () {
      expect(OcrConfidence.isLowConfidence(0.95), isFalse);
      expect(OcrConfidence.isLowConfidence(0.80), isFalse);
      expect(OcrConfidence.isLowConfidence(0.60), isFalse);
    });

    test('OCR-FLUTTER-03 low confidence requires review', () {
      expect(OcrConfidence.isLowConfidence(0.59), isTrue);
      expect(OcrConfidence.isLowConfidence(0.20), isTrue);
    });

    test('OCR-FLUTTER-06 invalid/missing fails closed', () {
      expect(OcrConfidence.normalize(null), isNull);
      expect(OcrConfidence.normalize('x'), isNull);
      expect(OcrConfidence.isLowConfidence(null), isTrue);
      expect(OcrConfidence.formatPercent(null), isNull);
    });
  });

  group('Review screen confidence gate', () {
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
          'matched_count': medicines
              .where((m) => m['match_status'] == 'MATCHED')
              .length,
          'unmatched_count': medicines
              .where((m) => m['match_status'] != 'MATCHED')
              .length,
        },
        'medicines': medicines,
      };
    }

    Future<void> pumpReview(
      WidgetTester tester,
      Map<String, dynamic> ocrResult,
    ) async {
      final tmp = Directory.systemTemp.createTempSync('ocr003_');
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
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('OCR-FLUTTER-01 confidence displayed as percent',
        (tester) async {
      await pumpReview(
        tester,
        ocrResult(
          confidence: 0.95,
          medicines: [
            {
              'extracted_name': 'Panadol',
              'extracted_strength': '500 mg',
              'extracted_frequency': 'BD',
              'match_status': 'MATCHED',
              'candidates': [
                {'medicine_id': 1, 'name': 'Panadol', 'ARTG': 'A1'},
              ],
            },
          ],
        ),
      );
      expect(find.textContaining('OCR confidence: 95%'), findsOneWidget);
    });

    testWidgets('OCR-FLUTTER-03 low confidence shows review banner',
        (tester) async {
      await pumpReview(
        tester,
        ocrResult(
          confidence: 0.20,
          lowConfidence: true,
          needsReview: true,
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
      expect(
        find.textContaining('Low or missing OCR confidence'),
        findsOneWidget,
      );
      expect(find.text('Review & save'), findsOneWidget);
      expect(find.text('Needs review'), findsWidgets);
    });

    testWidgets('OCR-FLUTTER-04 confirm gate shows acknowledgement dialog',
        (tester) async {
      await pumpReview(
        tester,
        ocrResult(
          confidence: 0.20,
          lowConfidence: true,
          needsReview: true,
          medicines: [
            {
              'extracted_name': 'Panadol',
              'match_status': 'UNMATCHED',
              'candidates': <Map<String, dynamic>>[],
            },
          ],
        ),
      );
      await tester.tap(find.text('Review & save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Review required'), findsOneWidget);
      expect(find.text('I have reviewed — save'), findsOneWidget);
      // Cancel acknowledgement — must not proceed to save network call
      await tester.tap(find.text('Go back'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Review required'), findsNothing);
    });

    testWidgets('OCR-FLUTTER-05 high confidence uses Confirm & save',
        (tester) async {
      await pumpReview(
        tester,
        ocrResult(
          confidence: 0.95,
          lowConfidence: false,
          needsReview: false,
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
      expect(find.textContaining('Low or missing OCR confidence'), findsNothing);
    });

    testWidgets('OCR-FLUTTER-07 OCR unavailable messaging', (tester) async {
      await pumpReview(
        tester,
        ocrResult(
          confidence: null,
          available: false,
          lowConfidence: true,
          needsReview: true,
        ),
      );
      expect(find.textContaining('OCR unavailable'), findsOneWidget);
    });

    testWidgets('OCR-FLUTTER-08 catalogue candidate Use control present',
        (tester) async {
      await pumpReview(
        tester,
        ocrResult(
          confidence: 0.95,
          medicines: [
            {
              'extracted_name': 'Amoxil',
              'match_status': 'MATCHED',
              'candidates': [
                {'medicine_id': 7, 'name': 'Amoxil Cap', 'ARTG': 'X'},
              ],
            },
          ],
        ),
      );
      expect(find.text('Catalogue candidates'), findsOneWidget);
      expect(find.text('Use'), findsOneWidget);
    });
  });

  test('OCR-FLUTTER-09 confirm-before-save contract in scan source', () {
    final scan = File(
            'lib/features/prescriptions/presentation/prescription_scan_screen.dart')
        .readAsStringSync();
    expect(scan.contains("/prescriptions/ocr"), isTrue);
    expect(scan.contains('persist'), isFalse);
    expect(scan.contains('/prescriptions/review'), isTrue);
    final review = File(
            'lib/features/prescriptions/presentation/prescription_review_screen.dart')
        .readAsStringSync();
    expect(review.contains("/prescriptions/confirm"), isTrue);
    expect(review.contains('_acknowledgeUncertainty'), isTrue);
    expect(review.contains('OcrConfidence'), isTrue);
  });
}
