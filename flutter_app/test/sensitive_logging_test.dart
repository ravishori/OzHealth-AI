import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/core/utils/debug_logger.dart';

void main() {
  setUp(DebugLogger.clearBufferForTest);

  test('SEC-LOG-03 request bodies are not logged', () {
    const med = 'MetforminHydrochloride500';
    const otp = '847291';
    const token = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.abc.def';
    DebugLogger.request('POST', 'http://10.0.2.2:8000/api/v1/ai/chat', {
      'message': 'I take $med and have chest pain',
      'otp_code': otp,
      'access_token': token,
    });
    final text = DebugLogger.recentText();
    expect(text.contains('POST http://10.0.2.2:8000/api/v1/ai/chat'), isTrue);
    expect(text.contains(med), isFalse);
    expect(text.contains(otp), isFalse);
    expect(text.contains(token), isFalse);
    expect(text.contains('body:'), isFalse);
  });

  test('SEC-LOG-04 response bodies are not logged', () {
    const rx = 'Take two tablets of Warfarin at night';
    DebugLogger.response(200, 'http://10.0.2.2:8000/api/v1/prescriptions/scan', {
      'raw_ocr_text': rx,
      'medicines': [
        {'name': 'Warfarin'}
      ],
    });
    final text = DebugLogger.recentText();
    expect(text.contains('200 http://10.0.2.2:8000/api/v1/prescriptions/scan'),
        isTrue);
    expect(text.contains(rx), isFalse);
    expect(text.contains('Warfarin'), isFalse);
    expect(text.contains('body:'), isFalse);
  });

  test('SEC-LOG-02/05 AI and medical payloads absent from request logs', () {
    const aiQ = 'I have chest pain after starting Atorvastatin';
    DebugLogger.request('POST', '/ai/chat', {'message': aiQ});
    final text = DebugLogger.recentText();
    expect(text.contains(aiQ), isFalse);
    expect(text.contains('Atorvastatin'), isFalse);
  });

  test('SEC-LOG-07 safe metadata remains', () {
    DebugLogger.request('GET', '/users/me');
    DebugLogger.response(401, '/users/me');
    final text = DebugLogger.recentText();
    expect(text.contains('GET /users/me'), isTrue);
    expect(text.contains('401 /users/me'), isTrue);
  });

  test('SEC-LOG-08 safeBody still masks otp and tokens when used explicitly', () {
    final masked = DebugLogger.safeBody({
      'otp_code': '123456',
      'access_token': 'abcdefghijklmnop',
      'note': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.xx',
    });
    expect(masked.contains('123456'), isFalse);
    expect(masked.contains('******'), isTrue);
    expect(masked.contains('[masked]'), isTrue);
  });

  test('SEC-LOG-09 error logging without response body content', () {
    const phi = 'Patient John Doe allergy Penicillin';
    DebugLogger.error('ApiClient', 'DioError [http]  status=500  url=/records',
        'timeout');
    final text = DebugLogger.recentText();
    expect(text.contains('status=500'), isTrue);
    expect(text.contains(phi), isFalse);
  });

  test('ApiClient interceptor omits bodies from DebugLogger calls', () {
    final src = File('lib/core/network/api_client.dart').readAsStringSync();
    expect(
      src.contains('DebugLogger.request(options.method, options.uri.toString());'),
      isTrue,
    );
    // Two-arg response logger only (status + URL); no body third argument.
    expect(
      RegExp(
        r'DebugLogger\.response\(\s*'
        r'response\.statusCode \?\? 0,\s*'
        r'response\.requestOptions\.uri\.toString\(\),\s*'
        r'\);',
      ).hasMatch(src),
      isTrue,
    );
    expect(src.contains('DebugLogger.response(\n'), isTrue);
    // Error path must not pass response body as a DebugLogger argument.
    final errorBlock = RegExp(
      r"DebugLogger\.error\(\s*'ApiClient',\s*'DioError[\s\S]*?\);",
    ).firstMatch(src)?.group(0);
    expect(errorBlock, isNotNull);
    expect(errorBlock!.contains('.data'), isFalse);
  });
}
