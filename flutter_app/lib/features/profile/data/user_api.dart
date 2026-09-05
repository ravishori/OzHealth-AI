import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';

class UserApi {
  static Future<Map<String, dynamic>> getMe() async {
    final resp = await ApiClient.get('/users/me');
    return resp.data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> updateMe(Map<String, dynamic> data) async {
    final resp = await ApiClient.put('/users/me', data: data);
    return resp.data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> uploadPhoto(String filePath) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
    });
    final resp = await ApiClient.uploadFile('/users/me/photo', formData);
    return resp.data as Map<String, dynamic>;
  }

  static Future<void> updateFcmToken(String token) async {
    await ApiClient.put('/users/me', data: {'fcm_token': token});
  }

  /// HN-LEGAL-007 — download owner-scoped JSON export (authenticated).
  /// Does not log the export body.
  static Future<Map<String, dynamic>> exportMyData() async {
    final resp = await ApiClient.get('/users/me/data-export');
    final data = resp.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) {
      return Map<String, dynamic>.from(jsonDecode(data) as Map);
    }
    if (data is List<int>) {
      return Map<String, dynamic>.from(jsonDecode(utf8.decode(data)) as Map);
    }
    throw StateError('Unexpected data-export response type');
  }

  /// Persist export JSON to a temp file and open the system share sheet.
  static Future<void> shareDataExport(Map<String, dynamic> payload) async {
    final dir = await getTemporaryDirectory();
    final uid = payload['user_id']?.toString() ?? 'me';
    final path = '${dir.path}/healthnest-data-export-$uid.json';
    final file = File(path);
    await file.writeAsString(jsonEncode(payload), flush: true);
    await Share.shareXFiles(
      [XFile(path)],
      subject: 'HealthNest data export',
    );
  }
}
