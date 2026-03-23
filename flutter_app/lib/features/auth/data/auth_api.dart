import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/utils/auth_storage.dart';

class AuthApi {
  static Future<void> sendOtp(String identifier, String purpose) async {
    await ApiClient.post('/auth/send-otp', data: {
      'identifier': identifier,
      'purpose': purpose,
    });
  }

  static Future<Map<String, dynamic>> register({
    required String name,
    required String identifier,
    required String otpCode,
    int? age,
    String? gender,
    String? bloodGroup,
  }) async {
    final resp = await ApiClient.post('/auth/register', data: {
      'name': name,
      'identifier': identifier,
      'otp_code': otpCode,
      if (age != null) 'age': age,
      if (gender != null) 'gender': gender,
      if (bloodGroup != null) 'blood_group': bloodGroup,
    });
    final data = resp.data as Map<String, dynamic>;
    await AuthStorage.saveTokens(
      accessToken: data['access_token'],
      refreshToken: data['refresh_token'],
      userId: data['user_id'],
      name: data['name'],
    );
    return data;
  }

  static Future<Map<String, dynamic>> login({
    required String identifier,
    required String otpCode,
  }) async {
    final resp = await ApiClient.post('/auth/login', data: {
      'identifier': identifier,
      'otp_code': otpCode,
    });
    final data = resp.data as Map<String, dynamic>;
    await AuthStorage.saveTokens(
      accessToken: data['access_token'],
      refreshToken: data['refresh_token'],
      userId: data['user_id'],
      name: data['name'],
    );
    return data;
  }

  /// Pre-validate an OTP without consuming it.
  /// Returns normally on success; throws [AppError] on invalid/expired OTP.
  static Future<void> verifyOtp(
    String identifier,
    String otpCode,
    String purpose,
  ) async {
    await ApiClient.post('/auth/verify-otp', data: {
      'identifier': identifier,
      'otp_code': otpCode,
      'purpose': purpose,
    });
  }

  static Future<void> logout() => AuthStorage.clearAll();
}
