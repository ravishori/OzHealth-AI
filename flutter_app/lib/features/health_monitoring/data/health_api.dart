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
  /// [limit] is capped by the API (max 200) so home cards can show
  /// multiple metric types without dropping older types.
  static Future<List<dynamic>> getMetrics({
    String? metricType,
    int? familyMemberId,
    int days = 30,
    int limit = 200,
  }) async {
    final resp = await ApiClient.get('/health-metrics/', queryParameters: {
      if (metricType != null) 'metric_type': metricType,
      if (familyMemberId != null) 'family_member_id': familyMemberId,
      'days': days,
      'limit': limit,
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

  /// Update an existing reading. Type and family subject stay frozen server-side.
  static Future<Map<String, dynamic>> updateMetric({
    required int id,
    required double value,
    double? value2,
    String? unit,
    String? notes,
    String? recordedAt,
  }) async {
    final resp = await ApiClient.put('/health-metrics/$id', data: {
      'value': value,
      if (value2 != null) 'value2': value2,
      if (unit != null) 'unit': unit,
      'notes': notes,
      if (recordedAt != null) 'recorded_at': recordedAt,
    });
    return resp.data as Map<String, dynamic>;
  }

  static Future<void> deleteMetric(int id) async {
    await ApiClient.delete('/health-metrics/$id');
  }
}
