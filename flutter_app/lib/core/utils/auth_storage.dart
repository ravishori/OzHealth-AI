import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vitapulse_ai/core/utils/jwt_local_session.dart';

class AuthStorage {
  static const _storage = FlutterSecureStorage();

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required int userId,
    required String name,
  }) async {
    await _storage.write(key: 'access_token', value: accessToken);
    await _storage.write(key: 'refresh_token', value: refreshToken);
    await _storage.write(key: 'user_id', value: userId.toString());
    await _storage.write(key: 'user_name', value: name);
  }

  static Future<String?> getAccessToken() => _storage.read(key: 'access_token');
  static Future<String?> getUserName() => _storage.read(key: 'user_name');
  static Future<int?> getUserId() async {
    final id = await _storage.read(key: 'user_id');
    return id != null ? int.tryParse(id) : null;
  }

  /// Cache the profile image relative path so the home screen can show the
  /// avatar without fetching the full profile on every launch.
  static Future<void> saveProfileImageUrl(String? relPath) async {
    if (relPath != null && relPath.isNotEmpty) {
      await _storage.write(key: 'profile_image_url', value: relPath);
    } else {
      await _storage.delete(key: 'profile_image_url');
    }
  }

  /// Returns the stored relative path (e.g. `profiles/3/abc.jpg`).
  /// Callers must combine this with the server root to get a full URL.
  static Future<String?> getProfileImageUrl() =>
      _storage.read(key: 'profile_image_url');

  /// Local session gate for splash / consent routing (HN-AUTH-008).
  ///
  /// Requires a non-empty access token whose JWT `exp` is still in the future.
  /// Expired or malformed tokens clear local storage and return false.
  /// This does **not** replace server-side JWT / `token_version` validation.
  static Future<bool> isLoggedIn({DateTime? now}) async {
    final token = await _storage.read(key: 'access_token');
    if (token == null || token.isEmpty) {
      return false;
    }
    if (!JwtLocalSession.isValidForLocalStartup(token, now: now)) {
      await clearAll();
      return false;
    }
    return true;
  }

  static Future<void> clearAll() async => _storage.deleteAll();
}
