import 'package:vitapulse_ai/core/network/api_client.dart';

class MedicineApi {
  static Future<Map<String, dynamic>> search(String query,
      {int limit = 20}) async {
    final resp = await ApiClient.get('/medicines/search',
        queryParameters: {'q': query, 'limit': limit});
    return resp.data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>?> getByBarcode(String barcode) async {
    try {
      final resp = await ApiClient.get('/medicines/barcode/$barcode');
      return resp.data as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> getMedicine(int id) async {
    final resp = await ApiClient.get('/medicines/$id');
    return resp.data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getAiInfo(String medicineName) async {
    final encodedName = Uri.encodeComponent(medicineName);
    final resp = await ApiClient.get('/medicines/ai-info/$encodedName');
    return resp.data as Map<String, dynamic>;
  }
}
