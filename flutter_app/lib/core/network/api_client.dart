/// ApiClient — Dio HTTP client with auto-discovered backend URL.
///
/// On the first request the client calls [ServerDiscovery.resolveBaseUrl()]
/// which probes all candidate URLs (emulator, localhost, LAN subnet) in
/// parallel and uses the first one that responds.  The result is cached for
/// the entire app session — no manual configuration required.
library api_client;

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:vitapulse_ai/core/utils/debug_logger.dart';
import 'package:vitapulse_ai/core/network/server_discovery.dart';
import 'package:vitapulse_ai/core/router/navigation_service.dart';

const _storage = FlutterSecureStorage();

class ApiClient {
  ApiClient._();

  static Dio? _dioInstance;
  static String? _activeBaseUrl;

  // ─── Lazy Dio instance ────────────────────────────────────────────────────

  /// Returns the Dio instance, initialising it with the discovered URL if
  /// it hasn't been created yet. Safe to call from any async context.
  static Future<Dio> get _dio async {
    if (_dioInstance != null) return _dioInstance!;

    // Resolve URL (discovery runs once and then returns cached value)
    final url = await ServerDiscovery.resolveBaseUrl();
    _activeBaseUrl = url;

    DebugLogger.log('ApiClient', 'Creating Dio  baseUrl=$url  platform=${_platformName()}');
    _dioInstance = _buildDio(url);
    return _dioInstance!;
  }

  // ─── Dio factory ─────────────────────────────────────────────────────────

  static Dio _buildDio(String baseUrl) {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout:    const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));

    // ── Interceptor 1: inject auth token + handle 401 refresh ───────────────
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: 'access_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          DebugLogger.warn('ApiClient', '401 — attempting token refresh');
          final refreshed = await _refreshToken(baseUrl);
          if (refreshed) {
            final token = await _storage.read(key: 'access_token');
            error.requestOptions.headers['Authorization'] = 'Bearer $token';
            try {
              final response = await dio.fetch(error.requestOptions);
              handler.resolve(response);
              return;
            } catch (retryErr) {
              DebugLogger.error('ApiClient', 'Retry after refresh failed', retryErr);
            }
          } else {
            // Both access and refresh tokens are expired — force logout.
            // Clear stored tokens so the next app launch goes to the login screen.
            DebugLogger.warn('ApiClient', 'Refresh failed — session fully expired, forcing logout');
            await _storage.delete(key: 'access_token');
            await _storage.delete(key: 'refresh_token');
            goToLogin();
          }
        }
        handler.next(DioException(
          requestOptions: error.requestOptions,
          response:       error.response,
          type:           error.type,
          error: AppError(
            ErrorHandler.getMessage(error),
            statusCode: error.response?.statusCode,
          ),
        ));
      },
    ));

    // ── Interceptor 2: request / response metadata logger (no PHI bodies) ──
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        DebugLogger.request(options.method, options.uri.toString());
        handler.next(options);
      },
      onResponse: (response, handler) {
        DebugLogger.response(
          response.statusCode ?? 0,
          response.requestOptions.uri.toString(),
        );
        handler.next(response);
      },
      onError: (error, handler) {
        final category = _errorCategory(error);
        DebugLogger.error(
          'ApiClient',
          'DioError [$category]  status=${error.response?.statusCode}  '
          'url=${error.requestOptions.uri}',
          error.message,
        );
        // Do not log error.response.data — may contain PHI / secrets.
        if (error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.connectionError) {
          DebugLogger.warn('ApiClient',
            'Server unreachable at $baseUrl — '
            'call ApiClient.rediscover() or tap "Re-discover" in the debug panel');
        }
        handler.next(error);
      },
    ));

    return dio;
  }

  // ─── Token refresh ────────────────────────────────────────────────────────

  static Future<bool> _refreshToken(String baseUrl) async {
    try {
      final rt = await _storage.read(key: 'refresh_token');
      if (rt == null) { DebugLogger.warn('ApiClient', 'No refresh_token'); return false; }
      final resp = await Dio(BaseOptions(baseUrl: baseUrl))
          .post('/auth/refresh', data: {'refresh_token': rt});
      await _storage.write(key: 'access_token',  value: resp.data['access_token']);
      await _storage.write(key: 'refresh_token', value: resp.data['refresh_token']);
      DebugLogger.log('ApiClient', 'Token refresh OK');
      return true;
    } catch (e) {
      DebugLogger.error('ApiClient', 'Token refresh failed', e);
      return false;
    }
  }

  // ─── Connectivity check ───────────────────────────────────────────────────

  /// Pings the health endpoint using the currently active base URL.
  /// Returns null on success, or an error description string.
  static Future<String?> checkConnectivity() async {
    final url = ServerDiscovery.cachedUrl ?? await ServerDiscovery.resolveBaseUrl();
    DebugLogger.log('ApiClient', 'checkConnectivity  url=$url');
    try {
      final probe = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ));
      final baseOnly = url.replaceAll('/api/v1', '');
      final r = await probe.get('$baseOnly/health');
      final status = r.data?['status']?.toString() ?? 'unknown';
      DebugLogger.connectionTest(url, true, detail: 'status=$status');
      return null;
    } on DioException catch (e) {
      final detail = e.type == DioExceptionType.connectionTimeout ||
                     e.type == DioExceptionType.connectionError
          ? 'Cannot reach $url — run re-discovery'
          : 'HTTP ${e.response?.statusCode ?? "no response"}: ${e.message}';
      DebugLogger.connectionTest(url, false, detail: detail);
      return detail;
    } catch (e) {
      DebugLogger.connectionTest(url, false, detail: e.toString());
      return e.toString();
    }
  }

  /// Force re-runs URL discovery (e.g. after switching Wi-Fi).
  static Future<String> rediscover() async {
    _dioInstance = null;
    _activeBaseUrl = null;
    final url = await ServerDiscovery.rediscover();
    _activeBaseUrl = url;
    _dioInstance = _buildDio(url);
    DebugLogger.log('ApiClient', 'Re-discovery complete → $url');
    return url;
  }

  /// The currently active base URL (null before first request / discovery).
  static String? get activeBaseUrl => _activeBaseUrl ?? ServerDiscovery.cachedUrl;

  // ─── Public HTTP helpers ──────────────────────────────────────────────────

  static Future<Response> get(String path,
      {Map<String, dynamic>? queryParameters}) async =>
      (await _dio).get(path, queryParameters: queryParameters);

  static Future<Response> post(String path, {dynamic data, Options? options}) async =>
      (await _dio).post(path, data: data, options: options);

  static Future<Response> put(String path, {dynamic data}) async =>
      (await _dio).put(path, data: data);

  static Future<Response> delete(String path) async =>
      (await _dio).delete(path);

  static Future<Response> uploadFile(String path, FormData formData) async =>
      (await _dio).post(path,
          data: formData,
          options: Options(contentType: 'multipart/form-data'));

  /// Authenticated binary download (e.g. medical record files).
  static Future<Response> downloadBytes(String path) async =>
      (await _dio).get(
        path,
        options: Options(responseType: ResponseType.bytes),
      );

  // ─── Helpers ─────────────────────────────────────────────────────────────

  static String _errorCategory(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return 'CONNECTION_TIMEOUT (${e.requestOptions.connectTimeout?.inSeconds}s)';
      case DioExceptionType.receiveTimeout:
        return 'RECEIVE_TIMEOUT (${e.requestOptions.receiveTimeout?.inSeconds}s)';
      case DioExceptionType.sendTimeout:
        return 'SEND_TIMEOUT';
      case DioExceptionType.connectionError:
        return 'CONNECTION_ERROR';
      case DioExceptionType.badResponse:
        return 'HTTP_${e.response?.statusCode}';
      case DioExceptionType.cancel:
        return 'CANCELLED';
      default:
        return 'UNKNOWN';
    }
  }

  static String _platformName() {
    if (kIsWeb) return 'web';
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS)     return 'ios';
      if (Platform.isWindows) return 'windows';
      if (Platform.isMacOS)   return 'macos';
    } catch (_) {}
    return 'unknown';
  }
}

/// Convenience getter — returns the active base URL synchronously
/// once discovery has completed, or a sensible default before that.
String get baseUrl =>
    ApiClient.activeBaseUrl ?? 'http://10.0.2.2:8000/api/v1';
