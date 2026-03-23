import 'package:hive_flutter/hive_flutter.dart';

/// Runs heavyweight initialization tasks after the UI has rendered its first frame.
/// Called from SplashScreen so the app shell is visible before any blocking work.
class AppInitializer {
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    await Future.wait([
      Hive.initFlutter(),
    ]);
    _initialized = true;
  }
}
