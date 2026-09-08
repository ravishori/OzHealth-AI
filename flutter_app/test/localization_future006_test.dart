import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/l10n/app_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:vitapulse_ai/core/locale/locale_controller.dart';
import 'package:vitapulse_ai/core/locale/locale_prefs.dart';
import 'package:vitapulse_ai/features/auth/presentation/screens/welcome_screen.dart';
import 'package:vitapulse_ai/features/settings/presentation/appearance_screen.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

Widget _app({
  Locale? locale,
  Widget? home,
}) {
  return ProviderScope(
    child: MaterialApp(
      locale: locale,
      supportedLocales: kAppSupportedLocales,
      localeResolutionCallback: localeResolution,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppThemeBuilder.light(const AppThemeSettings()),
      home: home,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDir;

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('hn_fut06_hive_');
    Hive.init(hiveDir.path);
    if (Hive.isBoxOpen('app_preferences')) {
      await Hive.box('app_preferences').clear();
    } else {
      await Hive.openBox('app_preferences');
    }
  });

  tearDown(() async {
    if (Hive.isBoxOpen('app_preferences')) {
      await Hive.box('app_preferences').clear();
      await Hive.box('app_preferences').close();
    }
  });

  test('FUT06-FL-01 default locale resolves to English', () {
    expect(localeResolution(null, kAppSupportedLocales), const Locale('en'));
    expect(
      localeResolution(const Locale('fr'), kAppSupportedLocales),
      const Locale('en'),
    );
  });

  test('FUT06-FL-02 required locales en/hi/mr are exposed', () {
    expect(kAppSupportedLocales, containsAll([
      const Locale('en'),
      const Locale('hi'),
      const Locale('mr'),
    ]));
    expect(kSupportedLanguageCodes, ['en', 'hi', 'mr']);
    final src = File('lib/main.dart').readAsStringSync();
    expect(src.contains('AppLocalizations.delegate'), isTrue);
    expect(src.contains('supportedLocales: kAppSupportedLocales'), isTrue);
  });

  testWidgets('FUT06-FL-03 user locale selection updates UI strings', (tester) async {
    await tester.pumpWidget(_app(
      locale: const Locale('hi'),
      home: const WelcomeScreen(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('शुरू करें'), findsOneWidget);
    expect(find.text('HealthNest'), findsOneWidget);
  });

  test('FUT06-FL-04 locale preference persists without PHI', () async {
    await persistLocaleCode('mr');
    expect(readStoredLocaleCode(), 'mr');
    final box = Hive.box('app_preferences');
    expect(box.keys, isNot(contains('user_id')));
    expect(box.keys, isNot(contains('email')));
    expect(box.keys, isNot(contains('access_token')));
    expect(kAppLocaleKey, 'app_locale');
    await persistLocaleCode(null);
    expect(readStoredLocaleCode(), isNull);
  });

  test('FUT06-FL-05 locale restores after restart (Hive reload)', () async {
    await persistLocaleCode('hi');
    await Hive.box('app_preferences').close();
    await Hive.openBox('app_preferences');
    expect(readStoredLocaleCode(), 'hi');
  });

  testWidgets('FUT06-FL-06 representative screens show localized strings', (tester) async {
    await tester.pumpWidget(_app(
      locale: const Locale('mr'),
      home: const WelcomeScreen(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('सुरु करा'), findsOneWidget);
    expect(find.text('तुमचा आरोग्य साथी'), findsOneWidget);
  });

  testWidgets('FUT06-FL-07 longer translated strings do not overflow', (tester) async {
    await tester.pumpWidget(_app(
      locale: const Locale('hi'),
      home: const AppearanceScreen(),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('लंबी अनुवादित'), findsOneWidget);
    // SoftWrap Text widgets should exist for language subtitle
    expect(find.byType(RadioListTile<String?>), findsWidgets);
  });

  testWidgets('FUT06-FL-08 snackbar/dialog cancel uses localized text', (tester) async {
    await tester.pumpWidget(_app(
      locale: const Locale('hi'),
      home: const AppearanceScreen(),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Reset to Defaults'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Reset to Defaults'));
    await tester.pumpAndSettle();
    expect(find.text('रद्द करें'), findsOneWidget);
  });

  testWidgets('FUT06-FL-09 accessibility semantics for language controls', (tester) async {
    await tester.pumpWidget(_app(
      locale: const Locale('en'),
      home: const AppearanceScreen(),
    ));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Language'), findsWidgets);
  });

  testWidgets('FUT06-FL-10 medical/emergency wording remains authoritative English', (tester) async {
    for (final locale in const [Locale('en'), Locale('hi'), Locale('mr')]) {
      await tester.pumpWidget(_app(
        locale: locale,
        home: const AppearanceScreen(),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('Call 000'), findsOneWidget);
      expect(
        find.textContaining(
          'This app does not provide medical advice. Always consult a qualified health professional.',
        ),
        findsOneWidget,
      );
    }
  });

  test('FUT06 ARB files exist for en/hi/mr only', () {
    expect(File('lib/l10n/app_en.arb').existsSync(), isTrue);
    expect(File('lib/l10n/app_hi.arb').existsSync(), isTrue);
    expect(File('lib/l10n/app_mr.arb').existsSync(), isTrue);
    // Do not invent additional languages beyond product scope.
    expect(File('lib/l10n/app_es.arb').existsSync(), isFalse);
    expect(File('lib/l10n/app_ar.arb').existsSync(), isFalse);
  });
}
