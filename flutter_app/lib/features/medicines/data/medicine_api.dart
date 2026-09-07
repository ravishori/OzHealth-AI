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

  /// HN-MED-009 — whether the current user favourited this catalogue medicine.
  /// Bookmark only — not a prescription or clinical recommendation.
  static Future<bool> getFavouriteStatus(int medicineId) async {
    final resp = await ApiClient.get('/medicines/$medicineId/favourite');
    final data = resp.data as Map<String, dynamic>;
    return data['is_favourite'] == true;
  }

  /// HN-MED-009 — add favourite (idempotent). Returns is_favourite.
  static Future<bool> addFavourite(int medicineId) async {
    final resp = await ApiClient.post('/medicines/$medicineId/favourite');
    final data = resp.data as Map<String, dynamic>;
    return data['is_favourite'] == true;
  }

  /// HN-MED-009 — remove favourite (idempotent). Returns is_favourite (false).
  static Future<bool> removeFavourite(int medicineId) async {
    final resp = await ApiClient.delete('/medicines/$medicineId/favourite');
    final data = resp.data as Map<String, dynamic>;
    return data['is_favourite'] == true;
  }

  /// HN-MED-009 — list current user's favourite medicines (auth-scoped).
  static Future<List<Map<String, dynamic>>> listFavourites() async {
    final resp = await ApiClient.get('/medicines/favourites');
    final data = resp.data as Map<String, dynamic>;
    final raw = data['favourites'];
    if (raw is! List) return [];
    return raw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }
}
