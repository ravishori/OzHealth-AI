import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vitapulse_ai/features/lab_analysis/presentation/lab_analysis_screen.dart';
import 'package:vitapulse_ai/features/legal/legal_copy.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppThemeBuilder.light(const AppThemeSettings()),
    home: child,
  );
}

void _setLargeSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Map<String, dynamic> _okPayload({
  bool lowConfidence = false,
  String? referenceRange = '130-175 g/L',
  String value = '110',
}) {
  return {
    'record_id': 42,
    'user_confirmed': false,
    'review_required': true,
    'is_clinician_verified': false,
    'guidance_type': 'informational',
    'is_diagnosis': false,
    'message':
        'Please review the extracted information against your original report.',
    'analysis': {
      'test_name': 'Full Blood Count',
      'test_date': '2026-01-15',
      'results': [
        {
          'parameter': 'Haemoglobin',
          'value': value,
          'unit': 'g/L',
          'original_value': value,
          'original_unit': 'g/L',
          'reference_range':
              referenceRange ?? 'Reference range not provided',
          'original_reference_range': referenceRange,
          'status': 'low',
          'plain_explanation':
              'Haemoglobin carries oxygen in the blood.',
          'action_needed': true,
          'review_required': true,
          'missing_fields': <String>[],
        }
      ],
      'abnormal_count': 1,
      'summary': 'Review extracted values against your report.',
      'recommendations': ['Discuss with your GP.'],
      'disclaimer': LegalCopy.labBanner,
      'review_required': true,
      'user_confirmed': false,
      'is_clinician_verified': false,
      'is_diagnosis': false,
      'ocr_low_confidence': lowConfidence,
      'ocr': {'low_confidence': lowConfidence, 'confidence': 0.4},
    },
  };
}

void main() {
  final screenSrc = File(
    'lib/features/lab_analysis/presentation/lab_analysis_screen.dart',
  ).readAsStringSync();

  testWidgets('LAB-F01 lab analysis screen renders', (tester) async {
    await tester.pumpWidget(_wrap(const LabAnalysisScreen()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lab_analysis_screen')), findsOneWidget);
    expect(find.text('Lab Report Review'), findsOneWidget);
    expect(find.byKey(const Key('lab_safety_banner')), findsOneWidget);
  });

  testWidgets('LAB-F02 camera/gallery selection via abstraction',
      (tester) async {
    _setLargeSurface(tester);
    XFile? picked;
    await tester.pumpWidget(
      _wrap(
        LabAnalysisScreen(
          pickImage: (source) async {
            picked = XFile('/tmp/synthetic_lab.png');
            return picked;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lab_gallery_button')));
    await tester.pumpAndSettle();
    expect(picked, isNotNull);
    expect(find.byKey(const Key('lab_selected_preview')), findsOneWidget);
  });

  testWidgets('LAB-F03 selected image displayed before analysis',
      (tester) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(
      _wrap(
        LabAnalysisScreen(
          initialFile: File('/tmp/synthetic_lab.png'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lab_selected_preview')), findsOneWidget);
    expect(find.byKey(const Key('lab_results_section')), findsNothing);
  });

  testWidgets('LAB-F04 submit shows loading state', (tester) async {
    _setLargeSurface(tester);
    var release = false;
    await tester.pumpWidget(
      _wrap(
        LabAnalysisScreen(
          initialFile: File('/tmp/synthetic_lab.png'),
          analyzeFile: (file) async {
            while (!release) {
              await Future<void>.delayed(const Duration(milliseconds: 20));
            }
            return _okPayload();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lab_analyze_button')));
    await tester.pump();
    expect(find.text('Extracting report...'), findsOneWidget);
    release = true;
    await tester.pumpAndSettle();
  });

  testWidgets('LAB-F05 duplicate submission prevented', (tester) async {
    _setLargeSurface(tester);
    var calls = 0;
    var release = false;
    await tester.pumpWidget(
      _wrap(
        LabAnalysisScreen(
          initialFile: File('/tmp/synthetic_lab.png'),
          analyzeFile: (file) async {
            calls += 1;
            while (!release) {
              await Future<void>.delayed(const Duration(milliseconds: 20));
            }
            return _okPayload();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final btn = find.byKey(const Key('lab_analyze_button'));
    await tester.tap(btn);
    await tester.pump();
    await tester.tap(btn);
    await tester.pump();
    expect(calls, 1);
    release = true;
    await tester.pumpAndSettle();
  });

  testWidgets('LAB-F06 successful analysis displays extracted data',
      (tester) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(
      _wrap(
        LabAnalysisScreen(
          initialFile: File('/tmp/synthetic_lab.png'),
          analyzeFile: (_) async => _okPayload(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lab_analyze_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lab_results_section')), findsOneWidget);
    expect(find.textContaining('Haemoglobin'), findsWidgets);
    expect(find.textContaining('Reported result: 110'), findsOneWidget);
  });

  testWidgets('LAB-F07 review/confirmation gate displayed', (tester) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(
      _wrap(
        LabAnalysisScreen(
          initialFile: File('/tmp/synthetic_lab.png'),
          analyzeFile: (_) async => _okPayload(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lab_analyze_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lab_review_gate')), findsOneWidget);
    expect(find.byKey(const Key('lab_confirm_button')), findsOneWidget);
    expect(
      find.textContaining(
          'Please review the extracted information against your original report'),
      findsWidgets,
    );
  });

  testWidgets('LAB-F08 user can reject extraction', (tester) async {
    _setLargeSurface(tester);
    var rejected = false;
    await tester.pumpWidget(
      _wrap(
        LabAnalysisScreen(
          initialFile: File('/tmp/synthetic_lab.png'),
          analyzeFile: (_) async => _okPayload(),
          rejectAnalysis: (id) async {
            rejected = true;
            return {'discarded': true, 'record_id': id};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lab_analyze_button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('lab_reject_button')));
    await tester.tap(find.byKey(const Key('lab_reject_button')));
    await tester.pumpAndSettle();
    expect(rejected, isTrue);
    expect(find.byKey(const Key('lab_results_section')), findsNothing);
  });

  testWidgets('LAB-F09 user can confirm valid extraction', (tester) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(
      _wrap(
        LabAnalysisScreen(
          initialFile: File('/tmp/synthetic_lab.png'),
          analyzeFile: (_) async => _okPayload(),
          confirmAnalysis: (id) async => {
            ..._okPayload(),
            'record_id': id,
            'user_confirmed': true,
            'review_required': false,
            'analysis': {
              ..._okPayload()['analysis'] as Map<String, dynamic>,
              'user_confirmed': true,
              'review_required': false,
            },
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lab_analyze_button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('lab_confirm_button')));
    await tester.tap(find.byKey(const Key('lab_confirm_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lab_confirmed_banner')), findsOneWidget);
    expect(find.byKey(const Key('lab_review_gate')), findsNothing);
  });

  testWidgets('LAB-F10 validation / empty selection error', (tester) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(_wrap(const LabAnalysisScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lab_analyze_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lab_error_banner')), findsOneWidget);
    expect(find.textContaining('select a lab report'), findsOneWidget);
  });

  testWidgets('LAB-F11 analysis failure shows safe retry', (tester) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(
      _wrap(
        LabAnalysisScreen(
          initialFile: File('/tmp/synthetic_lab.png'),
          analyzeFile: (_) async {
            throw Exception('backend down');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lab_analyze_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lab_error_banner')), findsOneWidget);
    expect(find.byKey(const Key('lab_retry_button')), findsOneWidget);
    expect(find.byKey(const Key('lab_results_section')), findsNothing);
  });

  testWidgets('LAB-F12 non-diagnostic disclaimer visible', (tester) async {
    await tester.pumpWidget(_wrap(const LabAnalysisScreen()));
    await tester.pumpAndSettle();
    expect(find.textContaining(LegalCopy.labBanner.substring(0, 40)),
        findsWidgets);
    expect(screenSrc.contains('does not diagnose'), isTrue);
    expect(screenSrc.toLowerCase().contains('ai doctor'), isFalse);
  });

  testWidgets('LAB-F13 no fabricated reference range displayed',
      (tester) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(
      _wrap(
        LabAnalysisScreen(
          initialFile: File('/tmp/synthetic_lab.png'),
          analyzeFile: (_) async => _okPayload(referenceRange: null),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lab_analyze_button')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Reference range not provided'),
      findsOneWidget,
    );
  });

  testWidgets('LAB-F14 original reported values displayed', (tester) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(
      _wrap(
        LabAnalysisScreen(
          initialFile: File('/tmp/synthetic_lab.png'),
          analyzeFile: (_) async => _okPayload(value: '110'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lab_analyze_button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Reported result: 110 g/L'), findsOneWidget);
    expect(
      find.textContaining('Reported reference range: 130-175 g/L'),
      findsOneWidget,
    );
  });

  test('LAB-F15 no diagnostic/prescribing language in normal UI source', () {
    final lower = screenSrc.toLowerCase();
    expect(lower.contains('diagnosis confirmed'), isFalse);
    expect(lower.contains('you have '), isFalse);
    expect(lower.contains('start taking'), isFalse);
    expect(lower.contains('stop taking'), isFalse);
    expect(lower.contains('all values normal'), isFalse);
    expect(screenSrc.contains('Review required'), isTrue);
    expect(screenSrc.contains('informational'), isTrue);
  });
}
