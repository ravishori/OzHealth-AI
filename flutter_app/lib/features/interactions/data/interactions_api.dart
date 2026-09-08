import 'package:vitapulse_ai/core/network/api_client.dart';

class InteractionsApi {
  /// Source-grounded interaction check.
  /// Prefer [medicineIds] from catalogue search; [medicines] names are resolved server-side.
  static Future<Map<String, dynamic>> checkInteractions({
    List<int>? medicineIds,
    List<String>? medicines,
    bool includeDuplicateCheck = true,
  }) async {
    final resp = await ApiClient.post(
      '/interactions/check',
      data: {
        if (medicineIds != null && medicineIds.isNotEmpty)
          'medicine_ids': medicineIds,
        if (medicines != null && medicines.isNotEmpty) 'medicines': medicines,
        'include_duplicate_check': includeDuplicateCheck,
      },
    );
    return Map<String, dynamic>.from(resp.data as Map);
  }
}
