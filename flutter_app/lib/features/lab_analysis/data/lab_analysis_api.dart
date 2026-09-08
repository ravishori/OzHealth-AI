import 'dart:io';
import 'package:dio/dio.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';

/// HN-FUTURE-002 — Lab analysis API client.
///
/// Analyze returns an unconfirmed extraction draft (review required).
/// Confirm persists user acknowledgement that they reviewed the extraction
/// against the original report — not clinician verification.
class LabAnalysisApi {
  static Future<Map<String, dynamic>> analyzeFile(
    File file, {
    int? familyMemberId,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        file.path,
        filename: file.path.split('/').last,
      ),
      if (familyMemberId != null) 'family_member_id': familyMemberId,
    });
    final resp = await ApiClient.post('/lab-analysis/analyze', data: formData);
    return resp.data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> analyzeExistingRecord(int recordId) async {
    final resp =
        await ApiClient.post('/lab-analysis/analyze-record/$recordId');
    return resp.data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> confirm(int recordId) async {
    final resp = await ApiClient.post('/lab-analysis/confirm/$recordId');
    return resp.data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> reject(int recordId) async {
    final resp = await ApiClient.post('/lab-analysis/reject/$recordId');
    return resp.data as Map<String, dynamic>;
  }
}
