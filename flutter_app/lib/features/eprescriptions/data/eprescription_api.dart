import 'dart:io';

import 'package:dio/dio.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';

/// API client for the ePrescription feature.
///
/// All methods throw [AppError] on HTTP/network failures — the caller should
/// catch and display the [AppError.message] to the user.
class EPrescriptionApi {
  EPrescriptionApi._();

  // ── Validate (scan / enter token) ─────────────────────────────────────────

  /// Validate a raw QR token or manual token against eRx Script Exchange (NPDS).
  ///
  /// Returns the full [EPrescriptionResponse] map on success.
  /// The backend handles URL-unwrapping, hashing, and TGA enrichment.
  static Future<Map<String, dynamic>> validateToken({
    required String token,
  }) async {
    final resp = await ApiClient.post('/eprescriptions/validate', data: {
      'token':    token,
      'provider': 'erx',
    });
    return resp.data as Map<String, dynamic>;
  }

  // ── Extract token from image ───────────────────────────────────────────────

  /// Upload a JPEG/PNG image and let the backend decode the QR code.
  /// Returns `{ 'token': '...', 'provider': 'erx' }`.
  static Future<Map<String, dynamic>> extractTokenFromImage(File image) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        image.path,
        filename: image.path.split(Platform.pathSeparator).last,
      ),
    });
    final resp = await ApiClient.uploadFile(
      '/eprescriptions/extract-token',
      formData,
    );
    return resp.data as Map<String, dynamic>;
  }

  // ── List ───────────────────────────────────────────────────────────────────

  /// List all ePrescriptions for the current user (newest first).
  static Future<List<Map<String, dynamic>>> list() async {
    final resp = await ApiClient.get('/eprescriptions/');
    final raw = resp.data as List<dynamic>? ?? [];
    return raw.cast<Map<String, dynamic>>();
  }

  // ── Detail ─────────────────────────────────────────────────────────────────

  /// Fetch full detail for a single ePrescription.
  static Future<Map<String, dynamic>> get(int id) async {
    final resp = await ApiClient.get('/eprescriptions/$id');
    return resp.data as Map<String, dynamic>;
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  /// Permanently delete an ePrescription record.
  static Future<void> delete(int id) async {
    await ApiClient.delete('/eprescriptions/$id');
  }

  // ── Auto-save to records ───────────────────────────────────────────────────

  /// Mark prescription as saved to medical records.
  /// Returns `{ 'saved_to_records': true, 'message': '...' }`.
  static Future<Map<String, dynamic>> saveToRecords(int id) async {
    final resp = await ApiClient.post('/eprescriptions/$id/save-to-records');
    return resp.data as Map<String, dynamic>;
  }

  /// Remove saved-to-records flag.
  static Future<Map<String, dynamic>> unsaveFromRecords(int id) async {
    final resp = await ApiClient.delete('/eprescriptions/$id/save-to-records');
    return resp.data as Map<String, dynamic>;
  }

  // ── Refill reminders ───────────────────────────────────────────────────────

  /// Add a refill reminder for a medicine in this prescription.
  static Future<Map<String, dynamic>> addRefillReminder({
    required int    epId,
    required String medicineName,
    required DateTime refillDate,
    String? note,
  }) async {
    final resp = await ApiClient.post(
      '/eprescriptions/$epId/refill-reminders',
      data: {
        'medicine_name': medicineName,
        'refill_date':   refillDate.toUtc().toIso8601String(),
        if (note != null) 'note': note,
      },
    );
    return resp.data as Map<String, dynamic>;
  }

  /// List all refill reminders for a prescription.
  static Future<List<Map<String, dynamic>>> getRefillReminders(int epId) async {
    final resp = await ApiClient.get('/eprescriptions/$epId/refill-reminders');
    final raw = resp.data as List<dynamic>? ?? [];
    return raw.cast<Map<String, dynamic>>();
  }

  /// Delete a refill reminder.
  static Future<void> deleteRefillReminder(int epId, int reminderId) async {
    await ApiClient.delete('/eprescriptions/$epId/refill-reminders/$reminderId');
  }

  // ── Drug interactions ──────────────────────────────────────────────────────

  /// Run AI drug-interaction check on all medicines in this ePrescription.
  /// Returns `{ 'medicines_checked': [...], 'interaction_analysis': {...}, ... }`.
  static Future<Map<String, dynamic>> checkInteractions(int epId) async {
    final resp = await ApiClient.post('/eprescriptions/$epId/interactions');
    return resp.data as Map<String, dynamic>;
  }

  // ── Share with family ──────────────────────────────────────────────────────

  /// Share this prescription with a family member.
  static Future<Map<String, dynamic>> share(int epId, int familyMemberId) async {
    final resp = await ApiClient.post(
      '/eprescriptions/$epId/share',
      data: {'family_member_id': familyMemberId},
    );
    return resp.data as Map<String, dynamic>;
  }

  /// List family members this prescription is shared with.
  static Future<List<Map<String, dynamic>>> getShares(int epId) async {
    final resp = await ApiClient.get('/eprescriptions/$epId/shares');
    final raw = resp.data as List<dynamic>? ?? [];
    return raw.cast<Map<String, dynamic>>();
  }

  /// Revoke a share.
  static Future<void> revokeShare(int epId, int shareId) async {
    await ApiClient.delete('/eprescriptions/$epId/share/$shareId');
  }
}
