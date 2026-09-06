import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/health_monitoring/data/health_metrics_chart.dart';
import 'package:vitapulse_ai/features/health_monitoring/presentation/log_metric_screen.dart';
import 'package:vitapulse_ai/features/legal/legal_copy.dart';
import 'package:vitapulse_ai/shared/widgets/clinical_safety_banner.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppThemeBuilder.light(const AppThemeSettings()),
    home: Scaffold(body: child),
  );
}

void main() {
  final homeSrc = File(
          'lib/features/health_monitoring/presentation/health_monitoring_screen.dart')
      .readAsStringSync();
  final logSrc =
      File('lib/features/health_monitoring/presentation/log_metric_screen.dart')
          .readAsStringSync();
  final historySrc = File(
          'lib/features/health_monitoring/presentation/metric_history_screen.dart')
      .readAsStringSync();
  final apiSrc =
      File('lib/features/health_monitoring/data/health_api.dart').readAsStringSync();
  final routerSrc = File('lib/core/router/app_router.dart').readAsStringSync();

  test('HEALTH-FL-01 Health Metrics screen still registered', () {
    expect(routerSrc.contains('HealthMonitoringScreen'), isTrue);
    expect(homeSrc.contains('Health Monitor'), isTrue);
  });

  test('HEALTH-FL-02 latest readings use recorded samples', () {
    expect(homeSrc.contains('Latest reading'), isTrue);
    expect(homeSrc.contains('displayValue'), isTrue);
    expect(homeSrc.toLowerCase().contains('you have hypertension'), isFalse);
    expect(homeSrc.toLowerCase().contains('you are healthy'), isFalse);
  });

  test('HEALTH-FL-03 add reading form opens via route', () {
    expect(routerSrc.contains('health/log'), isTrue);
    expect(logSrc.contains('Log Health Metric'), isTrue);
    expect(homeSrc.contains("push('/home/health/log'"), isTrue);
  });

  test('HEALTH-FL-04 metric-specific fields', () {
    expect(logSrc.contains('_isBP'), isTrue);
    expect(logSrc.contains('Systolic'), isTrue);
    expect(logSrc.contains('Diastolic'), isTrue);
    expect(logSrc.contains('Blood Sugar'), isTrue);
    expect(logSrc.contains('Heart Rate'), isTrue);
    expect(logSrc.contains('SpO2'), isTrue);
    expect(logSrc.contains('Weight'), isTrue);
    expect(logSrc.contains('_unitMap'), isTrue);
  });

  test('HEALTH-FL-05 invalid input is blocked', () {
    expect(logSrc.contains('Please enter a value') || logSrc.contains('Required'),
        isTrue);
    expect(logSrc.contains('valid number') || logSrc.contains('Invalid'), isTrue);
    expect(logSrc.contains('_formKey.currentState!.validate()'), isTrue);
  });

  test('HEALTH-FL-06 successful save refreshes history', () {
    expect(homeSrc.contains('_loadMetrics()'), isTrue);
    expect(logSrc.contains("ApiClient.post('/health-metrics/'"), isTrue);
    expect(homeSrc.contains("push('/home/health/log'"), isTrue);
  });

  test('HEALTH-FL-07 empty state renders', () {
    expect(homeSrc.contains('No recorded measurements yet'), isTrue);
    expect(homeSrc.contains('Add a health reading'), isTrue);
    expect(historySrc.contains('No recorded'), isTrue);
  });

  test('HEALTH-FL-08 loading state renders', () {
    expect(homeSrc.contains('CircularProgressIndicator'), isTrue);
    expect(historySrc.contains('CircularProgressIndicator'), isTrue);
  });

  test('HEALTH-FL-09 error state + retry', () {
    expect(homeSrc.contains('Try Again'), isTrue);
    expect(homeSrc.contains('_HealthMonitorErrorState'), isTrue);
    expect(historySrc.contains('Try Again'), isTrue);
    expect(homeSrc.contains('Unable to load your health data'), isTrue);
  });

  test('HEALTH-FL-10/11/12 range filters change data', () {
    expect(homeSrc.contains('HealthMetricsRange'), isTrue);
    expect(homeSrc.contains('days7') || homeSrc.contains('_range.days'), isTrue);
    expect(apiSrc.contains("'days': days"), isTrue);
    expect(historySrc.contains('HealthMetricsRange.days7') ||
        historySrc.contains('for (final range in HealthMetricsRange.values)'), isTrue);
    expect(homeSrc.contains("HealthApi.getMetrics"), isTrue);
  });

  test('HEALTH-FL-13 chart is chronological and not interpolated', () {
    expect(historySrc.contains('isCurved: false'), isTrue);
    expect(homeSrc.contains('isCurved: false'), isTrue);
    expect(historySrc.contains('HealthMetricsChartData.spots'), isTrue);
  });

  test('HEALTH-FL-14 single/no data handled without fabricating a trend', () {
    expect(homeSrc.contains('Not enough readings for a trend yet'), isTrue);
    expect(historySrc.contains('Not enough readings for a trend yet'), isTrue);
    expect(HealthMetricsChartData.hasTrend(const []), isFalse);
    expect(
      HealthMetricsChartData.hasTrend([
        RecordedMetricSample(
          recordedAt: DateTime(2026, 1, 1),
          value: 70,
          metricType: 'heart_rate',
        ),
      ]),
      isFalse,
    );
  });

  test('HEALTH-FL-15 family-member context stays isolated', () {
    expect(homeSrc.contains('familyMemberId: _familyMemberId'), isTrue);
    expect(homeSrc.contains("'Myself'"), isTrue);
    expect(logSrc.contains('Logged For'), isTrue);
    expect(
      logSrc.contains("'family_member_id': _selectedFamilyMemberId") ||
          logSrc.contains("data['family_member_id'] = _selectedFamilyMemberId"),
      isTrue,
    );
    expect(apiSrc.contains('family_member_id'), isTrue);
  });

  test('HEALTH-FAMILY-FUNC-03 log inherits Health Monitor subject only if owned', () {
    expect(homeSrc.contains('_logRouteExtra()'), isTrue);
    expect(homeSrc.contains("'familyMemberId': _familyMemberId"), isTrue);
    expect(routerSrc.contains('initialFamilyMemberId:'), isTrue);
    expect(logSrc.contains('initialFamilyMemberId'), isTrue);
    expect(logSrc.contains('ownedFamilyMemberSelection'), isTrue);
  });

  test('HEALTH-FAMILY-SEC-09 arbitrary family id cannot preselect log subject', () {
    expect(
      ownedFamilyMemberSelection(
        requestedId: 10,
        ownedMembers: [
          {'id': 10, 'name': 'Alex'},
        ],
      ),
      10,
    );
    expect(
      ownedFamilyMemberSelection(
        requestedId: 999,
        ownedMembers: [
          {'id': 10, 'name': 'Alex'},
        ],
      ),
      isNull,
    );
    expect(
      ownedFamilyMemberSelection(
        requestedId: 10,
        ownedMembers: const [],
      ),
      isNull,
    );
  });

  test('HEALTH-FL-16 existing log + monitor routes remain', () {
    expect(routerSrc.contains("path: 'health'"), isTrue);
    expect(routerSrc.contains("path: 'health/log'"), isTrue);
    expect(routerSrc.contains("path: 'health/history'"), isTrue);
    expect(logSrc.contains('_pickDateTime'), isTrue);
  });

  test('chart spots stay chronological and do not invent values', () {
    final a = RecordedMetricSample(
      id: 1,
      recordedAt: DateTime(2026, 1, 10),
      value: 80,
      metricType: 'heart_rate',
    );
    final b = RecordedMetricSample(
      id: 2,
      recordedAt: DateTime(2026, 1, 1),
      value: 70,
      metricType: 'heart_rate',
    );
    final spots = HealthMetricsChartData.spots([a, b]);
    expect(spots.length, 2);
    expect(spots.first.y, 70);
    expect(spots.last.y, 80);
    expect(spots.first.x < spots.last.x, isTrue);
    expect(HealthMetricsChartData.hasTrend([a, b]), isTrue);
  });

  test('malformed samples are not given invented timestamps', () {
    expect(
      () => RecordedMetricSample.fromJson({
        'id': 1,
        'value': 72,
        'metric_type': 'heart_rate',
      }),
      throwsFormatException,
    );
  });

  test('duplicate timestamps keep both stored points', () {
    final t = DateTime(2026, 2, 1, 8);
    final spots = HealthMetricsChartData.spots([
      RecordedMetricSample(
          id: 1, recordedAt: t, value: 70, metricType: 'heart_rate'),
      RecordedMetricSample(
          id: 2, recordedAt: t, value: 74, metricType: 'heart_rate'),
    ]);
    expect(spots.length, 2);
    expect(spots.map((p) => p.y).toList(), [70, 74]);
  });

  testWidgets('HEALTH-FL safety banner is non-diagnostic', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const ClinicalSafetyBanner(kind: ClinicalDisclaimerKind.healthMetrics),
      ),
    );
    expect(find.text(LegalCopy.healthMetricsBanner), findsOneWidget);
    expect(LegalCopy.healthMetricsBanner.toLowerCase().contains('diagnosis'),
        isTrue);
    expect(LegalCopy.healthMetricsBanner.toLowerCase().contains('hypertension'),
        isFalse);
  });

  test('HEALTH-CRUD-EDIT Flutter reuses log screen with frozen type/subject', () {
    expect(logSrc.contains('existingMetric'), isTrue);
    expect(logSrc.contains('Edit Health Metric'), isTrue);
    expect(logSrc.contains('Save changes'), isTrue);
    expect(logSrc.contains('_isEditing'), isTrue);
    expect(logSrc.contains('HealthApi.updateMetric'), isTrue);
    expect(routerSrc.contains("extra['metric']"), isTrue);
    expect(historySrc.contains('_openEdit'), isTrue);
    expect(apiSrc.contains("ApiClient.put('/health-metrics/\$id'"), isTrue);
  });

  test('HEALTH-CRUD-DELETE Flutter confirms then calls delete', () {
    expect(historySrc.contains('Delete reading?'), isTrue);
    expect(historySrc.contains("Navigator.pop(ctx, false)"), isTrue);
    expect(historySrc.contains('HealthApi.deleteMetric'), isTrue);
    expect(historySrc.contains('_load()'), isTrue);
    expect(apiSrc.contains("ApiClient.delete('/health-metrics/\$id')"), isTrue);
  });
}
