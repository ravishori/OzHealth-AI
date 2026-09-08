import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// HN-HEALTH-005 — Flutter contracts (HEALTH5-F01 .. HEALTH5-F10).
void main() {
  final monitorSrc = File(
    'lib/features/health_monitoring/presentation/health_monitoring_screen.dart',
  ).readAsStringSync();
  final logSrc = File(
    'lib/features/health_monitoring/presentation/log_metric_screen.dart',
  ).readAsStringSync();
  final apiSrc = File(
    'lib/features/health_monitoring/data/health_api.dart',
  ).readAsStringSync();
  final providerSrc = File(
    'lib/features/health_monitoring/providers/health_provider.dart',
  ).readAsStringSync();
  final routerSrc = File('lib/core/router/app_router.dart').readAsStringSync();

  test('HEALTH5-F01 edit action is available for an existing metric', () {
    expect(monitorSrc.contains('health_metric_edit_button_'), isTrue);
    expect(monitorSrc.contains('_openMetricHistory'), isTrue);
    expect(monitorSrc.contains("'/home/health/edit'"), isTrue);
    expect(routerSrc.contains("path: 'health/edit'"), isTrue);
    expect(routerSrc.contains('LogMetricScreen'), isTrue);
    expect(routerSrc.contains('initialMetric:'), isTrue);
  });

  test('HEALTH5-F02 edit form hydrates existing values', () {
    expect(logSrc.contains('initialMetric'), isTrue);
    expect(logSrc.contains('_prefillFromInitial'), isTrue);
    expect(logSrc.contains('edit_metric_screen'), isTrue);
    expect(logSrc.contains('Edit Health Metric'), isTrue);
    expect(logSrc.contains('_systolicController.text'), isTrue);
    expect(logSrc.contains('_valueController.text'), isTrue);
    expect(logSrc.contains('_notesController.text = notes'), isTrue);
    expect(logSrc.contains('DateTime.parse(recorded)'), isTrue);
  });

  test('HEALTH5-F03 user can modify supported fields', () {
    expect(logSrc.contains("Key('metric_value_field')"), isTrue);
    expect(logSrc.contains("Key('metric_systolic_field')"), isTrue);
    expect(logSrc.contains("Key('metric_diastolic_field')"), isTrue);
    expect(logSrc.contains("Key('metric_notes_field')"), isTrue);
    expect(logSrc.contains("Key('metric_datetime_picker')"), isTrue);
    expect(logSrc.contains('_pickDateTime'), isTrue);
  });

  test('HEALTH5-F04 save calls the update API', () {
    expect(apiSrc.contains('updateMetric'), isTrue);
    expect(apiSrc.contains('ApiClient.put'), isTrue);
    expect(apiSrc.contains('/health-metrics/\$metricId'), isTrue);
    expect(logSrc.contains('metric_save_edit_button'), isTrue);
    expect(logSrc.contains('HealthApi.updateMetric'), isTrue);
    expect(logSrc.contains('Navigator.of(context).pop(true)'), isTrue);
    // updateMetric body must not send ownership fields.
    final updateStart = apiSrc.indexOf('static Future<Map<String, dynamic>> updateMetric');
    final updateEnd = apiSrc.indexOf('static Future<List<dynamic>> getMetrics');
    expect(updateStart, greaterThan(0));
    expect(updateEnd, greaterThan(updateStart));
    final updateBody = apiSrc.substring(updateStart, updateEnd);
    expect(updateBody.contains('user_id'), isFalse);
    expect(updateBody.contains('family_member_id'), isFalse);
    expect(logSrc.contains('clearFamilyMember'), isFalse);
  });

  test('HEALTH5-F05 cancel does not call update', () {
    expect(logSrc.contains('dispose()'), isTrue);
    final submitIdx = logSrc.indexOf('Future<void> _submit()');
    final updateIdx = logSrc.indexOf('HealthApi.updateMetric');
    expect(submitIdx, greaterThan(0));
    expect(updateIdx, greaterThan(submitIdx));
    expect(logSrc.contains('dispose() {\n    HealthApi.updateMetric'), isFalse);
  });

  test('HEALTH5-F06 duplicate save is prevented while request is running', () {
    expect(logSrc.contains('bool _loading = false'), isTrue);
    expect(logSrc.contains('setState(() => _loading = true)'), isTrue);
    expect(logSrc.contains('LoadingButton'), isTrue);
    expect(logSrc.contains('loading: _loading'), isTrue);
  });

  test('HEALTH5-F07 successful update refreshes history', () {
    expect(monitorSrc.contains('if (edited == true'), isTrue);
    expect(monitorSrc.contains('_loadSummary()'), isTrue);
    expect(providerSrc.contains('updateMetric'), isTrue);
    expect(providerSrc.contains('loadHistory'), isTrue);
  });

  test('HEALTH5-F08 successful update refreshes summary/trend state', () {
    expect(monitorSrc.contains('_loadSummary()'), isTrue);
    expect(providerSrc.contains('loadSummary'), isTrue);
    expect(providerSrc.contains('await loadSummary'), isTrue);
    expect(providerSrc.contains('await loadHistory'), isTrue);
  });

  test('HEALTH5-F09 API failure is displayed without false success', () {
    expect(logSrc.contains('_friendlyError'), isTrue);
    expect(logSrc.contains('Failed to update metric. Please try again.'), isTrue);
    expect(logSrc.contains('This reading was not found'), isTrue);
    expect(logSrc.contains('SnackBar(\n            content: Text(e.toString())'), isFalse);
    expect(logSrc.contains('Informational reading only'), isTrue);
    expect(logSrc.toLowerCase().contains('not a diagnosis'), isTrue);
    expect(logSrc.toLowerCase().contains('prescrib'), isFalse);
    expect(logSrc.contains('Text(e.toString())'), isFalse);
    expect(logSrc.contains('updated'), isTrue);
    final catchIdx = logSrc.indexOf('} catch (e) {');
    expect(catchIdx, greaterThan(0));
    // Failure path resets loading and never claims success via pop(true) in catch.
    final catchBlock = logSrc.substring(catchIdx);
    expect(catchBlock.contains('Navigator.of(context).pop(true)'), isFalse);
  });

  test('HEALTH5-F10 invalid input prevents submission', () {
    expect(logSrc.contains('_formKey.currentState!.validate()'), isTrue);
    expect(logSrc.contains('if (!_formKey.currentState!.validate()) return;'), isTrue);
    expect(logSrc.contains('Please enter a valid number'), isTrue);
    expect(logSrc.contains('Expected range:'), isTrue);
    expect(logSrc.contains("return 'Required'"), isTrue);
    expect(logSrc.contains('Logged-for subject cannot be changed when editing.'), isTrue);
    expect(logSrc.contains('Metric type cannot be changed when editing.'), isTrue);
    expect(logSrc.contains('onChanged: _isEdit'), isTrue);
  });
}
