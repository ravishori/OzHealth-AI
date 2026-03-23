import 'package:vitapulse_ai/core/network/api_client.dart';

class HealthApi {
  /// Log a new health metric reading.
  static Future<Map<String, dynamic>> logMetric({
    required String metricType,
    required double value,
    double? value2,         // diastolic BP
    String? unit,
    String? notes,
    int? familyMemberId,
    String? recordedAt,    // ISO-8601 string; defaults to now on backend
  }) async {
    final resp = await ApiClient.post('/health-metrics/', data: {
      'metric_type': metricType,
      'value': value,
      if (value2 != null) 'value2': value2,
      if (unit != null) 'unit': unit,
      if (notes != null) 'notes': notes,
      if (familyMemberId != null) 'family_member_id': familyMemberId,
      if (recordedAt != null) 'recorded_at': recordedAt,
    });
    return resp.data as Map<String, dynamic>;
  }

  /// Fetch metric history. [days] filters to last N days.
  static Future<List<dynamic>> getMetrics({
    String? metricType,
    int? familyMemberId,
    int days = 30,
  }) async {
    final resp = await ApiClient.get('/health-metrics/', queryParameters: {
      if (metricType != null) 'metric_type': metricType,
      if (familyMemberId != null) 'family_member_id': familyMemberId,
      'days': days,
    });
    return resp.data as List<dynamic>;
  }

  /// Dashboard summary: latest reading per metric type.
  static Future<Map<String, dynamic>> getSummary({
    int? familyMemberId,
  }) async {
    final resp = await ApiClient.get('/health-metrics/summary',
        queryParameters: {
          if (familyMemberId != null) 'family_member_id': familyMemberId,
        });
    return resp.data as Map<String, dynamic>;
  }
}
