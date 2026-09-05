/// Converts raw [DioException] / any Exception into a user-friendly
/// single-line message. Never exposes internal stack-traces or raw
/// Dio output to the UI.
library error_handler;

import 'package:flutter/material.dart';
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

  /// ✅ Returns a friendly message
  static String getMessage(Object e) {
    if (e is AppError) return e.message;
    if (e is DioException) return _fromDio(e);
    return 'Something went wrong. Please try again.';
  }

  /// ✅ Show error in UI (SnackBar)
  static void show(BuildContext context, Object e) {
    final message = getMessage(e);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  /// ✅ Throw clean error instead of raw DioException
  static Never throwFriendly(DioException e) {
    throw AppError(_fromDio(e), statusCode: e.response?.statusCode);
  }

  // ─────────────────────────── private ───────────────────────────────────────

  static String _fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.connectionError:
        return 'Something went wrong. Please try again later.';

      case DioExceptionType.cancel:
        return 'Request was cancelled.';

      default:
        break;
    }

    final statusCode = e.response?.statusCode;
    final data = e.response?.data;

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
      case 502:
      case 503:
      case 504:
        return 'Something went wrong. Please try again later.';

      default:
        return backendMsg ?? 'Something went wrong. Please try again later.';
    }
  }

  static String? _extractBackendMessage(dynamic data) {
    if (data is Map) {
      final msg = data['message'] ?? data['detail'];
      if (msg is String && msg.isNotEmpty) return msg;
    }
    return null;
  }

  static String _extract422Message(dynamic data) {
    if (data is Map) {
      final details = data['details'] as List?;
      if (details != null && details.isNotEmpty) {
        final first = details.first as Map?;
        final field = first?['field']?.toString() ?? '';
        final msg = first?['message']?.toString() ?? '';

        if (field.isNotEmpty && msg.isNotEmpty) return '$field: $msg';
        if (msg.isNotEmpty) return msg;
      }

      final backendMsg = _extractBackendMessage(data);
      if (backendMsg != null) return backendMsg;
    }

    return 'Validation failed. Please check your input.';
  }
}