import 'package:dio/dio.dart';
import 'package:vitapulse_ai/features/settings/data/app_info.dart';

/// Result of a Nominatim reverse-geocode for profile address fill.
///
/// Coordinates and provider payloads are intentionally not retained beyond
/// this result. Callers must not log [suburb]/[city]/[postcode], or raw
/// provider errors.
class NominatimReverseResult {
  final bool ok;
  final String? suburb;
  final String? city;
  final String? stateFull;
  final String? postcode;
  final String safeMessage;

  const NominatimReverseResult._({
    required this.ok,
    this.suburb,
    this.city,
    this.stateFull,
    this.postcode,
    required this.safeMessage,
  });

  factory NominatimReverseResult.success({
    required String suburb,
    required String city,
    required String stateFull,
    required String postcode,
  }) {
    return NominatimReverseResult._(
      ok: true,
      suburb: suburb,
      city: city,
      stateFull: stateFull,
      postcode: postcode,
      safeMessage: '',
    );
  }

  factory NominatimReverseResult.notAustralian() {
    return const NominatimReverseResult._(
      ok: false,
      safeMessage: 'Could not detect an Australian address.',
    );
  }

  factory NominatimReverseResult.failed() {
    return const NominatimReverseResult._(
      ok: false,
      safeMessage: 'Address lookup failed. Please enter address manually.',
    );
  }

  factory NominatimReverseResult.busy() {
    return const NominatimReverseResult._(
      ok: false,
      safeMessage: 'Please wait a moment before looking up again.',
    );
  }
}

/// Client-side Nominatim reverse geocoder used by the profile address sheet.
///
/// Hygiene implemented locally (does not claim production ToS certification):
/// - identifying User-Agent with app name/version + existing support contact
/// - bounded connect + receive timeouts
/// - minimum interval between network calls (~1 req/s)
/// - short in-memory cache for identical rounded coordinates
/// - no coordinate/address/response-body logging
class NominatimReverseGeocode {
  NominatimReverseGeocode({
    Dio? dio,
    this.minInterval = const Duration(milliseconds: 1100),
    this.connectTimeout = const Duration(seconds: 8),
    this.receiveTimeout = const Duration(seconds: 10),
  }) : _dio = dio ?? Dio();

  static const endpoint = 'https://nominatim.openstreetmap.org/reverse';

  /// Stable app identity + existing support mailbox (AppInfo).
  /// Do not spoof a browser UA; do not embed secrets.
  static String get userAgent =>
      '${AppInfo.appName}/${AppInfo.versionName} '
      '(profile reverse-geocode; contact: ${AppInfo.supportEmail})';

  static const attribution =
      'Address lookup uses OpenStreetMap data © OpenStreetMap contributors';

  final Dio _dio;
  final Duration minInterval;
  final Duration connectTimeout;
  final Duration receiveTimeout;

  DateTime? _lastNetworkAt;
  String? _cacheKey;
  NominatimReverseResult? _cacheValue;
  Future<NominatimReverseResult>? _inFlight;
  String? _inFlightKey;

  /// Round coordinates to reduce duplicate lookups (~11 m at 4 dp).
  static String cacheKeyFor(double lat, double lon) {
    return '${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)}';
  }

  Future<NominatimReverseResult> reverse({
    required double latitude,
    required double longitude,
  }) async {
    final key = cacheKeyFor(latitude, longitude);

    if (_cacheKey == key && _cacheValue != null) {
      return _cacheValue!;
    }

    if (_inFlight != null && _inFlightKey == key) {
      return _inFlight!;
    }

    final now = DateTime.now();
    if (_lastNetworkAt != null &&
        now.difference(_lastNetworkAt!) < minInterval &&
        _cacheKey != key) {
      return NominatimReverseResult.busy();
    }

    final future = _fetch(latitude: latitude, longitude: longitude, key: key);
    _inFlight = future;
    _inFlightKey = key;
    try {
      return await future;
    } finally {
      if (identical(_inFlight, future)) {
        _inFlight = null;
        _inFlightKey = null;
      }
    }
  }

  Future<NominatimReverseResult> _fetch({
    required double latitude,
    required double longitude,
    required String key,
  }) async {
    try {
      _lastNetworkAt = DateTime.now();
      final resp = await _dio.get<Map<String, dynamic>>(
        endpoint,
        queryParameters: <String, dynamic>{
          'lat': latitude,
          'lon': longitude,
          'format': 'json',
          'addressdetails': 1,
        },
        options: Options(
          headers: <String, dynamic>{
            'User-Agent': userAgent,
            'Accept': 'application/json',
          },
          connectTimeout: connectTimeout,
          receiveTimeout: receiveTimeout,
          sendTimeout: connectTimeout,
          responseType: ResponseType.json,
          validateStatus: (code) => code != null && code >= 200 && code < 300,
        ),
      );

      final data = resp.data;
      if (data == null) return NominatimReverseResult.failed();

      final addr = data['address'];
      if (addr is! Map) return NominatimReverseResult.failed();
      final map = Map<String, dynamic>.from(addr);

      final country = (map['country_code'] ?? '').toString().toLowerCase();
      if (country != 'au') {
        final notAu = NominatimReverseResult.notAustralian();
        _cacheKey = key;
        _cacheValue = notAu;
        return notAu;
      }

      final suburb = (map['suburb'] ??
              map['neighbourhood'] ??
              map['hamlet'] ??
              map['village'] ??
              '')
          .toString();
      final city =
          (map['city'] ?? map['town'] ?? map['city_district'] ?? '').toString();
      final stateFull = (map['state'] ?? '').toString();
      final postcode = (map['postcode'] ?? '').toString();

      final ok = NominatimReverseResult.success(
        suburb: suburb,
        city: city,
        stateFull: stateFull,
        postcode: postcode,
      );
      _cacheKey = key;
      _cacheValue = ok;
      return ok;
    } on DioException {
      return NominatimReverseResult.failed();
    } catch (_) {
      return NominatimReverseResult.failed();
    }
  }
}
