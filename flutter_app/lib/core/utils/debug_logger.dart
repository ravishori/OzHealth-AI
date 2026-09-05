/// DebugLogger — structured file + console logger for HealthNest.
///
/// Usage:
///   DebugLogger.init();                        // call once at startup
///   DebugLogger.log('TAG', 'message');         // info
///   DebugLogger.error('TAG', 'msg', error);   // error
///   DebugLogger.request('POST', url, body);   // API request
///   DebugLogger.response(200, url, body);     // API response
///   await DebugLogger.exportPath();           // path to the log file
///   DebugLogger.recentLines(20);             // in-memory tail
library debug_logger;

import 'dart:io';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

enum _Level { info, warn, error, network }

class DebugLogger {
  DebugLogger._();

  static IOSink? _sink;
  static String? _logPath;
  static bool _ready = false;

  // In-memory ring buffer — last 200 lines shown in the debug panel
  static final Queue<_LogLine> _buffer = Queue();
  static const int _bufferSize = 200;

  // Listeners notified on every new line (for live debug panel)
  static final List<VoidCallback> _listeners = [];

  static void addListener(VoidCallback cb) => _listeners.add(cb);
  static void removeListener(VoidCallback cb) => _listeners.remove(cb);

  // ─── Init ─────────────────────────────────────────────────────────────────

  static Future<void> init() async {
    if (_ready) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logPath = '${dir.path}/vitapulse_debug.log';
      final file = File(_logPath!);
      _sink = file.openWrite(mode: FileMode.append);
      _ready = true;
      log('DebugLogger', '════ Session started ════  log: $_logPath');
    } catch (e) {
      debugPrint('[DebugLogger] Could not open log file: $e');
    }
  }

  // ─── Public API ───────────────────────────────────────────────────────────

  static void log(String tag, String message) =>
      _write(_Level.info, tag, message);

  static void warn(String tag, String message) =>
      _write(_Level.warn, tag, message);

  static void error(String tag, String message, [Object? err, StackTrace? st]) {
    _write(_Level.error, tag, message);
    if (err != null) _write(_Level.error, tag, '  error: $err');
    if (st != null)  _write(_Level.error, tag, '  stack: ${st.toString().split('\n').take(5).join(' | ')}');
  }

  /// Log an outbound HTTP request without payload bodies.
  ///
  /// Sensitive health/auth bodies must never be written to ordinary logs.
  /// Prefer method + URL only.
  static void request(String method, String url, [dynamic body]) {
    _write(_Level.network, 'REQ', '$method $url');
    // Intentionally ignore [body] — truncation is not safe for PHI.
  }

  /// Log an HTTP response without payload bodies.
  static void response(int statusCode, String url, [dynamic body]) {
    final level = statusCode >= 400 ? _Level.error : _Level.network;
    _write(level, 'RES', '$statusCode $url');
    // Intentionally ignore [body] — truncation is not safe for PHI.
  }

  static void connectionTest(String url, bool success, {String? detail}) {
    final tag = success ? 'PING_OK' : 'PING_FAIL';
    final lvl = success ? _Level.network : _Level.error;
    _write(lvl, tag, url + (detail != null ? '  [$detail]' : ''));
  }

  // ─── Access ───────────────────────────────────────────────────────────────

  /// Returns the filesystem path to the current log file.
  static String? get logFilePath => _logPath;

  /// Returns the last [n] lines from the in-memory buffer.
  // ignore: library_private_types_in_public_api
  static List<_LogLine> recentLines([int n = 50]) {
    final list = _buffer.toList();
    return list.length > n ? list.sublist(list.length - n) : list;
  }

  /// Concatenated recent log text for assertions (tests / debug panel).
  static String recentText([int n = 50]) {
    return recentLines(n)
        .map((e) => '${e.timestamp} ${e.tag} ${e.message}')
        .join('\n');
  }

  /// Clear the in-memory buffer (tests only).
  @visibleForTesting
  static void clearBufferForTest() {
    _buffer.clear();
  }

  /// Flush and close the file sink (call on app dispose if needed).
  static Future<void> close() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
    _ready = false;
  }

  // ─── Internal ─────────────────────────────────────────────────────────────

  static final _dateFmt = DateFormat('yyyy-MM-dd HH:mm:ss.SSS');

  static void _write(_Level level, String tag, String message) {
    final now = _dateFmt.format(DateTime.now());
    final prefix = _levelPrefix(level);
    final line = '$now $prefix [$tag] $message';

    // Console
    debugPrint(line);

    // File
    try {
      _sink?.writeln(line);
    } catch (_) {}

    // Buffer
    final entry = _LogLine(level: level, tag: tag, message: message, timestamp: now);
    _buffer.addLast(entry);
    if (_buffer.length > _bufferSize) _buffer.removeFirst();

    // Notify listeners (debug panel)
    for (final cb in List.of(_listeners)) {
      try { cb(); } catch (_) {}
    }
  }

  static String _levelPrefix(_Level l) {
    switch (l) {
      case _Level.info:    return 'I';
      case _Level.warn:    return 'W';
      case _Level.error:   return 'E';
      case _Level.network: return 'N';
    }
  }

  /// Mask sensitive fields (password, token, otp) when a caller explicitly
  /// asks to sanitize a diagnostic string. Not used for ApiClient bodies.
  @visibleForTesting
  static String safeBody(dynamic body) => _safeBody(body);

  /// Mask sensitive fields (password, token, otp) in request bodies.
  static String _safeBody(dynamic body) {
    try {
      var s = body.toString();
      // Mask OTP codes
      s = s.replaceAllMapped(
        RegExp(r'(otp_code["\s:]+)(\d{4,8})', caseSensitive: false),
        (m) => '${m[1]}******',
      );
      // Mask tokens
      s = s.replaceAllMapped(
        RegExp(r'(token["\s:]+)([A-Za-z0-9.\-_]{10,})', caseSensitive: false),
        (m) => '${m[1]}${m[2]!.substring(0, 8)}…[masked]',
      );
      // Mask Authorization headers if present in a string dump
      s = s.replaceAllMapped(
        RegExp(r'(Bearer\s+)([A-Za-z0-9.\-_]+)', caseSensitive: false),
        (m) => '${m[1]}[masked]',
      );
      return s.length > 500 ? '${s.substring(0, 500)}…[truncated]' : s;
    } catch (_) {
      return '[unserializable body]';
    }
  }
}

class _LogLine {
  final _Level level;
  final String tag;
  final String message;
  final String timestamp;

  const _LogLine({
    required this.level,
    required this.tag,
    required this.message,
    required this.timestamp,
  });

  bool get isError   => level == _Level.error;
  bool get isWarning => level == _Level.warn;
  bool get isNetwork => level == _Level.network;

  String get full => '$timestamp ${_icon(level)} [$tag] $message';

  static String _icon(_Level l) {
    switch (l) {
      case _Level.info:    return 'ℹ';
      case _Level.warn:    return '⚠';
      case _Level.error:   return '✖';
      case _Level.network: return '⇄';
    }
  }
}
