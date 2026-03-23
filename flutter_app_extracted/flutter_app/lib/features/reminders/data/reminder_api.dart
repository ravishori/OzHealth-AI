import 'package:vitapulse_ai/core/network/api_client.dart';

class ReminderApi {
  static Future<List<dynamic>> getReminders() async {
    final resp = await ApiClient.get('/reminders/');
    return resp.data as List<dynamic>;
  }

  static Future<Map<String, dynamic>> createReminder(
      Map<String, dynamic> data) async {
    final resp = await ApiClient.post('/reminders/', data: data);
    return resp.data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> updateReminder(
      int id, Map<String, dynamic> data) async {
    final resp = await ApiClient.put('/reminders/$id', data: data);
    return resp.data as Map<String, dynamic>;
  }

  static Future<void> deleteReminder(int id) async {
    await ApiClient.delete('/reminders/$id');
  }

  static Future<Map<String, dynamic>> toggleReminder(
      int id, bool isActive) async {
    final resp =
        await ApiClient.put('/reminders/$id', data: {'is_active': isActive});
    return resp.data as Map<String, dynamic>;
  }
}
