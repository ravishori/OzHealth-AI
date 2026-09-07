import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/family/domain/family_subject.dart';
import 'package:vitapulse_ai/features/family/presentation/family_subject_switcher.dart';
import 'package:vitapulse_ai/features/family/providers/family_subject_provider.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

final _alex = {
  'id': 11,
  'name': 'Alex Rivera',
  'relationship': 'Child',
  'is_active': true,
};
final _sam = {
  'id': 12,
  'name': 'Sam Rivera',
  'relationship': 'Spouse',
  'is_active': true,
};
final _inactive = {
  'id': 13,
  'name': 'Inactive Person',
  'relationship': 'Other',
  'is_active': false,
};

void main() {
  group('FAMILY-SUBJECT unit', () {
    test('FAMILY-SUBJECT-01 default subject is Self', () {
      final c = FamilySubjectController();
      expect(c.isSelf, isTrue);
      expect(c.familyMemberId, isNull);
      expect(c.displayName, 'Myself');
    });

    test('FAMILY-SUBJECT-02 selecting owned active member changes subject',
        () async {
      final c = FamilySubjectController();
      await c.setOwnedActiveMembers([_alex, _sam]);
      final ok = await c.selectFamilyMember(11);
      expect(ok, isTrue);
      expect(c.familyMemberId, 11);
      expect(c.displayName, 'Alex Rivera');
      expect(c.isSelf, isFalse);
    });

    test('FAMILY-SUBJECT-03 switching back to Self works', () async {
      final c = FamilySubjectController();
      await c.setOwnedActiveMembers([_alex]);
      await c.selectFamilyMember(11);
      await c.selectSelf();
      expect(c.isSelf, isTrue);
      expect(c.familyMemberId, isNull);
      expect(c.displayName, 'Myself');
    });

    test('FAMILY-SUBJECT-04 multiple owned members selectable independently',
        () async {
      final c = FamilySubjectController();
      await c.setOwnedActiveMembers([_alex, _sam]);
      expect(await c.selectFamilyMember(11), isTrue);
      expect(c.familyMemberId, 11);
      expect(await c.selectFamilyMember(12), isTrue);
      expect(c.familyMemberId, 12);
      expect(c.displayName, 'Sam Rivera');
    });

    test('FAMILY-SUBJECT-05 selection survives intended session restore',
        () async {
      final persistence = MemoryFamilySubjectPersistence();
      final first = FamilySubjectController(persistence: persistence);
      await first.setOwnedActiveMembers([_alex, _sam]);
      await first.selectFamilyMember(12);

      final second = FamilySubjectController(persistence: persistence);
      await second.restore(members: [_alex, _sam]);
      expect(second.familyMemberId, 12);
      expect(second.displayName, 'Sam Rivera');
    });

    test('FAMILY-SUBJECT-06 logout clear resets to Self', () async {
      final persistence = MemoryFamilySubjectPersistence();
      final c = FamilySubjectController(persistence: persistence);
      await c.setOwnedActiveMembers([_alex]);
      await c.selectFamilyMember(11);
      await c.clear();
      expect(c.isSelf, isTrue);
      expect(c.ownedActiveMembers, isEmpty);
      expect(await persistence.readFamilyMemberId(), isNull);
    });

    test('FAMILY-SUBJECT-07 unowned id cannot become active subject', () async {
      final c = FamilySubjectController();
      await c.setOwnedActiveMembers([_alex]);
      final ok = await c.selectFamilyMember(999);
      expect(ok, isFalse);
      expect(c.isSelf, isTrue);
    });

    test('FAMILY-SUBJECT-08 inactive member cannot become active subject',
        () async {
      final c = FamilySubjectController();
      await c.setOwnedActiveMembers([_alex, _inactive]);
      expect(c.ownedActiveMembers.length, 1);
      final ok = await c.selectFamilyMember(13);
      expect(ok, isFalse);
      expect(c.isSelf, isTrue);
    });

    test('FAMILY-SUBJECT-11 stale persisted id falls back to Self', () async {
      final persistence = MemoryFamilySubjectPersistence();
      await persistence.writeFamilyMemberId(99);
      final c = FamilySubjectController(persistence: persistence);
      await c.restore(members: [_alex]);
      expect(c.isSelf, isTrue);
      expect(c.familyMemberId, isNull);
      expect(await persistence.readFamilyMemberId(), isNull);
    });

    test('FAMILY-SUBJECT-10 ownedFamilyMemberSelection rejects inactive', () {
      expect(
        ownedFamilyMemberSelection(
          requestedId: 13,
          ownedMembers: [_inactive, _alex],
        ),
        isNull,
      );
      expect(
        ownedFamilyMemberSelection(
          requestedId: 11,
          ownedMembers: [_inactive, _alex],
        ),
        11,
      );
    });

    test('FAMILY-SUBJECT-10 controller does not expose PHI via toString logs',
        () {
      // Guardrail: snapshot/controller stringification must not invent PHI dumps.
      final c = FamilySubjectController();
      final s = c.toString();
      expect(s.contains('Alex'), isFalse);
      expect(s.toLowerCase().contains('allergy'), isFalse);
    });
  });

  group('FAMILY-SUBJECT widget', () {
    testWidgets('switcher lists Self and owned members', (tester) async {
      final controller = FamilySubjectController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            familySubjectProvider.overrideWith((ref) => controller),
          ],
          child: MaterialApp(
            theme: AppThemeBuilder.light(const AppThemeSettings()),
            home: Scaffold(
              body: FamilySubjectSwitcher(
                loadMembers: () async => [_alex, _sam, _inactive],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<int?>), findsOneWidget);
      expect(controller.isSelf, isTrue);

      await tester.tap(find.byType(DropdownButtonFormField<int?>));
      await tester.pumpAndSettle();
      expect(find.text('Myself').hitTestable(), findsWidgets);
      expect(find.text('Alex Rivera'), findsWidgets);
      expect(find.text('Sam Rivera'), findsWidgets);
      expect(find.text('Inactive Person'), findsNothing);

      await tester.tap(find.text('Alex Rivera').last);
      await tester.pumpAndSettle();
      expect(controller.familyMemberId, 11);
    });
  });
}
