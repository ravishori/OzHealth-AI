import 'package:dio/dio.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';

class SymptomsApi {
  // The backend wraps both AI calls in a 55-second asyncio.wait_for timeout.
  // Add an extra 30 s buffer on the Flutter side so Dio never races the server.
  static const _kAiReceiveTimeout = Duration(seconds: 90);

  static Future<Map<String, dynamic>> checkSymptoms(
    List<String> symptoms, {
    String? duration,
  }) async {
    final resp = await ApiClient.post(
      '/symptoms/check',
      data: {
        'symptoms': symptoms,
        if (duration != null) 'duration': duration,
        'include_consultation_advice': true,
      },
      options: Options(receiveTimeout: _kAiReceiveTimeout),
    );
    return resp.data as Map<String, dynamic>;
  }
}
