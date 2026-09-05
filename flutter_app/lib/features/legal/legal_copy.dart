/// In-app legal copy. A public HTTPS privacy URL is still required in Play Console.
///
/// Context banners below are short, patient-facing safety lines for clinical/AI
/// screens (HN-LEGAL-004). Full consent text remains [medicalDisclaimer].
class LegalCopy {
  LegalCopy._();

  static const medicalDisclaimerTitle = 'Important health notice';

  static const medicalDisclaimer =
      'HealthNest is not a medical device and does not diagnose, treat, '
      'cure, or prevent any medical condition.\n\n'
      'Information in this app, including medicine data, OCR results, and '
      'AI-generated answers, is for general information only. It is not a '
      'substitute for advice from a qualified doctor, pharmacist, or other '
      'health professional in Australia.\n\n'
      'If you think you have a medical emergency, call 000 (triple zero) '
      'immediately. Do not rely on this app in an emergency.';

  /// AI chat / assistant surfaces.
  static const aiBanner =
      'Not a doctor. HealthNest does not diagnose or prescribe. '
      'In an emergency call 000. AI answers can be wrong.';

  /// Medicine search and detail (catalog / informational content).
  static const medicineBanner =
      'Medicine information is for general information only. '
      'Follow your doctor or pharmacist. Do not change medication without '
      'professional advice. In an emergency call 000.';

  /// Prescription OCR review — verify before acting.
  static const prescriptionOcrBanner =
      'OCR and AI-extracted prescription details are unconfirmed. '
      'Verify every medicine with a doctor or pharmacist before acting. '
      'Do not rely on OCR alone for medication decisions.';

  /// Symptom checker — not a diagnosis.
  static const symptomBanner =
      'This tool provides general guidance only — not a diagnosis. '
      'Seek professional assessment when needed. For emergencies, call 000 '
      'immediately.';

  /// Footer note under symptom results (non-diagnostic).
  static const symptomProfessionalNote =
      'Always consult a qualified healthcare professional for diagnosis and '
      'treatment.';

  /// Lab analysis — informational / discuss with GP.
  static const labBanner =
      'This analysis is AI-generated and for informational purposes only. '
      'Discuss results with your GP. HealthNest does not diagnose. '
      'In an emergency call 000.';

  /// Drug-interaction checker.
  static const interactionBanner =
      'This analysis is AI-generated. Always consult your pharmacist or doctor '
      'before making any medication changes. In an emergency call 000.';

  /// Emergency / SOS — keep dial-first honesty (Sprint 2/3 wording).
  static const emergencyBanner =
      'Medical emergency disclaimer: HealthNest does not replace '
      'emergency services. In a life-threatening emergency call 000 '
      '(or 112 from a mobile). SOS records your location and does not '
      'automatically SMS or push-notify contacts.';

  static const privacyPolicy = '''
Privacy (in-app summary)

This app is intended for people in Australia. It collects account details (name, email and/or phone), optional health profile data (age, sex, blood group, conditions, allergies, address), family-member information you enter, medical documents you upload, medication reminders, health metrics you log, location when you use SOS or nearby services, and messages you send to the AI assistant.

Data is sent to our API over the network and stored in our database. Some health fields are encrypted at rest. Uploaded files are stored on the server. AI features send relevant text to a third-party language-model provider. SMS/email OTP uses telephony and email providers.

We do not sell your data. You can delete your account in Profile, which permanently deletes your account and associated app data we hold, except where we must retain records for security or law.

This in-app text is not a substitute for a hosted privacy policy URL required by Google Play. Host that policy on a public HTTPS page and set PRIVACY_POLICY_URL when building the store AAB.
''';

  static const terms = '''
Terms of use (in-app)

By using HealthNest you agree that the app is an information tool only, not a clinical service. You are responsible for verifying medicines and prescriptions with a pharmacist or prescriber.

You must not use the app to seek or provide emergency treatment. You must not upload documents you are not allowed to store.

We may suspend accounts that abuse the service. These terms may be updated; continued use after an in-app update constitutes acceptance of the revised in-app terms until a hosted terms URL is published.
''';
}
