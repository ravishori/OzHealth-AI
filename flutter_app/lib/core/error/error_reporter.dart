/// ErrorReporter — global client-side crash & error reporting.
///
/// Usage (automatic — wired in main.dart):
///   FlutterError.onError         → calls ErrorReporter.report()
///   PlatformDispatcher.onError   → calls ErrorReporter.report()
///   runZonedGuarded              → calls ErrorReporter.report()
///
/// The reporter is fire-and-forget and never throws, so it is safe to call
/// from any error handler without risking a secondary crash.
///
/// Rate limiting: max [_kMaxPerWindow] reports per [_kWindow] to avoid
/// flooding developers' inboxes on repeated errors (e.g. a rebuilding loop).
library error_reporter;

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:vitapulse_ai/core/network/server_discovery.dart';
import 'package:vitapulse_ai/core/utils/debug_logger.dart';

class ErrorReporter {
  ErrorReporter._();

  // ── Rate limiting ─────────────────────────────────────────────────────────
  static const int _kMaxPerWindow = 10;
  static const Duration _kWindow = Duration(minutes: 5);

  static int _windowCount = 0;
  static DateTime? _windowStart;

  // ── Cached Dio instance for error reporting ───────────────────────────────
  // Uses a separate Dio so a broken ApiClient can't prevent error reports.
  static Dio? _dio;

  static Dio _buildDio(String baseUrl) {
    return Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 6),
      sendTimeout: const Duration(seconds: 6),
      headers: {'Content-Type': 'application/json'},
    ));
  }

  // ── Optional user context ─────────────────────────────────────────────────
  static int? _userId;
  static String? _currentScreen;

  /// Call after login to attach user identity to future error reports.
  static void setUser(int? userId) => _userId = userId;

  /// Call on navigation events so errors include the current screen.
  static void setScreen(String? route) => _currentScreen = route;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Report an error. Never throws — safe to call from any context.
  static void report(
    Object error,
    StackTrace stackTrace, {
    String context = 'unknown',
  }) {
    // Rate-limit to avoid flooding on rapid repeated errors
    final now = DateTime.now();
    if (_windowStart == null ||
        now.difference(_windowStart!) > _kWindow) {
      _windowStart = now;
      _windowCount = 0;
    }
    _windowCount++;
    if (_windowCount > _kMaxPerWindow) {
      DebugLogger.warn(
        'ErrorReporter',
        'Rate limit reached ($_kMaxPerWindow per ${_kWindow.inMinutes} min) — '
        'skipping report for: ${error.runtimeType}',
      );
      return;
    }

    // Log locally first (always succeeds)
    DebugLogger.error(
      'ErrorReporter',
      '[$context] ${error.runtimeType}: $error',
      error,
    );

    // Fire-and-forget network report
    _sendReport(error, stackTrace, context: context);
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  static Future<void> _sendReport(
    Object error,
    StackTrace stackTrace, {
    required String context,
  }) async {
    try {
      // We need the server URL — use the cached value if available so we don't
      // block or trigger discovery during error handling.
      final baseUrl = ServerDiscovery.cachedUrl;
      if (baseUrl == null) {
        DebugLogger.warn('ErrorReporter',
            'Server URL not yet resolved — skipping remote report');
        return;
      }

      _dio ??= _buildDio(baseUrl);

      final String platform;
      try {
        platform = Platform.operatingSystem; // android, ios, windows, etc.
      } catch (_) {
        // Platform.operatingSystem throws on web — ignore
        return;
      }

      final payload = {
        'source': 'flutter',
        'context': context,
        'error_type': error.runtimeType.toString(),
        'message': _truncate(error.toString(), 1000),
        'stack_trace': _truncate(stackTrace.toString(), 5000),
        'platform': platform,
        'app_version': '1.0.0',
        if (_userId != null) 'user_id': _userId,
        if (_currentScreen != null) 'screen': _currentScreen,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };

      await _dio!.post('/errors/report', data: payload);
      DebugLogger.log('ErrorReporter', 'Error reported to server: ${error.runtimeType}');
    } on DioException catch (e) {
      // Network errors are expected when offline — just log locally
      DebugLogger.warn('ErrorReporter',
          'Could not send error report (network): ${e.type}');
    } catch (e) {
      // NEVER let error reporting crash the app
      DebugLogger.warn('ErrorReporter', 'Could not send error report: $e');
    }
  }

  static String _truncate(String s, int maxLen) =>
      s.length <= maxLen ? s : '${s.substring(0, maxLen)}…[truncated]';
}
