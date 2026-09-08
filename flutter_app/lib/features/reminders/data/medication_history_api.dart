import 'package:vitapulse_ai/core/network/api_client.dart';

/// HN-MEDMGMT-006 — medication dose / adherence history API.
class MedicationHistoryApi {
  static Future<List<Map<String, dynamic>>> listHistory({
    int? medicationScheduleId,
    int? familyMemberId,
  }) async {
    final query = <String, dynamic>{};
    if (medicationScheduleId != null) {
      query['medication_schedule_id'] = medicationScheduleId;
    }
    if (familyMemberId != null) {
      query['family_member_id'] = familyMemberId;
    }
    final resp = await ApiClient.get(
      '/medication-history/',
      queryParameters: query.isEmpty ? null : query,
    );
    final data = resp.data;
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  static Future<Map<String, dynamic>> recordDose({
    required int medicationScheduleId,
    required String status,
    required DateTime scheduledFor,
  }) async {
    final resp = await ApiClient.post(
      '/medication-history/',
      data: {
        'medication_schedule_id': medicationScheduleId,
        'status': status,
        'scheduled_for': scheduledFor.toUtc().toIso8601String(),
      },
    );
    return Map<String, dynamic>.from(resp.data as Map);
  }

  static Future<Map<String, dynamic>> summary({
    int? medicationScheduleId,
    int? familyMemberId,
  }) async {
    final query = <String, dynamic>{};
    if (medicationScheduleId != null) {
      query['medication_schedule_id'] = medicationScheduleId;
    }
    if (familyMemberId != null) {
      query['family_member_id'] = familyMemberId;
    }
    final resp = await ApiClient.get(
      '/medication-history/summary',
      queryParameters: query.isEmpty ? null : query,
    );
    return Map<String, dynamic>.from(resp.data as Map);
  }
}
