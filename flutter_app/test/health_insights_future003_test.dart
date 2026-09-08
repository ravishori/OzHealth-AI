import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/health_insights/presentation/health_insights_screen.dart';
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

Map<String, dynamic> _summary({
  bool grounded = true,
  bool insufficientOnly = false,
}) {
  if (insufficientOnly) {
    return {
      'period_days': 30,
      'is_diagnosis': false,
      'disclaimer': LegalCopy.aiBanner,
      'data_availability': {
        'metrics_count': 0,
        'dose_events_count': 0,
        'lab_record_count': 0,
      },
      'insights': [
        {
          'id': 'metrics-insufficient',
          'category': 'monitoring',
          'title': 'Not enough health metrics yet',
          'summary': 'Not enough recent health measurements to identify a trend.',
          'source': 'health_metrics',
          'period': 'Last 30 days',
          'status': 'insufficient_data',
          'suggestion': 'Log vitals',
          'is_diagnosis': false,
        }
      ],
    };
  }
  return {
    'period_days': 30,
    'is_diagnosis': false,
    'disclaimer': LegalCopy.aiBanner,
    'data_availability': {
      'metrics_count': 5,
      'dose_events_count': 10,
      'lab_record_count': 1,
    },
    'insights': [
      if (grounded)
        {
          'id': 'metric-heart_rate',
          'category': 'trend',
          'title': 'Heart rate: upward pattern in your records',
          'summary':
              'Based on 5 recorded heart rate readings, your recorded values show an upward pattern.',
          'source': 'health_metrics',
          'period': 'Last 30 days',
          'status': 'grounded',
          'suggestion': 'Discuss with your GP.',
          'is_diagnosis': false,
          'facts': {'direction': 'upward', 'reading_count': 5},
        },
      {
        'id': 'adherence-summary',
        'category': 'adherence',
        'title': 'Medication adherence from your records',
        'summary':
            'Your recorded adherence was 82% over the selected period.',
        'source': 'medication_dose_events',
        'period': 'Last 30 days',
        'status': grounded ? 'grounded' : 'insufficient_data',
        'suggestion': 'Discuss with your pharmacist.',
        'is_diagnosis': false,
      },
      {
        'id': 'lab-insufficient',
        'category': 'lab',
        'title': 'Lab insights awaiting review',
        'summary':
            'Unreviewed or raw AI/OCR lab analysis is not used as authoritative health insight data.',
        'source': 'lab_analysis',
        'period': 'Last 30 days',
        'status': 'insufficient_data',
        'review_state': 'unreviewed_excluded',
        'is_diagnosis': false,
      },
    ],
  };
}

Map<String, dynamic> _advice() => {
      'consult_needed': true,
      'urgency': 'routine',
      'advice':
          'Consider discussing your recorded measurements with a GP when you have questions.',
      'reasons': ['5 recent measurement(s) are available'],
      'next_steps': ['Call 000 in a medical emergency'],
      'disclaimer': LegalCopy.aiBanner,
      'is_diagnosis': false,
    };

void main() {
  final screenSrc = File(
    'lib/features/health_insights/presentation/health_insights_screen.dart',
  ).readAsStringSync();

  testWidgets('INS-F01 health insights screen renders', (tester) async {
    await tester.pumpWidget(
      _wrap(
        HealthInsightsScreen(
          fetchSummary: () async => _summary(),
          fetchAdvice: () async => _advice(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('health_insights_screen')), findsOneWidget);
    expect(find.text('Health Insights'), findsOneWidget);
  });

  testWidgets('INS-F02 loading state renders', (tester) async {
    var release = false;
    await tester.pumpWidget(
      _wrap(
        HealthInsightsScreen(
          fetchSummary: () async {
            while (!release) {
              await Future<void>.delayed(const Duration(milliseconds: 20));
            }
            return _summary();
          },
          fetchAdvice: () async {
            while (!release) {
              await Future<void>.delayed(const Duration(milliseconds: 20));
            }
            return _advice();
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('insights_loading')), findsOneWidget);
    release = true;
    await tester.pumpAndSettle();
  });

  testWidgets('INS-F03 grounded insight cards render', (tester) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(
      _wrap(
        HealthInsightsScreen(
          fetchSummary: () async => _summary(),
          fetchAdvice: () async => _advice(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Grounded insights'), findsOneWidget);
    expect(find.textContaining('Heart rate'), findsWidgets);
    expect(find.text('GROUNDED'), findsWidgets);
  });

  testWidgets('INS-F04 source/period information renders', (tester) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(
      _wrap(
        HealthInsightsScreen(
          fetchSummary: () async => _summary(),
          fetchAdvice: () async => _advice(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Source: health_metrics'), findsWidgets);
    expect(find.textContaining('Period: Last 30 days'), findsWidgets);
  });

  testWidgets('INS-F05 insufficient-data state renders honestly',
      (tester) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(
      _wrap(
        HealthInsightsScreen(
          fetchSummary: () async => _summary(insufficientOnly: true),
          fetchAdvice: () async => _advice(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('insights_insufficient_state')), findsOneWidget);
    expect(find.textContaining('Not enough data yet'), findsWidgets);
  });

  testWidgets('INS-F06 backend failure renders retry', (tester) async {
    await tester.pumpWidget(
      _wrap(
        HealthInsightsScreen(
          fetchSummary: () async => throw Exception('down'),
          fetchAdvice: () async => throw Exception('down'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('insights_error')), findsOneWidget);
    expect(find.byKey(const Key('insights_retry_button')), findsOneWidget);
  });

  testWidgets('INS-F07 refresh behavior works', (tester) async {
    _setLargeSurface(tester);
    var calls = 0;
    await tester.pumpWidget(
      _wrap(
        HealthInsightsScreen(
          fetchSummary: () async {
            calls += 1;
            return _summary();
          },
          fetchAdvice: () async => _advice(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final first = calls;
    await tester.tap(find.byKey(const Key('insights_refresh_button')));
    await tester.pumpAndSettle();
    expect(calls, greaterThan(first));
  });

  testWidgets('INS-F08 medication adherence insight renders', (tester) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(
      _wrap(
        HealthInsightsScreen(
          fetchSummary: () async => _summary(),
          fetchAdvice: () async => _advice(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('adherence was 82%'), findsOneWidget);
  });

  testWidgets('INS-F09 metric trend insight renders', (tester) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(
      _wrap(
        HealthInsightsScreen(
          fetchSummary: () async => _summary(),
          fetchAdvice: () async => _advice(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('upward pattern'), findsWidgets);
  });

  testWidgets('INS-F10 lab unreviewed not shown as confirmed', (tester) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(
      _wrap(
        HealthInsightsScreen(
          fetchSummary: () async => _summary(),
          fetchAdvice: () async => _advice(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
          'Unreviewed lab extractions are not shown as confirmed'),
      findsOneWidget,
    );
  });

  testWidgets('INS-F11 non-diagnostic disclaimer visible', (tester) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(
      _wrap(
        HealthInsightsScreen(
          fetchSummary: () async => _summary(),
          fetchAdvice: () async => _advice(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('insights_safety_banner')), findsOneWidget);
    expect(find.byKey(const Key('insights_disclaimer')), findsOneWidget);
    expect(find.textContaining('not a diagnosis'), findsWidgets);
  });

  test('INS-F12 no unsafe diagnostic/prescribing UI copy', () {
    final lower = screenSrc.toLowerCase();
    expect(lower.contains('diagnosis confirmed'), isFalse);
    expect(lower.contains('you have '), isFalse);
    expect(lower.contains('start taking'), isFalse);
    expect(lower.contains('stop taking'), isFalse);
    expect(lower.contains('all clear!'), isFalse);
  });

  testWidgets('INS-F13 duplicate refresh prevented while loading',
      (tester) async {
    var calls = 0;
    var release = false;
    await tester.pumpWidget(
      _wrap(
        HealthInsightsScreen(
          fetchSummary: () async {
            calls += 1;
            while (!release) {
              await Future<void>.delayed(const Duration(milliseconds: 20));
            }
            return _summary();
          },
          fetchAdvice: () async {
            while (!release) {
              await Future<void>.delayed(const Duration(milliseconds: 20));
            }
            return _advice();
          },
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('insights_refresh_button')));
    await tester.pump();
    expect(calls, 1);
    release = true;
    await tester.pumpAndSettle();
  });

  test('INS-F14 family subject not forced client-side', () {
    // Screen does not invent family_member_id; API optional param only.
    expect(screenSrc.contains('family_member_id'), isFalse);
  });
}
