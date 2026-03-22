import 'package:vitapulse_ai/core/network/api_client.dart';

class AiApi {
  /// Send a chat message. Returns AI reply + conversation_id.
  static Future<Map<String, dynamic>> chat({
    required String message,
    int? conversationId,
    String contextType = 'general',
  }) async {
    final resp = await ApiClient.post('/ai/chat', data: {
      'message': message,
      if (conversationId != null) 'conversation_id': conversationId,
      'context_type': contextType,
    });
    return resp.data as Map<String, dynamic>;
  }

  /// Get contextual health guidance based on recent metric values.
  static Future<Map<String, dynamic>> healthGuidance({
    required String query,
    String? metricType,
    List<double>? recentValues,
  }) async {
    final resp = await ApiClient.post('/ai/health-guidance', data: {
      'query': query,
      if (metricType != null) 'metric_type': metricType,
      if (recentValues != null) 'recent_values': recentValues,
    });
    return resp.data as Map<String, dynamic>;
  }

  /// List past conversations (summaries).
  static Future<List<dynamic>> getConversations() async {
    final resp = await ApiClient.get('/ai/conversations');
    return resp.data as List<dynamic>;
  }

  /// Full conversation with all messages.
  static Future<Map<String, dynamic>> getConversation(int id) async {
    final resp = await ApiClient.get('/ai/conversations/$id');
    return resp.data as Map<String, dynamic>;
  }
}
