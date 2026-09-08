// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'HealthNest';

  @override
  String get appTagline => 'Your health companion';

  @override
  String get getStarted => 'Get Started';

  @override
  String get login => 'Log in';

  @override
  String get language => 'Language';

  @override
  String get languageSubtitle =>
      'App display language. Clinical and emergency wording stays in English when a safe translation is not available.';

  @override
  String get languageSystem => 'System default';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageHindi => 'Hindi';

  @override
  String get languageMarathi => 'Marathi';

  @override
  String get appearance => 'Appearance';

  @override
  String get appearanceSubtitle => 'Themes, text size & display';

  @override
  String get privacy => 'Privacy';

  @override
  String get privacySubtitle => 'Consent, export, notifications & legal';

  @override
  String get accountSection => 'Account';

  @override
  String get myProfile => 'My Profile';

  @override
  String get signOut => 'Sign Out';

  @override
  String get homeDashboard => 'Home Dashboard';

  @override
  String get emergencySos => 'Emergency SOS';

  @override
  String get emergencySosSubtitle => 'Alert emergency contacts';

  @override
  String get aiHealthAssistant => 'AI Health Assistant';

  @override
  String get settingsSaved => 'Language updated';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get featureMedications => 'Manage Medications & Prescriptions';

  @override
  String get featureAiAssistant => 'AI Health Assistant (24/7)';

  @override
  String get featureFamily => 'Family Health Management';

  @override
  String get featureMonitoring => 'Health Monitoring & AI Insights';

  @override
  String get welcomeLongSample =>
      'Choose your preferred display language. Longer translated labels should wrap without clipping buttons or navigation items.';

  @override
  String get emergencyCallZeroZeroZero => 'Call 000';

  @override
  String get medicalDisclaimerShort =>
      'This app does not provide medical advice. Always consult a qualified health professional.';

  @override
  String get security => 'Security';

  @override
  String get securitySubtitle =>
      'Optional device biometrics for this app on this device';

  @override
  String get securityBiometricLock => 'Biometric app lock';

  @override
  String get securityBiometricLockHelp =>
      'Require fingerprint or face unlock before opening your HealthNest home on this device. This does not replace your account sign-in.';

  @override
  String get securityBoundaryHelp =>
      'When enabled, HealthNest asks for device biometrics after you sign in, before showing your home. No fingerprints or face data are stored by HealthNest.';

  @override
  String get securityBiometricsUnavailable =>
      'Biometrics are not available or not enrolled on this device.';

  @override
  String get securityEnableReason => 'Confirm biometrics to enable app lock';

  @override
  String get securityDisableReason => 'Confirm biometrics to disable app lock';

  @override
  String get securityUnlockReason => 'Unlock HealthNest';

  @override
  String get securityUnlockTitle => 'Unlock HealthNest';

  @override
  String get securityUnlockBody =>
      'Use your device biometrics to continue to your home screen.';

  @override
  String get securityUnlockAction => 'Unlock';

  @override
  String get securityEnabled => 'Biometric app lock enabled';

  @override
  String get securityDisabled => 'Biometric app lock disabled';

  @override
  String get securityAuthFailed =>
      'Authentication failed. App lock was not changed.';

  @override
  String get securityAuthCancelled => 'Authentication cancelled.';
}
