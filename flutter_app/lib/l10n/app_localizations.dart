import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_mr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hi'),
    Locale('mr')
  ];

  /// Application brand name — keep as product name
  ///
  /// In en, this message translates to:
  /// **'HealthNest'**
  String get appTitle;

  /// No description provided for @appTagline.
  ///
  /// In en, this message translates to:
  /// **'Your health companion'**
  String get appTagline;

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get getStarted;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get login;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'App display language. Clinical and emergency wording stays in English when a safe translation is not available.'**
  String get languageSubtitle;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageHindi.
  ///
  /// In en, this message translates to:
  /// **'Hindi'**
  String get languageHindi;

  /// No description provided for @languageMarathi.
  ///
  /// In en, this message translates to:
  /// **'Marathi'**
  String get languageMarathi;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @appearanceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Themes, text size & display'**
  String get appearanceSubtitle;

  /// No description provided for @privacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacy;

  /// No description provided for @privacySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Consent, export, notifications & legal'**
  String get privacySubtitle;

  /// No description provided for @accountSection.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountSection;

  /// No description provided for @myProfile.
  ///
  /// In en, this message translates to:
  /// **'My Profile'**
  String get myProfile;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get signOut;

  /// No description provided for @homeDashboard.
  ///
  /// In en, this message translates to:
  /// **'Home Dashboard'**
  String get homeDashboard;

  /// No description provided for @emergencySos.
  ///
  /// In en, this message translates to:
  /// **'Emergency SOS'**
  String get emergencySos;

  /// No description provided for @emergencySosSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Alert emergency contacts'**
  String get emergencySosSubtitle;

  /// No description provided for @aiHealthAssistant.
  ///
  /// In en, this message translates to:
  /// **'AI Health Assistant'**
  String get aiHealthAssistant;

  /// No description provided for @settingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Language updated'**
  String get settingsSaved;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @featureMedications.
  ///
  /// In en, this message translates to:
  /// **'Manage Medications & Prescriptions'**
  String get featureMedications;

  /// No description provided for @featureAiAssistant.
  ///
  /// In en, this message translates to:
  /// **'AI Health Assistant (24/7)'**
  String get featureAiAssistant;

  /// No description provided for @featureFamily.
  ///
  /// In en, this message translates to:
  /// **'Family Health Management'**
  String get featureFamily;

  /// No description provided for @featureMonitoring.
  ///
  /// In en, this message translates to:
  /// **'Health Monitoring & AI Insights'**
  String get featureMonitoring;

  /// No description provided for @welcomeLongSample.
  ///
  /// In en, this message translates to:
  /// **'Choose your preferred display language. Longer translated labels should wrap without clipping buttons or navigation items.'**
  String get welcomeLongSample;

  /// Australian emergency number — do not localize the digits
  ///
  /// In en, this message translates to:
  /// **'Call 000'**
  String get emergencyCallZeroZeroZero;

  /// Safety disclaimer retained in English across locales for semantic accuracy
  ///
  /// In en, this message translates to:
  /// **'This app does not provide medical advice. Always consult a qualified health professional.'**
  String get medicalDisclaimerShort;

  /// No description provided for @security.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get security;

  /// No description provided for @securitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Optional device biometrics for this app on this device'**
  String get securitySubtitle;

  /// No description provided for @securityBiometricLock.
  ///
  /// In en, this message translates to:
  /// **'Biometric app lock'**
  String get securityBiometricLock;

  /// No description provided for @securityBiometricLockHelp.
  ///
  /// In en, this message translates to:
  /// **'Require fingerprint or face unlock before opening your HealthNest home on this device. This does not replace your account sign-in.'**
  String get securityBiometricLockHelp;

  /// No description provided for @securityBoundaryHelp.
  ///
  /// In en, this message translates to:
  /// **'When enabled, HealthNest asks for device biometrics after you sign in, before showing your home. No fingerprints or face data are stored by HealthNest.'**
  String get securityBoundaryHelp;

  /// No description provided for @securityBiometricsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Biometrics are not available or not enrolled on this device.'**
  String get securityBiometricsUnavailable;

  /// No description provided for @securityEnableReason.
  ///
  /// In en, this message translates to:
  /// **'Confirm biometrics to enable app lock'**
  String get securityEnableReason;

  /// No description provided for @securityDisableReason.
  ///
  /// In en, this message translates to:
  /// **'Confirm biometrics to disable app lock'**
  String get securityDisableReason;

  /// No description provided for @securityUnlockReason.
  ///
  /// In en, this message translates to:
  /// **'Unlock HealthNest'**
  String get securityUnlockReason;

  /// No description provided for @securityUnlockTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock HealthNest'**
  String get securityUnlockTitle;

  /// No description provided for @securityUnlockBody.
  ///
  /// In en, this message translates to:
  /// **'Use your device biometrics to continue to your home screen.'**
  String get securityUnlockBody;

  /// No description provided for @securityUnlockAction.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get securityUnlockAction;

  /// No description provided for @securityEnabled.
  ///
  /// In en, this message translates to:
  /// **'Biometric app lock enabled'**
  String get securityEnabled;

  /// No description provided for @securityDisabled.
  ///
  /// In en, this message translates to:
  /// **'Biometric app lock disabled'**
  String get securityDisabled;

  /// No description provided for @securityAuthFailed.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed. App lock was not changed.'**
  String get securityAuthFailed;

  /// No description provided for @securityAuthCancelled.
  ///
  /// In en, this message translates to:
  /// **'Authentication cancelled.'**
  String get securityAuthCancelled;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hi', 'mr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
    case 'mr':
      return AppLocalizationsMr();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
