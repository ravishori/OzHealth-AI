import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/profile/data/nominatim_reverse_geocode.dart';
import 'package:vitapulse_ai/features/settings/data/app_info.dart';

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this._handler);

  final Future<ResponseBody> Function(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) _handler;

  int calls = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls += 1;
    return _handler(options, requestStream, cancelFuture);
  }
}

ResponseBody _jsonBody(Map<String, dynamic> json, {int status = 200}) {
  return ResponseBody.fromString(
    jsonEncode(json),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  final screenSrc =
      File('lib/features/profile/presentation/profile_screen.dart')
          .readAsStringSync();
  final geoSrc =
      File('lib/features/profile/data/nominatim_reverse_geocode.dart')
          .readAsStringSync();

  test('PROF-009-FL-01 identifying User-Agent uses AppInfo contact', () {
    expect(NominatimReverseGeocode.userAgent.contains(AppInfo.appName), isTrue);
    expect(
      NominatimReverseGeocode.userAgent.contains(AppInfo.versionName),
      isTrue,
    );
    expect(
      NominatimReverseGeocode.userAgent.contains(AppInfo.supportEmail),
      isTrue,
    );
    expect(NominatimReverseGeocode.userAgent.contains('Mozilla'), isFalse);
    expect(geoSrc.contains('User-Agent'), isTrue);
    expect(screenSrc.contains("User-Agent': 'HealthNest/1.0'"), isFalse);
  });

  test('PROF-009-FL-02 connect and receive timeouts are bounded', () {
    expect(geoSrc.contains('connectTimeout'), isTrue);
    expect(geoSrc.contains('receiveTimeout'), isTrue);
    expect(geoSrc.contains('Duration(seconds: 8)'), isTrue);
    expect(geoSrc.contains('Duration(seconds: 10)'), isTrue);
  });

  test('PROF-009-FL-03 OSM attribution is shown on address sheet', () {
    expect(screenSrc.contains('NominatimReverseGeocode.attribution'), isTrue);
    expect(
      NominatimReverseGeocode.attribution.contains('OpenStreetMap'),
      isTrue,
    );
  });

  test('PROF-009-FL-04 no sensitive coordinate/address/response logging', () {
    expect(geoSrc.contains('debugPrint'), isFalse);
    expect(geoSrc.contains('print('), isFalse);
    expect(geoSrc.contains('logger'), isFalse);
    expect(screenSrc.contains('debugPrint(pos'), isFalse);
    expect(screenSrc.contains('print(pos'), isFalse);
    expect(screenSrc.contains('print(result'), isFalse);
  });

  test('PROF-009-FL-05 existing address fields retained on failure path', () {
    expect(screenSrc.contains('priorSuburb'), isTrue);
    expect(screenSrc.contains('priorCity'), isTrue);
    expect(screenSrc.contains('priorPostcode'), isTrue);
    expect(screenSrc.contains('priorState'), isTrue);
    expect(screenSrc.contains('_suburbCtrl.text = priorSuburb'), isTrue);
  });

  test('PROF-009-FL-06 normal reverse geocode success', () async {
    final dio = Dio();
    late RequestOptions seen;
    dio.httpClientAdapter = _ScriptedAdapter((options, _, __) async {
      seen = options;
      return _jsonBody({
        'address': {
          'suburb': 'Richmond',
          'city': 'Melbourne',
          'state': 'Victoria',
          'postcode': '3121',
          'country_code': 'au',
        },
      });
    });

    final geo = NominatimReverseGeocode(
      dio: dio,
      minInterval: Duration.zero,
    );
    final result = await geo.reverse(
      latitude: -37.8123,
      longitude: 144.9876,
    );

    expect(result.ok, isTrue);
    expect(result.suburb, 'Richmond');
    expect(result.city, 'Melbourne');
    expect(result.stateFull, 'Victoria');
    expect(result.postcode, '3121');
    expect(seen.headers['User-Agent'], NominatimReverseGeocode.userAgent);
    expect(seen.connectTimeout, const Duration(seconds: 8));
    expect(seen.receiveTimeout, const Duration(seconds: 10));
    expect(seen.uri.host, 'nominatim.openstreetmap.org');
  });

  test('PROF-009-FL-07 non-AU response is a safe failure', () async {
    final dio = Dio();
    dio.httpClientAdapter = _ScriptedAdapter((_, __, ___) async {
      return _jsonBody({
        'address': {
          'city': 'Auckland',
          'country_code': 'nz',
        },
      });
    });
    final geo = NominatimReverseGeocode(
      dio: dio,
      minInterval: Duration.zero,
    );
    final result = await geo.reverse(latitude: -36.84, longitude: 174.76);
    expect(result.ok, isFalse);
    expect(result.safeMessage.contains('Australian'), isTrue);
    expect(result.safeMessage.contains('Exception'), isFalse);
    expect(result.safeMessage.toLowerCase().contains('nominatim'), isFalse);
  });

  test('PROF-009-FL-08 timeout/network failure is safe', () async {
    final dio = Dio();
    dio.httpClientAdapter = _ScriptedAdapter((_, __, ___) async {
      throw DioException(
        requestOptions: RequestOptions(path: '/reverse'),
        type: DioExceptionType.receiveTimeout,
      );
    });
    final geo = NominatimReverseGeocode(
      dio: dio,
      minInterval: Duration.zero,
    );
    final result = await geo.reverse(latitude: -33.86, longitude: 151.20);
    expect(result.ok, isFalse);
    expect(result.safeMessage.contains('manually'), isTrue);
    expect(result.safeMessage.contains('Timeout'), isFalse);
    expect(result.safeMessage.contains('DioException'), isFalse);
    expect(result.safeMessage.contains('http'), isFalse);
  });

  test('PROF-009-FL-09 duplicate same-coordinate lookup uses cache', () async {
    final dio = Dio();
    final adapter = _ScriptedAdapter((_, __, ___) async {
      return _jsonBody({
        'address': {
          'suburb': 'Carlton',
          'city': 'Melbourne',
          'state': 'Victoria',
          'postcode': '3053',
          'country_code': 'au',
        },
      });
    });
    dio.httpClientAdapter = adapter;
    final geo = NominatimReverseGeocode(
      dio: dio,
      minInterval: Duration.zero,
    );

    final a = await geo.reverse(latitude: -37.8001, longitude: 144.9668);
    final b = await geo.reverse(latitude: -37.8001, longitude: 144.9668);
    expect(a.ok, isTrue);
    expect(b.ok, isTrue);
    expect(adapter.calls, 1);
  });

  test('PROF-009-FL-10 rapid different lookups are rate-limited', () async {
    final dio = Dio();
    final adapter = _ScriptedAdapter((_, __, ___) async {
      return _jsonBody({
        'address': {
          'suburb': 'A',
          'city': 'B',
          'state': 'Victoria',
          'postcode': '3000',
          'country_code': 'au',
        },
      });
    });
    dio.httpClientAdapter = adapter;
    final geo = NominatimReverseGeocode(
      dio: dio,
      minInterval: const Duration(seconds: 2),
    );

    final first = await geo.reverse(latitude: -37.81, longitude: 144.96);
    final second = await geo.reverse(latitude: -33.86, longitude: 151.20);
    expect(first.ok, isTrue);
    expect(second.ok, isFalse);
    expect(second.safeMessage.toLowerCase().contains('wait'), isTrue);
    expect(adapter.calls, 1);
  });

  test('PROF-009-FL-11 invalid/empty provider payload fails safely', () async {
    final dio = Dio();
    dio.httpClientAdapter = _ScriptedAdapter((_, __, ___) async {
      return _jsonBody({'address': null});
    });
    final geo = NominatimReverseGeocode(
      dio: dio,
      minInterval: Duration.zero,
    );
    final result = await geo.reverse(latitude: 0, longitude: 0);
    expect(result.ok, isFalse);
    expect(result.safeMessage.contains('Exception'), isFalse);
  });

  test('PROF-009-FL-12 profile sheet uses helper, not raw Dio Nominatim', () {
    expect(screenSrc.contains('NominatimReverseGeocode'), isTrue);
    expect(screenSrc.contains('_geocoder.reverse'), isTrue);
    expect(screenSrc.contains('nominatim.openstreetmap.org'), isFalse);
    expect(screenSrc.contains("headers: {'User-Agent'"), isFalse);
  });
}
