/// Authoritative in-app metadata already present in the repository.
///
/// Values match `pubspec.yaml` (`version: 1.0.0+1`), Android `app_name`,
/// and the existing Health Monitor mailto address. Do not invent
/// certifications, partnerships, or medical claims here.
class AppInfo {
  AppInfo._();

  static const appName = 'HealthNest';
  static const tagline =
      'Intelligent Personal Health Companion for Australia';
  static const versionName = '1.0.0';
  static const versionCode = '1';
  static const versionLabel = 'Version $versionName (build $versionCode)';

  /// Existing support mailbox used by Health Monitor error-report mailto.
  static const supportEmail = 'ravidigitalforge@gmail.com';
}
