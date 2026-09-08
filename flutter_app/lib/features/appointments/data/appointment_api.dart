import 'package:vitapulse_ai/core/network/api_client.dart';

/// HN-REM-010 — appointment CRUD API (ownership from auth; never client-supplied).
class AppointmentApi {
  static Future<List<Map<String, dynamic>>> listAppointments({
    bool activeOnly = true,
    int? familyMemberId,
  }) async {
    final query = <String, dynamic>{
      'active_only': activeOnly,
    };
    if (familyMemberId != null) {
      query['family_member_id'] = familyMemberId;
    }
    final resp = await ApiClient.get(
      '/appointments/',
      queryParameters: query,
    );
    final data = resp.data;
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  static Future<Map<String, dynamic>> getAppointment(int id) async {
    final resp = await ApiClient.get('/appointments/$id');
    return Map<String, dynamic>.from(resp.data as Map);
  }

  static Future<Map<String, dynamic>> createAppointment(
    Map<String, dynamic> data,
  ) async {
    final resp = await ApiClient.post('/appointments/', data: data);
    return Map<String, dynamic>.from(resp.data as Map);
  }

  static Future<Map<String, dynamic>> updateAppointment(
    int id,
    Map<String, dynamic> data,
  ) async {
    final resp = await ApiClient.put('/appointments/$id', data: data);
    return Map<String, dynamic>.from(resp.data as Map);
  }

  static Future<void> deleteAppointment(int id) async {
    await ApiClient.delete('/appointments/$id');
  }
}

/// Allowed remind_before_minutes values (must match backend).
const List<int> kAllowedRemindBeforeMinutes = [0, 15, 30, 60, 120, 1440];

String remindBeforeLabel(int minutes) {
  switch (minutes) {
    case 0:
      return 'At appointment time';
    case 15:
      return '15 minutes before';
    case 30:
      return '30 minutes before';
    case 60:
      return '1 hour before';
    case 120:
      return '2 hours before';
    case 1440:
      return '1 day before';
    default:
      return '$minutes minutes before';
  }
}

/// Build create/update payload. Never includes client owner identity fields.
Map<String, dynamic> buildAppointmentSavePayload({
  required String title,
  required DateTime scheduledAt,
  String? notes,
  int remindBeforeMinutes = 60,
  int? familyMemberId,
  bool includeFamilyMember = true,
}) {
  final payload = <String, dynamic>{
    'title': title.trim(),
    'scheduled_at': scheduledAt.toUtc().toIso8601String(),
    'remind_before_minutes': remindBeforeMinutes,
  };
  final cleanedNotes = notes?.trim();
  if (cleanedNotes != null && cleanedNotes.isNotEmpty) {
    payload['notes'] = cleanedNotes;
  } else {
    payload['notes'] = null;
  }
  if (includeFamilyMember) {
    payload['family_member_id'] = familyMemberId;
  }
  return payload;
}

DateTime? parseAppointmentApiDateTime(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s)?.toLocal();
}
