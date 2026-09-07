import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// HN-HEALTH-006 — Flutter contracts for delete health metric.
void main() {
  final monitorSrc = File(
    'lib/features/health_monitoring/presentation/health_monitoring_screen.dart',
  ).readAsStringSync();
  final apiSrc = File(
    'lib/features/health_monitoring/data/health_api.dart',
  ).readAsStringSync();
  final providerSrc = File(
    'lib/features/health_monitoring/providers/health_provider.dart',
  ).readAsStringSync();

  test('HEALTH-006-FE-01 delete action available on history metric', () {
    expect(monitorSrc.contains('health_metric_delete_button_'), isTrue);
    expect(monitorSrc.contains('_confirmAndDeleteMetric'), isTrue);
    expect(monitorSrc.contains("Icons.delete_outline"), isTrue);
  });

  test('HEALTH-006-FE-02 confirmation dialog appears before delete', () {
    expect(monitorSrc.contains('health_metric_delete_confirm_dialog'), isTrue);
    expect(monitorSrc.contains('Delete this health measurement?'), isTrue);
    expect(monitorSrc.contains('health_metric_delete_cancel'), isTrue);
    expect(monitorSrc.contains('health_metric_delete_confirm'), isTrue);
    expect(monitorSrc.contains('showDialog<bool>'), isTrue);
  });

  test('HEALTH-006-FE-03 cancel makes no API call', () {
    // Cancel pops false; deleteMetric only runs after confirmed == true.
    expect(monitorSrc.contains("Navigator.of(dialogCtx).pop(false)"), isTrue);
    expect(monitorSrc.contains('if (confirmed != true) return false;'), isTrue);
    final confirmIdx = monitorSrc.indexOf('if (confirmed != true) return false;');
    final deleteIdx = monitorSrc.indexOf('HealthApi.deleteMetric');
    expect(confirmIdx, greaterThan(0));
    expect(deleteIdx, greaterThan(confirmIdx));
  });

  test('HEALTH-006-FE-04 confirm calls DELETE API', () {
    expect(apiSrc.contains('deleteMetric'), isTrue);
    expect(apiSrc.contains("ApiClient.delete('/health-metrics/\$metricId')"), isTrue);
    expect(monitorSrc.contains('HealthApi.deleteMetric(metricId: metricId)'), isTrue);
    expect(apiSrc.contains("'user_id':"), isFalse);
  });

  test('HEALTH-006-FE-05 successful deletion refreshes and removes item', () {
    expect(monitorSrc.contains('items = items'), isTrue);
    expect(monitorSrc.contains("r['id'] != id"), isTrue);
    expect(monitorSrc.contains('_loadSummary()'), isTrue);
    expect(monitorSrc.contains('Measurement removed'), isTrue);
    expect(providerSrc.contains('deleteMetric'), isTrue);
    expect(providerSrc.contains('loadSummary'), isTrue);
    expect(providerSrc.contains('loadHistory'), isTrue);
  });

  test('HEALTH-006-FE-06 API failure shows safe friendly error', () {
    expect(monitorSrc.contains('_friendlyDeleteMessage'), isTrue);
    expect(
      monitorSrc.contains('Failed to delete measurement. Please try again.'),
      isTrue,
    );
    expect(monitorSrc.contains('This reading was not found'), isTrue);
    expect(monitorSrc.contains('Text(e.toString())'), isFalse);
    expect(
      monitorSrc.contains('does not change your medical condition or treatment'),
      isTrue,
    );
    expect(monitorSrc.toLowerCase().contains('prescrib'), isFalse);
  });

  test('HEALTH-006-FE-07 edit path remains intact', () {
    expect(monitorSrc.contains('health_metric_edit_button_'), isTrue);
    expect(monitorSrc.contains("'/home/health/edit'"), isTrue);
    expect(apiSrc.contains('updateMetric'), isTrue);
  });
}
