import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/interactions/presentation/interaction_check_screen.dart';
import 'package:vitapulse_ai/features/legal/legal_copy.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppThemeBuilder.light(const AppThemeSettings()),
    home: child,
  );
}

void _setLargeSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Map<String, dynamic> _sourceBackedResult() => {
      'ai_used': false,
      'authoritative': true,
      'disclaimer': LegalCopy.interactionBanner,
      'overall_status': 'ALERTS_PRESENT',
      'unresolved': [],
      'interaction_analysis': {
        'risk_level': 'known',
        'unavailable': false,
        'overall_summary': '1 source-backed interaction record(s) found.',
        'recommendations': ['Discuss with a pharmacist.'],
        'interactions': [
          {
            'drug_a': 'Warfarin',
            'drug_b': 'Aspirin',
            'severity': 'major',
            'description': 'Increased bleeding risk (database).',
            'recommended_action':
                'Discuss this database-recorded interaction with a pharmacist.',
            'source_type': 'source_backed',
            'source_name': 'local_interactions_table',
            'verified': true,
            'status': 'KNOWN',
            'unavailable': false,
            'medicine_a': {'medicine_id': 1, 'name': 'Warfarin'},
            'medicine_b': {'medicine_id': 2, 'name': 'Aspirin'},
          }
        ],
      },
      'duplicate_check': {'duplicates': [], 'is_interaction': false},
    };

Map<String, dynamic> _unavailableResult() => {
      'ai_used': false,
      'authoritative': true,
      'disclaimer': LegalCopy.interactionBanner,
      'overall_status': 'INCOMPLETE_DATA',
      'unresolved': [],
      'interaction_analysis': {
        'risk_level': 'unavailable',
        'unavailable': true,
        'overall_summary':
            'Interaction information is unavailable for the selected medicine pair(s). This does not mean the medicines are confirmed safe together.',
        'recommendations': [
          'Unavailable interaction information must not be treated as confirmation of safety.'
        ],
        'interactions': [
          {
            'drug_a': 'Paracetamol',
            'drug_b': 'Ibuprofen',
            'status': 'UNKNOWN',
            'unavailable': true,
            'description':
                'Interaction information is unavailable for this medicine pair.',
            'source_type': 'unavailable',
            'verified': false,
          }
        ],
      },
      'duplicate_check': {
        'duplicates': [
          {
            'medicine_a': 'Panadol',
            'medicine_b': 'Paracetamol',
            'reason': 'same canonical_key',
            'is_interaction': false,
          }
        ],
        'is_interaction': false,
      },
    };

Future<void> _addTwoCatalogueMeds(WidgetTester tester) async {
  await tester.enterText(
      find.byKey(const Key('interaction_medicine_input')), 'war');
  await tester.pumpAndSettle();
  await tester.tap(find.text('Warfarin').first);
  await tester.pumpAndSettle();
  await tester.enterText(
      find.byKey(const Key('interaction_medicine_input')), 'asp');
  await tester.pumpAndSettle();
  await tester.tap(find.text('Aspirin').first);
  await tester.pumpAndSettle();
}

void main() {
  final screenSrc = File(
    'lib/features/interactions/presentation/interaction_check_screen.dart',
  ).readAsStringSync();
  final apiSrc =
      File('lib/features/interactions/data/interactions_api.dart').readAsStringSync();
  final legalSrc = File('lib/features/legal/legal_copy.dart').readAsStringSync();

  testWidgets('IX-F01 checker screen exists', (tester) async {
    await tester.pumpWidget(_wrap(const InteractionCheckScreen()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('interaction_check_screen')), findsOneWidget);
    expect(find.text('Drug Interaction Check'), findsOneWidget);
  });

  testWidgets('IX-F02 medicine selection works', (tester) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(
      _wrap(
        InteractionCheckScreen(
          searchMedicines: (q) async => {
            'results': [
              {'id': 1, 'name': 'Warfarin', 'generic_name': 'warfarin'},
              {'id': 2, 'name': 'Aspirin', 'generic_name': 'aspirin'},
            ],
          },
          checkInteractions: (
              {medicineIds, medicines, includeDuplicateCheck = true}) async {
            return _sourceBackedResult();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _addTwoCatalogueMeds(tester);
    expect(find.byKey(const Key('interaction_selected_list')), findsOneWidget);
    expect(find.textContaining('Warfarin'), findsWidgets);
  });

  testWidgets('IX-F03 check request constructed with ids', (tester) async {
    _setLargeSurface(tester);
    List<int>? sentIds;
    await tester.pumpWidget(
      _wrap(
        InteractionCheckScreen(
          searchMedicines: (q) async => {
            'results': [
              {'id': 1, 'name': 'Warfarin'},
              {'id': 2, 'name': 'Aspirin'},
            ],
          },
          checkInteractions: (
              {medicineIds, medicines, includeDuplicateCheck = true}) async {
            sentIds = medicineIds;
            return _sourceBackedResult();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _addTwoCatalogueMeds(tester);
    await tester.tap(find.byKey(const Key('interaction_check_button')));
    await tester.pumpAndSettle();
    expect(sentIds, containsAll([1, 2]));
  });

  testWidgets('IX-F04/05/06 source-backed result + severity + provenance',
      (tester) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(
      _wrap(
        InteractionCheckScreen(
          searchMedicines: (q) async => {
            'results': [
              {'id': 1, 'name': 'Warfarin'},
              {'id': 2, 'name': 'Aspirin'},
            ],
          },
          checkInteractions: (
              {medicineIds, medicines, includeDuplicateCheck = true}) async {
            return _sourceBackedResult();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _addTwoCatalogueMeds(tester);
    await tester.tap(find.byKey(const Key('interaction_check_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('interaction_source_card')), findsOneWidget);
    expect(find.textContaining('MAJOR'), findsOneWidget);
    expect(find.textContaining('local_interactions_table'), findsOneWidget);
    expect(find.textContaining('Source-backed'), findsWidgets);
  });

  testWidgets('IX-F07/08 unavailable state honest — not safe', (tester) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(
      _wrap(
        InteractionCheckScreen(
          searchMedicines: (q) async => {
            'results': [
              {'id': 1, 'name': 'Warfarin'},
              {'id': 2, 'name': 'Aspirin'},
            ],
          },
          checkInteractions: (
              {medicineIds, medicines, includeDuplicateCheck = true}) async {
            return _unavailableResult();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _addTwoCatalogueMeds(tester);
    await tester.tap(find.byKey(const Key('interaction_check_button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('unavailable'), findsWidgets);
    expect(
      find.textContaining('does not mean the medicines are confirmed safe'),
      findsWidgets,
    );
    expect(find.text('Risk Level: LOW'), findsNothing);
    expect(find.textContaining('All Clear'), findsNothing);
    expect(find.textContaining('No interactions found'), findsNothing);
  });

  testWidgets('IX-F09 duplicate warning remains separate', (tester) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(
      _wrap(
        InteractionCheckScreen(
          searchMedicines: (q) async => {
            'results': [
              {'id': 1, 'name': 'Warfarin'},
              {'id': 2, 'name': 'Aspirin'},
            ],
          },
          checkInteractions: (
              {medicineIds, medicines, includeDuplicateCheck = true}) async {
            return _unavailableResult();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _addTwoCatalogueMeds(tester);
    await tester.tap(find.byKey(const Key('interaction_check_button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('interaction_duplicate_warning')),
      findsOneWidget,
    );
    expect(
      find.textContaining('not a drug interaction'),
      findsOneWidget,
    );
  });

  testWidgets('IX-F10 loading prevents duplicate submission', (tester) async {
    _setLargeSurface(tester);
    var calls = 0;
    var release = false;
    await tester.pumpWidget(
      _wrap(
        InteractionCheckScreen(
          searchMedicines: (q) async => {
            'results': [
              {'id': 1, 'name': 'Warfarin'},
              {'id': 2, 'name': 'Aspirin'},
            ],
          },
          checkInteractions: (
              {medicineIds, medicines, includeDuplicateCheck = true}) async {
            calls += 1;
            while (!release) {
              await Future<void>.delayed(const Duration(milliseconds: 20));
            }
            return _sourceBackedResult();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _addTwoCatalogueMeds(tester);
    final btn = find.byKey(const Key('interaction_check_button'));
    await tester.tap(btn);
    await tester.pump();
    await tester.tap(btn);
    await tester.pump();
    expect(calls, 1);
    release = true;
    await tester.pumpAndSettle();
  });

  testWidgets('IX-F11 API failure safe error state', (tester) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(
      _wrap(
        InteractionCheckScreen(
          searchMedicines: (q) async => {
            'results': [
              {'id': 1, 'name': 'Warfarin'},
              {'id': 2, 'name': 'Aspirin'},
            ],
          },
          checkInteractions: (
              {medicineIds, medicines, includeDuplicateCheck = true}) async {
            throw Exception('backend down');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _addTwoCatalogueMeds(tester);
    await tester.tap(find.byKey(const Key('interaction_check_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('interaction_error_banner')), findsOneWidget);
    expect(find.byKey(const Key('interaction_retry_button')), findsOneWidget);
  });

  test('IX-F12 AI-only not presented as verified in UI/API copy', () {
    expect(screenSrc.toLowerCase().contains('ai-generated analysis'), isFalse);
    expect(legalSrc.contains('Unavailable information does not mean'), isTrue);
    expect(apiSrc.contains('/interactions/check'), isTrue);
    expect(screenSrc.contains('not verified as safe'), isTrue);
  });

  testWidgets('IX-F13 empty selection blocked', (tester) async {
    await tester.pumpWidget(
      _wrap(
        InteractionCheckScreen(
          checkInteractions: (
              {medicineIds, medicines, includeDuplicateCheck = true}) async {
            fail('should not call');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('interaction_check_button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Add at least 2 medicines'), findsOneWidget);
  });
}
