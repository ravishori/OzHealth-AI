import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/utils/auth_storage.dart';

enum LogoutOutcome {
  /// Server invalidated the session and local state was cleared.
  serverOk,

  /// Local state cleared but server invalidation was not confirmed.
  localOnly,
}

class AuthApi {
  /// Returns a [SendOtpResult] with delivery status.
  static Future<SendOtpResult> sendOtp(String identifier, String purpose) async {
    final resp = await ApiClient.post('/auth/send-otp', data: {
      'identifier': identifier,
      'purpose': purpose,
    });
    final data = resp.data as Map<String, dynamic>? ?? {};
    return SendOtpResult(
      message: data['message']?.toString() ?? 'OTP sent.',
      channel: data['channel']?.toString() ?? '',
      delivered: data['delivered'] as bool? ?? true,
      devError: data['_dev_error']?.toString(),
    );
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

  /// Call server logout **while tokens are still present**, then clear local state.
  ///
  /// On network/server failure, still clears local credentials so the user is
  /// not left appearing authenticated (fail-safe). Callers must not claim full
  /// server success when [LogoutOutcome.localOnly] is returned.
  static Future<LogoutOutcome> logout() async {
    var serverOk = false;
    try {
      await ApiClient.post('/auth/logout');
      serverOk = true;
    } catch (_) {
      serverOk = false;
    }
    await AuthStorage.clearAll();
    return serverOk ? LogoutOutcome.serverOk : LogoutOutcome.localOnly;
  }
}

class SendOtpResult {
  final String message;
  final String channel; // "email" or "sms"
  final bool delivered;
  final String? devError; // only present in DEBUG mode

  const SendOtpResult({
    required this.message,
    required this.channel,
    required this.delivered,
    this.devError,
  });
}
