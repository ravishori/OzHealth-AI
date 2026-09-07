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

  /// HN-RX-003 — create a manually entered prescription (no OCR file).
  static Future<Map<String, dynamic>> createManualPrescription({
    required List<Map<String, dynamic>> medicines,
    String? doctorName,
    String? hospital,
    int? familyMemberId,
  }) async {
    final body = <String, dynamic>{
      'medicines': medicines,
      if (doctorName != null && doctorName.trim().isNotEmpty)
        'doctor_name': doctorName.trim(),
      if (hospital != null && hospital.trim().isNotEmpty)
        'hospital': hospital.trim(),
      if (familyMemberId != null) 'family_member_id': familyMemberId,
    };
    final resp = await ApiClient.post('/prescriptions/manual', data: body);
    return resp.data as Map<String, dynamic>;
  }
}
