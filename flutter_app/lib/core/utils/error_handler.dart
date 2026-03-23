/// Converts raw [DioException] / any Exception into a user-friendly
/// single-line message.  Never exposes internal stack-traces or raw
/// Dio output to the UI.
library error_handler;

import 'package:dio/dio.dart';

class AppError implements Exception {
  final String message;
  final int? statusCode;
  const AppError(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class ErrorHandler {
  ErrorHandler._();

  /// Returns a friendly [String] for any exception.
  static String getMessage(Object e) {
    if (e is AppError) return e.message;
    if (e is DioException) return _fromDio(e);
    return 'Something went wrong. Please try again.';
  }

  /// Throws [AppError] with a friendly message instead of raw [DioException].
  static Never throwFriendly(DioException e) {
    throw AppError(_fromDio(e), statusCode: e.response?.statusCode);
  }

  // ─────────────────────────── private ───────────────────────────────────────

  static String _fromDio(DioException e) {
    // ── Connection / timeout errors (no HTTP response) ──────────────────────
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'Connection timed out. Check your internet and try again.';
      case DioExceptionType.connectionError:
        return 'Could not reach the server. Check your connection.';
      case DioExceptionType.cancel:
        return 'Request was cancelled.';
      default:
        break;
    }

    final statusCode = e.response?.statusCode;
    final data = e.response?.data;

    // ── Try to extract backend message first ─────────────────────────────────
    final backendMsg = _extractBackendMessage(data);

    switch (statusCode) {
      case 400:
        return backendMsg ?? 'Invalid request. Please check your input.';

      case 401:
        return 'Session expired. Please login again.';

      case 403:
        return 'You don\'t have permission to do that.';

      case 404:
        return backendMsg ?? 'The requested resource was not found.';

      case 409:
        return backendMsg ?? 'A conflict occurred. This item may already exist.';

      case 422:
        return _extract422Message(data);

      case 429:
        final retryAfter = e.response?.headers.value('retry-after');
        if (retryAfter != null) {
          final seconds = int.tryParse(retryAfter) ?? 0;
          if (seconds > 60) {
            final mins = (seconds / 60).ceil();
            return 'Too many attempts. Please wait $mins minute${mins == 1 ? '' : 's'} before trying again.';
          }
          return 'Too many attempts. Please wait $retryAfter seconds before trying again.';
        }
        return backendMsg ?? 'Too many attempts. Please wait a moment and try again.';

      case 500:
        return 'Server error. Our team has been notified. Please try again later.';

      case 502:
      case 503:
      case 504:
        return 'Service temporarily unavailable. Please try again in a moment.';

      default:
        return backendMsg ?? 'An error occurred (code $statusCode). Please try again.';
    }
  }

  /// Extract message from backend JSON: { "message": "..." } or { "detail": "..." }
  static String? _extractBackendMessage(dynamic data) {
    if (data is Map) {
      final msg = data['message'] ?? data['detail'];
      if (msg is String && msg.isNotEmpty) return msg;
    }
    return null;
  }

  /// Extract readable message from Pydantic 422 validation errors.
  static String _extract422Message(dynamic data) {
    if (data is Map) {
      final details = data['details'] as List?;
      if (details != null && details.isNotEmpty) {
        final first = details.first as Map?;
        final field = first?['field']?.toString() ?? '';
        final msg   = first?['message']?.toString() ?? '';
        if (field.isNotEmpty && msg.isNotEmpty) return '$field: $msg';
        if (msg.isNotEmpty) return msg;
      }
      final backendMsg = _extractBackendMessage(data);
      if (backendMsg != null) return backendMsg;
    }
    return 'Validation failed. Please check your input.';
  }
}
