import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitapulse_ai/core/locale/locale_prefs.dart';

/// App UI locale controller (HN-FUTURE-006).
///
/// `null` means follow the device/system locale (with English fallback).
class LocaleController extends Notifier<Locale?> {
  @override
  Locale? build() {
    final code = readStoredLocaleCode();
    if (code == null) return null;
    return Locale(code);
  }

  Future<void> setLocale(Locale? locale) async {
    if (locale == null) {
      await persistLocaleCode(null);
      state = null;
      return;
    }
    final code = locale.languageCode.toLowerCase();
    if (!kSupportedLanguageCodes.contains(code)) {
      await persistLocaleCode(null);
      state = null;
      return;
    }
    await persistLocaleCode(code);
    state = Locale(code);
  }

  Future<void> useSystemLocale() => setLocale(null);
}

final localeControllerProvider =
    NotifierProvider<LocaleController, Locale?>(LocaleController.new);

/// Locales exposed by the application localization configuration.
const kAppSupportedLocales = <Locale>[
  Locale('en'),
  Locale('hi'),
  Locale('mr'),
];

Locale localeResolution(Locale? device, Iterable<Locale> supported) {
  // Explicit user preference is applied by MaterialApp.locale; this callback
  // handles system/device resolution when locale is null.
  if (device != null) {
    for (final l in supported) {
      if (l.languageCode == device.languageCode) return l;
    }
  }
  return const Locale('en');
}
