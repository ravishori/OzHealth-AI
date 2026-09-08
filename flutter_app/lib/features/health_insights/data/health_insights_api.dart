import 'package:vitapulse_ai/core/network/api_client.dart';

/// HN-FUTURE-003 — grounded Health Insights API.
class HealthInsightsApi {
  static Future<Map<String, dynamic>> fetchSummary({
    int periodDays = 30,
    int? familyMemberId,
  }) async {
    final resp = await ApiClient.get(
      '/insights/summary',
      queryParameters: {
        'period_days': periodDays,
        if (familyMemberId != null) 'family_member_id': familyMemberId,
      },
    );
    return Map<String, dynamic>.from(resp.data as Map);
  }

  static Future<Map<String, dynamic>> fetchConsultationAdvice({
    int periodDays = 30,
    int? familyMemberId,
  }) async {
    final resp = await ApiClient.get(
      '/insights/consultation-advice',
      queryParameters: {
        'period_days': periodDays,
        if (familyMemberId != null) 'family_member_id': familyMemberId,
      },
    );
    return Map<String, dynamic>.from(resp.data as Map);
  }
}
