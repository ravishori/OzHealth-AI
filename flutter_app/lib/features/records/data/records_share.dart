import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';

/// Safe share filename: `medical_record_<type>_<date>.<ext>`
/// Never includes record ids, titles, notes, or original filenames.
String safeMedicalRecordShareFilename({
  String? recordType,
  String? recordDate,
  String? createdAt,
  String? fileType,
  String? originalFileName,
}) {
  final type = _safeToken(recordType) ?? 'record';
  final date = _dateToken(recordDate) ?? _dateToken(createdAt) ?? 'undated';
  final ext = _safeExtension(fileType, originalFileName);
  return 'medical_record_${type}_$date.$ext';
}

String? _safeToken(String? raw) {
  if (raw == null) return null;
  final cleaned = raw
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  if (cleaned.isEmpty) return null;
  return cleaned.length > 32 ? cleaned.substring(0, 32) : cleaned;
}

String? _dateToken(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final parsed = DateTime.tryParse(raw.trim());
  if (parsed == null) return null;
  final y = parsed.year.toString().padLeft(4, '0');
  final m = parsed.month.toString().padLeft(2, '0');
  final d = parsed.day.toString().padLeft(2, '0');
  return '$y$m$d';
}

String _safeExtension(String? fileType, String? originalFileName) {
  final fromType = _safeToken(fileType);
  if (fromType != null && fromType.length <= 5 && !fromType.contains('_')) {
    return fromType;
  }
  final name = originalFileName ?? '';
  final dot = name.lastIndexOf('.');
  if (dot >= 0 && dot < name.length - 1) {
    final ext = _safeToken(name.substring(dot + 1));
    if (ext != null && ext.length <= 5 && !ext.contains('_')) return ext;
  }
  return 'bin';
}

/// Owner-authenticated download → temp file → native share sheet.
///
/// Does not log file bytes or clinical content. Does not create public URLs.
class RecordsShare {
  RecordsShare._();

  static Future<List<int>> defaultDownload(int recordId) async {
    final resp = await ApiClient.downloadBytes('/records/$recordId/file');
    final bytes = resp.data;
    if (bytes is! List<int>) {
      throw StateError('Unexpected file payload');
    }
    return bytes;
  }

  static Future<void> shareOwnedRecord({
    required int recordId,
    required Map<String, dynamic> record,
    Future<List<int>> Function(int recordId)? download,
    Future<void> Function(String path)? sharePath,
    Future<Directory> Function()? temporaryDirectory,
  }) async {
    final bytes = await (download ?? defaultDownload)(recordId);
    final dir = await (temporaryDirectory ?? getTemporaryDirectory)();
    final name = safeMedicalRecordShareFilename(
      recordType: record['record_type']?.toString(),
      recordDate: record['record_date']?.toString(),
      createdAt: record['created_at']?.toString(),
      fileType: record['file_type']?.toString(),
      originalFileName: record['file_name']?.toString(),
    );
    final path = '${dir.path}${Platform.pathSeparator}$name';
    final file = File(path);
    try {
      await file.writeAsBytes(bytes, flush: true);
      if (sharePath != null) {
        await sharePath(path);
      } else {
        await Share.shareXFiles(
          [XFile(path)],
          subject: 'HealthNest medical record',
        );
      }
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }
}
