import 'package:vitapulse_ai/core/network/api_client.dart';

class HealthApi {
  /// Log a new health metric reading.
  static Future<Map<String, dynamic>> logMetric({
    required String metricType,
    required double value,
    double? value2, // diastolic BP
    String? unit,
    String? notes,
    int? familyMemberId,
    String? recordedAt, // ISO-8601 string; defaults to now on backend
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

  /// HN-HEALTH-005 — update an existing owned health metric.
  /// Does not send user_id or other server-owned fields.
  static Future<Map<String, dynamic>> updateMetric({
    required int metricId,
    double? value,
    double? value2,
    bool clearValue2 = false,
    String? unit,
    String? notes,
    bool clearNotes = false,
    String? recordedAt,
    int? familyMemberId,
    bool clearFamilyMember = false,
  }) async {
    final data = <String, dynamic>{};
    if (value != null) data['value'] = value;
    if (clearValue2) {
      data['value2'] = null;
    } else if (value2 != null) {
      data['value2'] = value2;
    }
    if (unit != null) data['unit'] = unit;
    if (clearNotes) {
      data['notes'] = null;
    } else if (notes != null) {
      data['notes'] = notes;
    }
    if (recordedAt != null) data['recorded_at'] = recordedAt;
    if (clearFamilyMember) {
      data['family_member_id'] = null;
    } else if (familyMemberId != null) {
      data['family_member_id'] = familyMemberId;
    }

    final resp = await ApiClient.put('/health-metrics/$metricId', data: data);
    return resp.data as Map<String, dynamic>;
  }

  /// HN-HEALTH-006 — delete an existing owned health metric.
  static Future<void> deleteMetric({required int metricId}) async {
    await ApiClient.delete('/health-metrics/$metricId');
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
