import 'package:vitapulse_ai/core/network/api_client.dart';

class EmergencyApi {
  static Future<List<dynamic>> getContacts() async {
    final resp = await ApiClient.get('/emergency/contacts');
    return resp.data as List<dynamic>;
  }

  static Future<Map<String, dynamic>> addContact(
      Map<String, dynamic> data) async {
    final resp = await ApiClient.post('/emergency/contacts', data: data);
    return resp.data as Map<String, dynamic>;
  }

  static Future<void> deleteContact(int id) async {
    await ApiClient.delete('/emergency/contacts/$id');
  }

  /// Triggers SOS: notifies emergency contacts and returns status.
  static Future<Map<String, dynamic>> sendSOS({
    double? latitude,
    double? longitude,
    String? message,
  }) async {
    final resp = await ApiClient.post('/emergency/sos', data: {
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (message != null) 'message': message,
    });
    return resp.data as Map<String, dynamic>;
  }
}
