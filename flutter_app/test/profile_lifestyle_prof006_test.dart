import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/profile/data/lifestyle_preferences.dart';
import 'package:vitapulse_ai/features/profile/presentation/lifestyle_preferences_section.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppThemeBuilder.light(const AppThemeSettings()),
    home: Scaffold(body: child),
  );
}

void main() {
  final profileSrc =
      File('lib/features/profile/presentation/profile_screen.dart')
          .readAsStringSync();
  final sectionSrc = File(
          'lib/features/profile/presentation/lifestyle_preferences_section.dart')
      .readAsStringSync();
  final codecSrc =
      File('lib/features/profile/data/lifestyle_preferences.dart')
          .readAsStringSync();
  final apiSrc =
      File('lib/features/profile/data/user_api.dart').readAsStringSync();

  test('PROF-LIFE-FL-01 codec hydrates GET object into display map', () {
    final parsed = LifestylePreferencesCodec.parse({
      'diet': 'Vegetarian',
      'exercise': 'Walking',
      'ignored_nested': {'x': 1},
      'id': null,
    });
    expect(parsed['diet'], 'Vegetarian');
    expect(parsed['exercise'], 'Walking');
    expect(parsed.containsKey('ignored_nested'), isFalse);
    expect(parsed.containsKey('id'), isFalse);
    expect(LifestylePreferencesCodec.parse(null), isEmpty);
    expect(LifestylePreferencesCodec.parse([]), isEmpty);
  });

  testWidgets('PROF-LIFE-FL-01 preferences hydrate into Profile UI',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        LifestylePreferencesSection(
          values: const {
            'diet': 'Vegetarian',
            'exercise': 'Walking',
          },
          saving: false,
          onSave: (_) async => true,
        ),
      ),
    );
    expect(find.text('Lifestyle preferences'), findsOneWidget);
    expect(find.text('Vegetarian'), findsOneWidget);
    expect(find.text('Walking'), findsOneWidget);
    expect(find.textContaining('Diet'), findsOneWidget);
    expect(find.textContaining('Exercise'), findsOneWidget);
    expect(find.text('42'), findsNothing);
  });

  testWidgets('PROF-LIFE-FL-02 user can edit preference values', (tester) async {
    await tester.pumpWidget(
      _wrap(
        LifestylePreferencesEditorSheet(
          initial: const {'diet': 'Vegetarian'},
          onSave: (_) async => true,
        ),
      ),
    );
    await tester.pump();
    final dietField = find.byKey(const Key('lifestyle-field-diet'));
    expect(dietField, findsOneWidget);
    expect(find.text('Vegetarian'), findsOneWidget);
    await tester.enterText(dietField, 'Halal');
    await tester.pump();
    expect(find.text('Halal'), findsOneWidget);
  });

  testWidgets('PROF-LIFE-FL-03 save sends the expected fields', (tester) async {
    Map<String, String>? received;
    await tester.pumpWidget(
      _wrap(
        LifestylePreferencesEditorSheet(
          initial: const {'diet': 'Vegetarian', 'exercise': 'Walking'},
          onSave: (next) async {
            received = Map<String, String>.from(next);
            return true;
          },
        ),
      ),
    );
    await tester.enterText(
        find.byKey(const Key('lifestyle-field-diet')), 'Halal');
    await tester.enterText(
        find.byKey(const Key('lifestyle-field-sleep')), '7 hours');
    await tester.tap(find.byKey(const Key('lifestyle-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(received, isNotNull);
    expect(received!['diet'], 'Halal');
    expect(received!['exercise'], 'Walking');
    expect(received!['sleep'], '7 hours');
    expect(
      LifestylePreferencesCodec.toPayload(received!),
      {
        'diet': 'Halal',
        'exercise': 'Walking',
        'sleep': '7 hours',
      },
    );
    expect(profileSrc.contains("'lifestyle_preferences':"), isTrue);
    expect(profileSrc.contains('LifestylePreferencesCodec.toPayload'), isTrue);
  });

  testWidgets('PROF-LIFE-FL-04 successful save updates displayed state',
      (tester) async {
    var values = <String, String>{'diet': 'Vegetarian'};
    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (context, setState) {
            return LifestylePreferencesSection(
              values: values,
              saving: false,
              onSave: (next) async {
                setState(() {
                  values = {
                    for (final e in next.entries)
                      if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
                  };
                });
                return true;
              },
            );
          },
        ),
      ),
    );
    expect(find.text('Vegetarian'), findsOneWidget);
    await tester.tap(find.byKey(const Key('lifestyle-edit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
        find.byKey(const Key('lifestyle-field-diet')), 'Mediterranean');
    await tester.tap(find.byKey(const Key('lifestyle-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Mediterranean'), findsWidgets);
    expect(find.text('Vegetarian'), findsNothing);
  });

  testWidgets(
      'PROF-LIFE-FL-05 save failure shows safe error and preserves values',
      (tester) async {
    const original = {'diet': 'Vegetarian'};
    var values = Map<String, String>.from(original);
    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (context, setState) {
            return Column(
              children: [
                LifestylePreferencesSection(
                  values: values,
                  saving: false,
                  onSave: (_) async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not save profile')),
                    );
                    return false;
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('lifestyle-edit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
        find.byKey(const Key('lifestyle-field-diet')), 'ShouldNotStick');
    await tester.tap(find.byKey(const Key('lifestyle-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Could not save profile'), findsOneWidget);
    expect(find.text('ShouldNotStick'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Vegetarian'), findsOneWidget);
    expect(find.text('ShouldNotStick'), findsNothing);
    expect(values, original);
    expect(profileSrc.contains('ErrorHandler.getMessage'), isTrue);
  });

  testWidgets('PROF-LIFE-FL-06 duplicate save is prevented while request active',
      (tester) async {
    var saves = 0;
    final gate = Completer<bool>();
    await tester.pumpWidget(
      _wrap(
        LifestylePreferencesEditorSheet(
          initial: const {'diet': 'Vegetarian'},
          onSave: (_) {
            saves += 1;
            return gate.future;
          },
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('lifestyle-save')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('lifestyle-save')));
    await tester.pump();
    expect(saves, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    gate.complete(true);
    await tester.pump();
  });

  test('PROF-LIFE-FL-07 no raw IDs or sensitive payload logging', () {
    expect(sectionSrc.contains('debugPrint'), isFalse);
    expect(sectionSrc.contains('print('), isFalse);
    expect(codecSrc.contains('debugPrint'), isFalse);
    expect(codecSrc.contains('print('), isFalse);
    expect(apiSrc.contains('debugPrint'), isFalse);
    expect(apiSrc.contains('print('), isFalse);

    final saveFnStart = profileSrc.indexOf('Future<bool> _saveLifestylePreferences');
    expect(saveFnStart, greaterThanOrEqualTo(0));
    final saveFn = profileSrc.substring(
      saveFnStart,
      profileSrc.indexOf('Future<void> _exportMyData'),
    );
    expect(saveFn.contains('print('), isFalse);
    expect(saveFn.contains('debugPrint'), isFalse);
    expect(saveFn.contains('toString()'), isFalse);
    expect(saveFn.contains('DebugLogger'), isFalse);

    expect(sectionSrc.contains("user_id"), isFalse);
    expect(sectionSrc.contains("owner_id"), isFalse);
    expect(profileSrc.contains('LifestylePreferencesSection'), isTrue);
    expect(profileSrc.toLowerCase().contains('you should'), isFalse);
    expect(sectionSrc.toLowerCase().contains('diagnosis'), isFalse);
  });
}
