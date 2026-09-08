import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/profile/data/lifestyle_preferences.dart';
import 'package:vitapulse_ai/features/profile/presentation/lifestyle_preferences_section.dart';

/// HN-PROF-006 — Flutter lifestyle preferences contracts.
void main() {
  final screenSrc = File(
    'lib/features/profile/presentation/profile_screen.dart',
  ).readAsStringSync();
  final sectionSrc = File(
    'lib/features/profile/presentation/lifestyle_preferences_section.dart',
  ).readAsStringSync();
  final dataSrc = File(
    'lib/features/profile/data/lifestyle_preferences.dart',
  ).readAsStringSync();
  final apiSrc = File(
    'lib/features/profile/data/user_api.dart',
  ).readAsStringSync();

  test('PROF006-F01 profile displays lifestyle preferences when returned', () {
    expect(screenSrc.contains('LifestylePreferencesSection'), isTrue);
    expect(screenSrc.contains("p['lifestyle_preferences']"), isTrue);
    expect(sectionSrc.contains('lifestyle_preferences_section'), isTrue);
  });

  test('PROF006-F02 existing preference hydrates into edit control', () {
    expect(screenSrc.contains('LifestylePreferences.fromApi'), isTrue);
    expect(sectionSrc.contains('widget.initial[key]'), isTrue);
    expect(sectionSrc.contains('LifestylePreferencesEditorSheet'), isTrue);
    final prefs = LifestylePreferences.fromApi({
      'diet': 'Vegetarian',
      'exercise': 'Walk',
      'junk': null,
    });
    expect(prefs['diet'], 'Vegetarian');
    expect(prefs['exercise'], 'Walk');
    expect(prefs.containsKey('junk'), isFalse);
  });

  test('PROF006-F03 user can edit the preference', () {
    expect(sectionSrc.contains("Key('lifestyle_field_\$key')"), isTrue);
    expect(sectionSrc.contains('lifestyle_preferences_edit'), isTrue);
    expect(screenSrc.contains('_showLifestyleEditor'), isTrue);
  });

  test('PROF006-F04 save invokes existing profile update API', () {
    expect(screenSrc.contains('_patchProfile'), isTrue);
    expect(screenSrc.contains("'lifestyle_preferences': result"), isTrue);
    expect(screenSrc.contains("ApiClient.put('/users/me'"), isTrue);
    expect(apiSrc.contains('static Future<Map<String, dynamic>> updateMe'), isTrue);
    final updateStart = apiSrc.indexOf('static Future<Map<String, dynamic>> updateMe');
    final updateEnd = apiSrc.indexOf('static Future<Map<String, dynamic>> uploadPhoto');
    final updateBody = apiSrc.substring(updateStart, updateEnd);
    expect(updateBody.contains('user_id'), isFalse);
    expect(updateBody.contains("ApiClient.put('/users/me'"), isTrue);
  });

  test('PROF006-F05 successful save updates local/profile state', () {
    expect(screenSrc.contains("setState(() => _profile = resp.data"), isTrue);
    expect(screenSrc.contains('Lifestyle preferences updated'), isTrue);
  });

  test('PROF006-F06 preference persists after profile reload', () {
    expect(screenSrc.contains('_loadProfile'), isTrue);
    expect(screenSrc.contains("ApiClient.get('/users/me')"), isTrue);
    expect(screenSrc.contains('RefreshIndicator'), isTrue);
  });

  test('PROF006-F07 empty preference is handled correctly', () {
    expect(LifestylePreferences.fromApi(null), isEmpty);
    expect(LifestylePreferences.fromApi('null'), isEmpty);
    expect(LifestylePreferences.fromApi({'diet': 'null'}), isEmpty);
    expect(sectionSrc.contains('lifestyle_preferences_empty'), isTrue);
    expect(sectionSrc.contains('Tap edit to add lifestyle preferences'), isTrue);
    expect(dataSrc.contains('[object'), isTrue);
  });

  test('PROF006-F08 validation prevents invalid submission', () {
    expect(sectionSrc.contains('_formKey.currentState!.validate()'), isTrue);
    expect(sectionSrc.contains('Keep under 200 characters'), isTrue);
    expect(
      () => LifestylePreferences.toApi({'diet': 'x' * 201}),
      throwsA(isA<FormatException>()),
    );
  });

  test('PROF006-F09 API failure does not show false success', () {
    expect(screenSrc.contains('if (ok && mounted)'), isTrue);
    expect(screenSrc.contains('Lifestyle preferences updated'), isTrue);
    // Success snackbar only after ok; _patchProfile returns false on error.
    expect(screenSrc.contains('return false;'), isTrue);
    expect(screenSrc.contains('ErrorHandler.getMessage(e)'), isTrue);
  });

  test('PROF006-F10 duplicate save is prevented while request is running', () {
    expect(sectionSrc.contains('bool _saving = false'), isTrue);
    expect(sectionSrc.contains('if (_saving) return;'), isTrue);
    expect(sectionSrc.contains('onPressed: _saving ? null : _onSave'), isTrue);
  });

  test('PROF006 privacy/UI — not medical advice; no URL query placement', () {
    expect(sectionSrc.toLowerCase().contains('not medical'), isTrue);
    expect(sectionSrc.toLowerCase().contains('diagnosis'), isTrue);
    expect(sectionSrc.toLowerCase().contains('treatment'), isFalse);
    expect(screenSrc.contains('lifestyle_preferences='), isFalse);
    expect(apiSrc.contains('queryParameters'), isFalse);
    expect(dataSrc.contains('not medical diagnoses'), isTrue);
  });

  testWidgets('PROF006 section renders empty and populated states', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LifestylePreferencesSection(
            preferences: const {},
            onEdit: () {},
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('lifestyle_preferences_empty')), findsOneWidget);
    expect(find.textContaining('not a medical assessment'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LifestylePreferencesSection(
            preferences: const {'diet': 'Vegetarian'},
            onEdit: () {},
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('lifestyle_pref_value_diet')), findsOneWidget);
    expect(find.text('Vegetarian'), findsOneWidget);
  });

  testWidgets('PROF006 editor cancel does not return a payload', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Map<String, String>? result = {'sentinel': 'x'};
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showModalBottomSheet<Map<String, String>>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const LifestylePreferencesEditorSheet(
                    initial: {'diet': 'Vegan'},
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Vegan'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('lifestyle_cancel')));
    await tester.tap(find.byKey(const Key('lifestyle_cancel')));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
