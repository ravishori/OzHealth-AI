import 'package:vitapulse_ai/core/network/api_client.dart';

class FamilyApi {
  static Future<List<dynamic>> getMembers() async {
    final resp = await ApiClient.get('/family/');
    return resp.data as List<dynamic>;
  }

  static Future<Map<String, dynamic>> getMember(int id) async {
    final resp = await ApiClient.get('/family/$id');
    return resp.data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> addMember(Map<String, dynamic> data) async {
    final resp = await ApiClient.post('/family/', data: data);
    return resp.data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> updateMember(
      int id, Map<String, dynamic> data) async {
    final resp = await ApiClient.put('/family/$id', data: data);
    return resp.data as Map<String, dynamic>;
  }

  static Future<void> deleteMember(int id) async {
    await ApiClient.delete('/family/$id');
  }
}
