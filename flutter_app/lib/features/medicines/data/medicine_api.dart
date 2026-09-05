import 'package:vitapulse_ai/core/network/api_client.dart';

class MedicineApi {
  static Future<Map<String, dynamic>> search(String query,
      {int limit = 20}) async {
    final resp = await ApiClient.get('/medicines/search',
        queryParameters: {'q': query, 'limit': limit});
    return resp.data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getMedicine(int id) async {
    final resp = await ApiClient.get('/medicines/$id');
    return resp.data as Map<String, dynamic>;
  }

  /// Catalogue-grounded patient explanation (HN-MED-008 preferred AI path).
  static Future<Map<String, dynamic>> getExplanation(int id) async {
    final resp = await ApiClient.get('/medicines/$id/explanation');
    return resp.data as Map<String, dynamic>;
  }

  /// Legacy name bridge — catalogue-gated only; does not invent clinical records.
  /// Prefer [getExplanation] with a confirmed medicine id for detail screens.
  static Future<Map<String, dynamic>> getAiInfo(String medicineName) async {
    final encodedName = Uri.encodeComponent(medicineName);
    final resp = await ApiClient.get('/medicines/ai-info/$encodedName');
    return resp.data as Map<String, dynamic>;
  }
}
