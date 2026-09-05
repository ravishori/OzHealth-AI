import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/family/data/family_api.dart';
import 'package:vitapulse_ai/features/family/presentation/family_screen.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

void main() {
  test('FAMILY-PHOTO-01 FamilyApi has no uploadPhoto capability', () {
    final src = File('lib/features/family/data/family_api.dart').readAsStringSync();
    expect(src.contains('uploadPhoto'), isFalse);
    expect(src.contains('/photo'), isFalse);
    expect(src.contains('MultipartFile'), isFalse);
    expect(src.contains('FormData'), isFalse);
  });

  test('FAMILY-PHOTO-05 HN-PROF-008 UserApi.uploadPhoto remains present', () {
    final src = File('lib/features/profile/data/user_api.dart').readAsStringSync();
    expect(src.contains('static Future<Map<String, dynamic>> uploadPhoto'), isTrue);
    expect(src.contains('/users/me/photo'), isTrue);
  });

  test('FAMILY-PHOTO-02/03 Family screen uses initials CircleAvatar, not photo picker',
      () {
    final src =
        File('lib/features/family/presentation/family_screen.dart').readAsStringSync();
    expect(src.contains('_avatarCircle'), isTrue);
    expect(src.contains('CircleAvatar'), isTrue);
    expect(src.contains('ImagePicker'), isFalse);
    expect(src.contains('uploadPhoto'), isFalse);
    expect(src.contains('family/') && src.contains('photo'), isFalse);
  });

  testWidgets('FAMILY-PHOTO-03/04 Family screen builds with initials avatar contract',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.light(const AppThemeSettings()),
        home: const FamilyScreen(),
      ),
    );
    await tester.pump();
    // Title present; loading or list — no photo upload controls
    expect(find.text('Family Members'), findsOneWidget);
    expect(find.textContaining('Upload photo'), findsNothing);
    expect(find.textContaining('Change photo'), findsNothing);
    expect(find.byIcon(Icons.camera_alt), findsNothing);
    expect(find.byIcon(Icons.photo_camera), findsNothing);
  });

  test('FAMILY-PHOTO-04 FamilyApi CRUD surface remains', () {
    expect(FamilyApi.getMembers, isA<Function>());
    expect(FamilyApi.getMember, isA<Function>());
    expect(FamilyApi.addMember, isA<Function>());
    expect(FamilyApi.updateMember, isA<Function>());
    expect(FamilyApi.deleteMember, isA<Function>());
  });
}
