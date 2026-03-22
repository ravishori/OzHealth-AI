import 'package:dio/dio.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';

class PrescriptionApi {
  /// Uploads a prescription image/PDF, runs OCR + AI, and returns structured data.
  static Future<Map<String, dynamic>> scanPrescription({
    required String filePath,
    int? familyMemberId,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
      if (familyMemberId != null) 'family_member_id': familyMemberId,
    });
    final resp = await ApiClient.uploadFile('/prescriptions/scan', formData);
    return resp.data as Map<String, dynamic>;
  }

  static Future<List<dynamic>> getPrescriptions() async {
    final resp = await ApiClient.get('/prescriptions/');
    return resp.data as List<dynamic>;
  }

  static Future<Map<String, dynamic>> getPrescription(int id) async {
    final resp = await ApiClient.get('/prescriptions/$id');
    return resp.data as Map<String, dynamic>;
  }
}
