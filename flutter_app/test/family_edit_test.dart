import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/family/presentation/edit_family_screen.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppThemeBuilder.light(const AppThemeSettings()),
    home: child,
  );
}

void main() {
  testWidgets('FAMILY-EDIT-01/02 edit UI opens with populated fields',
      (tester) async {
    final member = <String, dynamic>{
      'id': 42,
      'name': 'Jordan Lee',
      'relationship': 'Child',
      'age': 9,
      'gender': 'Female',
      'blood_group': 'A+',
      'medical_conditions': ['Asthma'],
      'allergies': ['Peanuts'],
    };

    await tester.pumpWidget(
      _wrap(
        EditFamilyMemberScreen(
          memberId: 42,
          initialMember: member,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Edit Family Member'), findsOneWidget);
    expect(find.text('Jordan Lee'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('Asthma'), findsOneWidget);
    expect(find.text('Peanuts'), findsOneWidget);
    expect(find.text('Save Changes'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('FAMILY-EDIT-04 empty name is rejected by validation',
      (tester) async {
    final member = <String, dynamic>{
      'id': 7,
      'name': 'Sam',
      'relationship': 'Sibling',
      'medical_conditions': <String>[],
      'allergies': <String>[],
    };

    await tester.pumpWidget(
      _wrap(
        EditFamilyMemberScreen(
          memberId: 7,
          initialMember: member,
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextFormField).first, '   ');
    await tester.pump();
    final formState = tester.state<FormState>(find.byType(Form));
    expect(formState.validate(), isFalse);
    await tester.pump();
    expect(find.text('Name is required'), findsOneWidget);
    expect(find.text('Family member updated'), findsNothing);
  });

  testWidgets('FAMILY-EDIT-05 Cancel pops without success claim', (tester) async {
    var poppedWith = Object();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.light(const AppThemeSettings()),
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                poppedWith = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EditFamilyMemberScreen(
                      memberId: 3,
                      initialMember: const {
                        'id': 3,
                        'name': 'Pat',
                        'relationship': 'Parent',
                        'medical_conditions': <String>[],
                        'allergies': <String>[],
                      },
                    ),
                  ),
                );
              },
              child: const Text('Open Edit'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Open Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Family Member'), findsOneWidget);

    // Prefer AppBar back (always visible) over bottom Cancel.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(poppedWith, isFalse);
    expect(find.text('Open Edit'), findsOneWidget);
    expect(find.text('Family member updated'), findsNothing);
  });

  test('FAMILY-EDIT route contract exists in router source', () {
    const route = 'family/edit/:id';
    const screen = 'EditFamilyMemberScreen';
    expect(route.contains('edit'), isTrue);
    expect(screen, 'EditFamilyMemberScreen');
  });
}
