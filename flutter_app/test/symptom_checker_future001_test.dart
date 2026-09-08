import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/legal/legal_copy.dart';
import 'package:vitapulse_ai/features/symptoms/presentation/symptom_checker_screen.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppThemeBuilder.light(const AppThemeSettings()),
    home: child,
  );
}

void _setLargeSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Map<String, dynamic> _okResult({bool call000 = false}) => {
      'symptoms_assessed': ['Headache'],
      'is_diagnosis': false,
      'guidance_type': 'informational',
      'triage': {
        'urgency': call000 ? 'emergency' : 'soon',
        'urgency_label':
            call000 ? 'Seek emergency care' : 'See a GP within a few days',
        'possible_conditions': [
          {
            'name': 'Tension-type headache (consideration)',
            'likelihood': 'medium',
            'description': 'A common consideration — not a diagnosis.',
          }
        ],
        'recommendations': ['Rest', 'See a GP if symptoms persist'],
        'red_flags': call000 ? ['Chest pain with breathlessness'] : <String>[],
        'self_care': ['Hydrate'],
        'call_000': call000,
        'disclaimer': LegalCopy.symptomProfessionalNote,
      },
      'consultation_advice': {
        'consult_needed': true,
        'urgency_label': 'Within a few days',
        'suggested_specialist': 'GP',
      },
    };

void main() {
  final screenSrc = File(
    'lib/features/symptoms/presentation/symptom_checker_screen.dart',
  ).readAsStringSync();
  final apiSrc =
      File('lib/features/symptoms/data/symptoms_api.dart').readAsStringSync();
  final legalSrc =
      File('lib/features/legal/legal_copy.dart').readAsStringSync();

  Future<void> _addViaField(WidgetTester tester, String symptom) async {
    await tester.enterText(find.byKey(const Key('symptom_input_field')), symptom);
    await tester.tap(find.byKey(const Key('symptom_add_button')));
    await tester.pumpAndSettle();
  }

  Future<void> _submit(WidgetTester tester) async {
    final button = find.byKey(const Key('symptom_submit_button'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('SYM-F01 symptom checker screen renders', (tester) async {
    await tester.pumpWidget(_wrap(const SymptomCheckerScreen()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('symptom_checker_screen')), findsOneWidget);
    expect(find.text('Symptom Information'), findsOneWidget);
    expect(find.byKey(const Key('symptom_safety_banner')), findsOneWidget);
  });

  testWidgets('SYM-F02 empty submission is blocked', (tester) async {
    _setLargeSurface(tester);
    var called = false;
    await tester.pumpWidget(
      _wrap(
        SymptomCheckerScreen(
          checkSymptoms: (symptoms, {duration}) async {
            called = true;
            return _okResult();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _submit(tester);
    expect(called, isFalse);
    expect(find.textContaining('Add at least one symptom'), findsWidgets);
  });

  testWidgets('SYM-F03 whitespace-only add is blocked', (tester) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(_wrap(const SymptomCheckerScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('symptom_input_field')), '   ');
    await tester.tap(find.byKey(const Key('symptom_add_button')));
    await tester.pumpAndSettle();
    expect(find.byType(Chip), findsNothing);
  });

  testWidgets('SYM-F04 loading prevents duplicate submission', (tester) async {
    _setLargeSurface(tester);
    var calls = 0;
    await tester.pumpWidget(
      _wrap(
        SymptomCheckerScreen(
          checkSymptoms: (symptoms, {duration}) async {
            calls++;
            await Future<void>.delayed(const Duration(milliseconds: 400));
            return _okResult();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _addViaField(tester, 'Headache');
    final button = find.byKey(const Key('symptom_submit_button'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pump();
    expect(find.byKey(const Key('symptom_loading_state')), findsOneWidget);
    await tester.tap(button);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('SYM-F05 successful result renders', (tester) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(
      _wrap(
        SymptomCheckerScreen(
          checkSymptoms: (symptoms, {duration}) async => _okResult(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _addViaField(tester, 'Fever');
    await _submit(tester);
    expect(find.byKey(const Key('symptom_result_panel')), findsOneWidget);
    expect(find.text('Possible considerations'), findsOneWidget);
    expect(find.textContaining('Tension-type headache'), findsOneWidget);
  });

  testWidgets('SYM-F06 disclaimer / non-diagnostic copy visible',
      (tester) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(
      _wrap(
        SymptomCheckerScreen(
          checkSymptoms: (symptoms, {duration}) async => _okResult(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('not a diagnosis'), findsWidgets);
    await _addViaField(tester, 'Cough');
    await _submit(tester);
    expect(find.byKey(const Key('symptom_result_disclaimer')), findsOneWidget);
  });

  testWidgets('SYM-F07 backend failure renders safe error state',
      (tester) async {
    _setLargeSurface(tester);
    await tester.pumpWidget(
      _wrap(
        SymptomCheckerScreen(
          checkSymptoms: (symptoms, {duration}) async {
            throw Exception('network');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _addViaField(tester, 'Nausea');
    await _submit(tester);
    expect(find.byKey(const Key('symptom_error_state')), findsOneWidget);
    expect(find.byKey(const Key('symptom_result_panel')), findsNothing);
  });

  testWidgets('SYM-F08 retry works', (tester) async {
    _setLargeSurface(tester);
    var failOnce = true;
    await tester.pumpWidget(
      _wrap(
        SymptomCheckerScreen(
          checkSymptoms: (symptoms, {duration}) async {
            if (failOnce) {
              failOnce = false;
              throw Exception('temp');
            }
            return _okResult();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _addViaField(tester, 'Fatigue');
    await _submit(tester);
    expect(find.byKey(const Key('symptom_error_state')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('symptom_retry_button')));
    await tester.tap(find.byKey(const Key('symptom_retry_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('symptom_result_panel')), findsOneWidget);
  });

  test('SYM-F09 unauthorized handled via ErrorHandler path', () {
    expect(screenSrc.contains('ErrorHandler.show'), isTrue);
    expect(apiSrc.contains('/symptoms/check'), isTrue);
  });

  testWidgets('SYM-F10 emergency escalation UI', (tester) async {
    _setLargeSurface(tester);
    var dialed = false;
    String? opened;
    await tester.pumpWidget(
      _wrap(
        SymptomCheckerScreen(
          checkSymptoms: (symptoms, {duration}) async =>
              _okResult(call000: true),
          launchUri: (uri) async {
            dialed = uri.scheme == 'tel';
            return true;
          },
          openRoute: (path) => opened = path,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _addViaField(tester, 'Chest pain');
    await _submit(tester);
    expect(find.byKey(const Key('symptom_emergency_banner')), findsOneWidget);
    expect(find.text('CALL 000 NOW'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('symptom_call_000_button')));
    await tester.tap(find.byKey(const Key('symptom_call_000_button')));
    await tester.pumpAndSettle();
    expect(dialed, isTrue);
    await tester.ensureVisible(
        find.byKey(const Key('symptom_open_emergency_button')));
    await tester.tap(find.byKey(const Key('symptom_open_emergency_button')));
    await tester.pumpAndSettle();
    expect(opened, '/home/emergency');
  });

  test('SYM-F11 no diagnostic/prescribing chrome in normal UI', () {
    expect(screenSrc.contains('AI Symptom Checker'), isFalse);
    expect(screenSrc.contains('Possible Conditions'), isFalse);
    expect(screenSrc.contains('Possible considerations'), isTrue);
    expect(screenSrc.contains('Symptom Information'), isTrue);
    expect(screenSrc.toLowerCase().contains('prescrib'), isFalse);
    expect(screenSrc.contains('You have'), isFalse);
    expect(legalSrc.contains('not a diagnosis'), isTrue);
  });

  test('SYM-F12 family subject not invented on this screen', () {
    expect(screenSrc.contains('family_member_id'), isFalse);
    expect(apiSrc.contains('family_member'), isFalse);
  });
}
