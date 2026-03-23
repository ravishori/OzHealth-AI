import 'package:dio/dio.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';

class RecordsApi {
  static Future<List<dynamic>> getRecords({
    String? recordType,
    int? familyMemberId,
  }) async {
    final resp = await ApiClient.get('/records/', queryParameters: {
      if (recordType != null) 'record_type': recordType,
      if (familyMemberId != null) 'family_member_id': familyMemberId,
    });
    return resp.data as List<dynamic>;
  }

  static Future<Map<String, dynamic>> getRecord(int id) async {
    final resp = await ApiClient.get('/records/$id');
    return resp.data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> uploadRecord({
    required String filePath,
    required String recordType,
    String? title,
    String? notes,
    int? familyMemberId,
    String? recordDate,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
      'record_type': recordType,
      if (title != null) 'title': title,
      if (notes != null) 'notes': notes,
      if (familyMemberId != null) 'family_member_id': familyMemberId,
      if (recordDate != null) 'record_date': recordDate,
    });
    final resp = await ApiClient.uploadFile('/records/upload', formData);
    return resp.data as Map<String, dynamic>;
  }

  static Future<void> deleteRecord(int id) async {
    await ApiClient.delete('/records/$id');
  }
}
