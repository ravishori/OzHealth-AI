import 'package:vitapulse_ai/core/network/api_client.dart';

class InteractionsApi {
  static Future<Map<String, dynamic>> checkInteractions(
    List<String> medicines, {
    bool includeDuplicateCheck = true,
  }) async {
    final resp = await ApiClient.post(
      '/interactions/check',
      data: {
        'medicines': medicines,
        'include_duplicate_check': includeDuplicateCheck,
      },
    );
    return resp.data as Map<String, dynamic>;
  }
}
