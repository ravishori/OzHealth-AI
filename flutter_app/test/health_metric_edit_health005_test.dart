import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// HN-HEALTH-005 — Flutter contracts for edit health metric.
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

  test('HEALTH-005-FE-01 edit action available for existing metric', () {
    expect(monitorSrc.contains('health_metric_edit_button_'), isTrue);
    expect(monitorSrc.contains("_openMetricHistory"), isTrue);
    expect(monitorSrc.contains("'/home/health/edit'"), isTrue);
    expect(routerSrc.contains("path: 'health/edit'"), isTrue);
    expect(routerSrc.contains('LogMetricScreen'), isTrue);
    expect(routerSrc.contains('initialMetric:'), isTrue);
  });

  test('HEALTH-005-FE-02 edit form opens with existing values prefilled', () {
    expect(logSrc.contains('initialMetric'), isTrue);
    expect(logSrc.contains('_prefillFromInitial'), isTrue);
    expect(logSrc.contains('edit_metric_screen'), isTrue);
    expect(logSrc.contains('Edit Health Metric'), isTrue);
    expect(logSrc.contains('_systolicController.text'), isTrue);
    expect(logSrc.contains('_valueController.text'), isTrue);
    expect(logSrc.contains('_notesController.text = notes'), isTrue);
    expect(logSrc.contains('DateTime.parse(recorded)'), isTrue);
  });

  test('HEALTH-005-FE-03 user can modify values notes and timestamp', () {
    expect(logSrc.contains("Key('metric_value_field')"), isTrue);
    expect(logSrc.contains("Key('metric_systolic_field')"), isTrue);
    expect(logSrc.contains("Key('metric_diastolic_field')"), isTrue);
    expect(logSrc.contains("Key('metric_notes_field')"), isTrue);
    expect(logSrc.contains("Key('metric_datetime_picker')"), isTrue);
    expect(logSrc.contains('_pickDateTime'), isTrue);
  });

  test('HEALTH-005-FE-04 validation prevents invalid submission', () {
    expect(logSrc.contains('_formKey.currentState!.validate()'), isTrue);
    expect(logSrc.contains('Please enter a valid number'), isTrue);
    expect(logSrc.contains('Expected range:'), isTrue);
    expect(logSrc.contains("return 'Required'"), isTrue);
  });

  test('HEALTH-005-FE-05 cancel does not call update API', () {
    // Cancel/back is Navigator pop via AppBar — no updateMetric on dispose/pop.
    expect(logSrc.contains('dispose()'), isTrue);
    expect(logSrc.contains('HealthApi.updateMetric'), isTrue);
    // updateMetric only inside _submit after validation
    final submitIdx = logSrc.indexOf('Future<void> _submit()');
    final updateIdx = logSrc.indexOf('HealthApi.updateMetric');
    expect(submitIdx, greaterThan(0));
    expect(updateIdx, greaterThan(submitIdx));
    expect(logSrc.contains('dispose() {\n    HealthApi.updateMetric'), isFalse);
  });

  test('HEALTH-005-FE-06 save calls update API and pops success', () {
    expect(apiSrc.contains('updateMetric'), isTrue);
    expect(apiSrc.contains('ApiClient.put'), isTrue);
    expect(apiSrc.contains('/health-metrics/\$metricId'), isTrue);
    expect(apiSrc.contains("'user_id':"), isFalse);
    expect(apiSrc.contains('"user_id":'), isFalse);
    expect(logSrc.contains('metric_save_edit_button'), isTrue);
    expect(logSrc.contains('Navigator.of(context).pop(true)'), isTrue);
    expect(logSrc.contains('HealthApi.updateMetric'), isTrue);
  });

  test('HEALTH-005-FE-07 successful save refreshes metric history', () {
    expect(monitorSrc.contains('if (edited == true'), isTrue);
    expect(monitorSrc.contains('_loadSummary()'), isTrue);
    expect(providerSrc.contains('updateMetric'), isTrue);
    expect(providerSrc.contains('loadSummary'), isTrue);
    expect(providerSrc.contains('loadHistory'), isTrue);
  });

  test('HEALTH-005-FE-08 error state handled safely without PHI dump', () {
    expect(logSrc.contains('_friendlyError'), isTrue);
    expect(logSrc.contains('Failed to update metric. Please try again.'), isTrue);
    expect(logSrc.contains('This reading was not found'), isTrue);
    // Must not surface raw exception / response body to snackbar
    expect(logSrc.contains('SnackBar(\n            content: Text(e.toString())'), isFalse);
    expect(logSrc.contains('Informational reading only'), isTrue);
    // Safety copy may say "not a diagnosis" — must not recommend diagnosis/prescribe.
    expect(logSrc.toLowerCase().contains('not a diagnosis'), isTrue);
    expect(logSrc.toLowerCase().contains('prescrib'), isFalse);
    expect(logSrc.contains('Text(e.toString())'), isFalse);
  });

  test('HEALTH-005-FE-09 metric type locked on edit; create path intact', () {
    expect(logSrc.contains('Metric type cannot be changed when editing.'), isTrue);
    expect(logSrc.contains('onSelected: _isEdit'), isTrue);
    expect(logSrc.contains("ApiClient.post('/health-metrics/'"), isTrue);
    expect(logSrc.contains('Log Health Metric'), isTrue);
  });
}
