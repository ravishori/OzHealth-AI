import 'dart:convert';

/// Local JWT inspection for session *hygiene* only (HN-AUTH-008).
///
/// Decodes the payload to read `exp`. Does **not** verify signatures and must
/// never be treated as proof of authentication — the backend remains
/// authoritative for JWT validation and `token_version`.
enum LocalJwtStatus {
  /// Token structure is OK and `exp` is in the future (UTC).
  valid,

  /// `exp` is present and not after now.
  expired,

  /// Not a three-part JWT, payload not JSON, or `exp` not a usable number.
  malformed,

  /// Payload parsed but `exp` claim is absent.
  missingExp,
}

class JwtLocalSession {
  JwtLocalSession._();

  /// Evaluate an access token for local startup gating.
  ///
  /// [now] is injectable for tests. Never logs token or payload contents.
  static LocalJwtStatus evaluateAccessToken(
    String? token, {
    DateTime? now,
  }) {
    if (token == null || token.isEmpty) {
      return LocalJwtStatus.malformed;
    }

    final parts = token.split('.');
    if (parts.length != 3) {
      return LocalJwtStatus.malformed;
    }

    try {
      final payloadJson = _decodeBase64Url(parts[1]);
      final decoded = jsonDecode(payloadJson);
      if (decoded is! Map) {
        return LocalJwtStatus.malformed;
      }
      final payload = Map<String, dynamic>.from(decoded);

      if (!payload.containsKey('exp')) {
        return LocalJwtStatus.missingExp;
      }

      final expSeconds = _asEpochSeconds(payload['exp']);
      if (expSeconds == null) {
        return LocalJwtStatus.malformed;
      }

      final expiry = DateTime.fromMillisecondsSinceEpoch(
        expSeconds * 1000,
        isUtc: true,
      );
      final clock = (now ?? DateTime.now()).toUtc();
      if (!expiry.isAfter(clock)) {
        return LocalJwtStatus.expired;
      }
      return LocalJwtStatus.valid;
    } catch (_) {
      return LocalJwtStatus.malformed;
    }
  }

  /// True only when [evaluateAccessToken] returns [LocalJwtStatus.valid].
  static bool isValidForLocalStartup(String? token, {DateTime? now}) =>
      evaluateAccessToken(token, now: now) == LocalJwtStatus.valid;

  static String _decodeBase64Url(String segment) {
    var normalized = segment.replaceAll('-', '+').replaceAll('_', '/');
    switch (normalized.length % 4) {
      case 2:
        normalized += '==';
      case 3:
        normalized += '=';
      case 1:
        throw const FormatException('invalid base64url length');
    }
    return utf8.decode(base64.decode(normalized));
  }

  static int? _asEpochSeconds(Object? value) {
    if (value is int) return value;
    if (value is double) {
      if (value.isNaN || value.isInfinite) return null;
      return value.truncate();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }
}
