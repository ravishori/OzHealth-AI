import 'package:dio/dio.dart';
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
}
