import 'package:vitapulse_ai/core/network/api_client.dart';

class NearbyApi {
  /// [type]: hospital | pharmacy | lab | clinic
  static Future<List<dynamic>> getNearby({
    required double latitude,
    required double longitude,
    String type = 'hospital',
    int radiusMeters = 5000,
  }) async {
    final resp = await ApiClient.get('/nearby/', queryParameters: {
      'lat': latitude,
      'lng': longitude,
      'type': type,
      'radius': radiusMeters,
    });
    return resp.data as List<dynamic>;
  }
}
