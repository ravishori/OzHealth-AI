/// ServerDiscovery — automatically finds the backend server at runtime.
///
/// Priority order (all probed in parallel, fastest wins):
///   1. Android emulator loopback  →  10.0.2.2:8000
///   2. iOS simulator / web        →  localhost:8000
///   3. Local subnet scan          →  192.168.x.* / 10.x.x.* (real device on WiFi)
///
/// Result is cached for the app session so discovery only runs once.
/// Call [ServerDiscovery.resolveBaseUrl()] once at startup (e.g. in main.dart).
library server_discovery;

import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vitapulse_ai/core/config/app_env.dart';
import 'package:vitapulse_ai/core/utils/debug_logger.dart';

class ServerDiscovery {
  ServerDiscovery._();

  static const int    _port         = 8000;
  static const String _apiPrefix    = '/api/v1';
  static const String _healthPath   = '/health';
  static const Duration _probeTimeout = Duration(seconds: 2);
  static const String _fallback     = 'http://10.0.2.2:$_port$_apiPrefix';
  static const String _manualIpKey  = 'server_manual_ip';
  static const _storage             = FlutterSecureStorage();

  static String? _resolvedUrl;
  static bool    _discovering = false;
  static final List<Completer<String>> _waiters = [];

  // ─── Manual IP (persisted) ────────────────────────────────────────────────

  /// Save a user-provided IP (e.g. '192.168.1.5'). Clears the cached URL so
  /// the next [resolveBaseUrl] call will use this IP first.
  static Future<void> setManualIp(String ip) async {
    final trimmed = ip.trim();
    await _storage.write(key: _manualIpKey, value: trimmed);
    _resolvedUrl = null;
    _discovering = false;
    _waiters.clear();
    DebugLogger.log('ServerDiscovery', 'Manual IP saved → $trimmed');
  }

  /// Remove the manually-saved IP and revert to auto-discovery.
  static Future<void> clearManualIp() async {
    await _storage.delete(key: _manualIpKey);
    _resolvedUrl = null;
    _discovering = false;
    _waiters.clear();
    DebugLogger.log('ServerDiscovery', 'Manual IP cleared — will auto-discover');
  }

  /// Read the currently stored manual IP, or null if not set.
  static Future<String?> getManualIp() => _storage.read(key: _manualIpKey);

  // ─── Public API ──────────────────────────────────────────────────────────

  /// Returns the resolved base URL (e.g. 'http://192.168.1.5:8000/api/v1').
  /// Checks the user-saved manual IP first; falls back to auto-discovery.
  static Future<String> resolveBaseUrl() async {
    if (_resolvedUrl != null) return _resolvedUrl!;

    final configured = AppEnv.apiBaseUrl.trim();
    if (configured.isNotEmpty) {
      var url = configured;
      if (!url.contains('/api/v1')) {
        if (url.endsWith('/')) url = url.substring(0, url.length - 1);
        url = '$url/api/v1';
      }
      _resolvedUrl = url;
      DebugLogger.log('ServerDiscovery', 'Using compile-time API_BASE_URL');
      return _resolvedUrl!;
    }

    if (!AppEnv.allowLanDiscovery) {
      DebugLogger.error(
        'ServerDiscovery',
        'Release build has no API_BASE_URL — refusing LAN HTTP discovery',
      );
      _resolvedUrl = 'https://api.unconfigured.invalid/api/v1';
      return _resolvedUrl!;
    }

    // ── 1. Try user-saved manual IP ─────────────────────────────────────────
    try {
      final manualIp = await _storage.read(key: _manualIpKey);
      if (manualIp != null && manualIp.isNotEmpty) {
        final url = 'http://$manualIp:$_port$_apiPrefix';
        DebugLogger.log('ServerDiscovery', 'Manual IP found → probing $url');
        if (await _probe(url)) {
          _resolvedUrl = url;
          DebugLogger.log('ServerDiscovery', 'Manual URL reachable ✓ → $_resolvedUrl');
          return _resolvedUrl!;
        }
        DebugLogger.warn('ServerDiscovery',
            'Manual IP $manualIp did not respond — falling back to auto-discovery');
      }
    } catch (e) {
      DebugLogger.warn('ServerDiscovery', 'Manual IP read error: $e');
    }

    // ── 2. Auto-discovery ───────────────────────────────────────────────────
    // If discovery is already running, wait for it
    if (_discovering) {
      final c = Completer<String>();
      _waiters.add(c);
      return c.future;
    }

    _discovering = true;
    DebugLogger.log('ServerDiscovery', 'Starting backend discovery…');

    try {
      final candidates = await _buildCandidates();
      DebugLogger.log('ServerDiscovery',
          'Probing ${candidates.length} candidate(s) in parallel (timeout ${_probeTimeout.inSeconds}s each)');
      for (final c in candidates) {
        DebugLogger.log('ServerDiscovery', '  candidate: $c');
      }

      final url = await _probeAll(candidates);
      _resolvedUrl = url;
      DebugLogger.log('ServerDiscovery', 'Resolved → $_resolvedUrl');
    } catch (e) {
      _resolvedUrl = _fallback;
      DebugLogger.error('ServerDiscovery', 'Discovery failed, using fallback: $_fallback', e);
    } finally {
      _discovering = false;
    }

    // Unblock any waiters
    for (final c in _waiters) {
      c.complete(_resolvedUrl);
    }
    _waiters.clear();

    return _resolvedUrl!;
  }

  /// Force a re-discovery (e.g. after network change). Resets the cache.
  static Future<String> rediscover() async {
    _resolvedUrl = null;
    _discovering = false;
    _waiters.clear();
    DebugLogger.log('ServerDiscovery', 'Cache cleared — re-running discovery');
    return resolveBaseUrl();
  }

  /// Returns the cached URL synchronously, or null if not yet resolved.
  static String? get cachedUrl => _resolvedUrl;

  // ─── Candidate building ──────────────────────────────────────────────────

  static Future<List<String>> _buildCandidates() async {
    final urls = <String>{};

    if (kIsWeb) {
      urls.add('http://localhost:$_port$_apiPrefix');
      return urls.toList();
    }

    // ── Fixed well-known addresses ──────────────────────────────────────────
    if (Platform.isAndroid) {
      // Android emulator: host machine is always 10.0.2.2
      urls.add('http://10.0.2.2:$_port$_apiPrefix');
    }

    if (Platform.isIOS || Platform.isMacOS) {
      urls.add('http://localhost:$_port$_apiPrefix');
      urls.add('http://127.0.0.1:$_port$_apiPrefix');
    }

    if (Platform.isWindows || Platform.isLinux) {
      urls.add('http://localhost:$_port$_apiPrefix');
      urls.add('http://127.0.0.1:$_port$_apiPrefix');
    }

    // ── Local subnet scan (real device on Wi-Fi) ────────────────────────────
    // Get this device's own IPv4 addresses and derive the subnet.
    // The backend PC will be on the same subnet (e.g. 192.168.1.x).
    final subnets = await _getLocalSubnets();
    for (final subnet in subnets) {
      // Cover the full typical DHCP range 1-254 in priority order:
      //   • 1-20  : statics / router / server / early DHCP leases
      //   • 100-200 : common mid/high DHCP block (covers .132, .150, etc.)
      //   • 21-99  : less common mid statics
      //   • 201-254 : upper DHCP tail
      // All probes run in parallel so the list length doesn't add latency —
      // only the fastest responder matters.
      final lastOctets = [
        // Low statics & early DHCP (highest priority)
        ...List.generate(20, (i) => i + 1),     // 1-20
        // Full mid DHCP block — most desktop PCs land here
        ...List.generate(101, (i) => i + 100),  // 100-200
        // Remaining mid range
        ...List.generate(79, (i) => i + 21),    // 21-99
        // Upper tail
        ...List.generate(54, (i) => i + 201),   // 201-254
      ];
      for (final last in lastOctets) {
        urls.add('http://$subnet.$last:$_port$_apiPrefix');
      }

      // Try device's own octet neighbours (the PC is often on the same segment)
      final parts = subnet.split('.');
      if (parts.length == 3) {
        final deviceOctet = await _deviceLastOctet(subnet);
        if (deviceOctet != null) {
          for (final delta in [-2, -1, 1, 2, 3, 4]) {
            final candidate = deviceOctet + delta;
            if (candidate > 0 && candidate < 255) {
              urls.add('http://$subnet.$candidate:$_port$_apiPrefix');
            }
          }
        }
      }
    }

    return urls.toList();
  }

  /// Returns unique /24 subnet prefixes (e.g. ['192.168.1', '10.0.0']).
  static Future<List<String>> _getLocalSubnets() async {
    final subnets = <String>{};
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          // Skip emulator virtual adapter and loopback
          if (ip == '10.0.2.15' || ip.startsWith('127.')) continue;
          if (ip.startsWith('192.168.') ||
              ip.startsWith('10.')       ||
              ip.startsWith('172.')) {
            final parts = ip.split('.');
            if (parts.length == 4) {
              subnets.add('${parts[0]}.${parts[1]}.${parts[2]}');
              DebugLogger.log('ServerDiscovery',
                  'Found local interface: $ip  (subnet ${parts[0]}.${parts[1]}.${parts[2]}.*)');
            }
          }
        }
      }
    } catch (e) {
      DebugLogger.warn('ServerDiscovery', 'NetworkInterface.list() failed: $e');
    }
    return subnets.toList();
  }

  static Future<int?> _deviceLastOctet(String subnet) async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.address.startsWith('$subnet.')) {
            return int.tryParse(addr.address.split('.').last);
          }
        }
      }
    } catch (_) {}
    return null;
  }

  // ─── Parallel probing ────────────────────────────────────────────────────

  /// Probes all [candidates] in parallel and returns the URL of the fastest
  /// successful response. Falls back to [_fallback] if none respond.
  static Future<String> _probeAll(List<String> candidates) async {
    if (candidates.isEmpty) return _fallback;

    final completer = Completer<String>();
    int pending = candidates.length;

    for (final url in candidates) {
      _probe(url).then((ok) {
        if (ok && !completer.isCompleted) {
          DebugLogger.log('ServerDiscovery', '  ✓ Responded: $url');
          completer.complete(url);
        }
      }).catchError((_) {
        // ignore individual probe errors
      }).whenComplete(() {
        pending--;
        if (pending == 0 && !completer.isCompleted) {
          DebugLogger.warn('ServerDiscovery',
              'No server responded — using fallback: $_fallback');
          completer.complete(_fallback);
        }
      });
    }

    return completer.future;
  }

  /// Returns true if [baseUrl] responds to the health endpoint.
  static Future<bool> _probe(String baseUrl) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: _probeTimeout,
        receiveTimeout: _probeTimeout,
        sendTimeout: _probeTimeout,
      ));
      final resp = await dio.get('${_stripPrefix(baseUrl)}$_healthPath');
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Strips the /api/v1 suffix to build the health check URL.
  /// e.g. 'http://10.0.2.2:8000/api/v1' → 'http://10.0.2.2:8000'
  static String _stripPrefix(String url) {
    if (url.endsWith(_apiPrefix)) {
      return url.substring(0, url.length - _apiPrefix.length);
    }
    return url;
  }
}
