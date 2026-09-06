import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/records/presentation/upload_record_screen.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppThemeBuilder.light(const AppThemeSettings()),
    home: child,
  );
}

void main() {
  final uploadSrc =
      File('lib/features/records/presentation/upload_record_screen.dart')
          .readAsStringSync();
  final apiSrc =
      File('lib/features/records/data/records_api.dart').readAsStringSync();
  final manifestSrc =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  test('RECORD-CAMERA-FL-01 Camera action is available', () {
    expect(uploadSrc.contains("title: const Text('Take photo')"), isTrue);
    expect(uploadSrc.contains("key: const Key('record-upload-source-camera')"),
        isTrue);
    expect(uploadSrc.contains('ImageSource.camera'), isTrue);
  });

  testWidgets('RECORD-CAMERA-FL-01 source sheet shows Camera', (tester) async {
    await tester.pumpWidget(_wrap(const UploadRecordScreen()));
    await tester.pump();
    await tester.tap(find.byKey(const Key('record-upload-file-area')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('record-upload-source-camera')), findsOneWidget);
    expect(find.text('Take photo'), findsOneWidget);
  });

  test('RECORD-CAMERA-FL-02 camera uses existing image_picker', () {
    expect(uploadSrc.contains("import 'package:image_picker/image_picker.dart'"),
        isTrue);
    expect(uploadSrc.contains('ImagePicker()'), isTrue);
    expect(uploadSrc.contains('pickImage'), isTrue);
    expect(uploadSrc.contains('ImageSource.camera'), isTrue);
    expect(uploadSrc.contains('ImageSource.gallery'), isTrue);
    expect(File('pubspec.yaml').readAsStringSync().contains('image_picker:'),
        isTrue);
    expect(manifestSrc.contains('android.permission.CAMERA'), isTrue);
  });

  test('RECORD-CAMERA-FL-03 captured image enters existing upload flow', () {
    expect(uploadSrc.contains('_selectedFile = File(picked.path)'), isTrue);
    expect(uploadSrc.contains('_isImage = true'), isTrue);
    expect(uploadSrc.contains("ApiClient.uploadFile('/records/upload'"), isTrue);
    expect(uploadSrc.contains('LoadingButton'), isTrue);
    expect(uploadSrc.contains("text: 'Upload Record'"), isTrue);
    expect(apiSrc.contains("/records/upload"), isTrue);
  });

  testWidgets('RECORD-CAMERA-FL-04 camera cancellation does not upload',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        UploadRecordScreen(
          imagePicker: (_) async => null,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('record-upload-file-area')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('record-upload-source-camera')));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Upload Record'), findsWidgets);
    expect(find.text('Record uploaded successfully'), findsNothing);
  });

  testWidgets('RECORD-CAMERA-FL-05 camera failure produces a safe error',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        UploadRecordScreen(
          imagePicker: (_) async {
            throw Exception('unavailable');
          },
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('record-upload-file-area')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('record-upload-source-camera')));
    await tester.pump();
    await tester.pump();
    expect(
      find.text('Could not open the camera. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('/data/'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
  });

  test('RECORD-CAMERA-FL-06 existing Gallery flow remains available', () {
    expect(uploadSrc.contains('ImageSource.gallery'), isTrue);
    expect(uploadSrc.contains("title: const Text('Choose from gallery')"),
        isTrue);
    expect(uploadSrc.contains("key: const Key('record-upload-source-gallery')"),
        isTrue);
  });

  testWidgets('RECORD-CAMERA-FL-06/07 gallery and PDF remain in the sheet',
      (tester) async {
    await tester.pumpWidget(_wrap(const UploadRecordScreen()));
    await tester.pump();
    await tester.tap(find.byKey(const Key('record-upload-file-area')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('record-upload-source-gallery')), findsOneWidget);
    expect(find.byKey(const Key('record-upload-source-pdf')), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
    expect(find.text('Choose PDF'), findsOneWidget);
  });

  test('RECORD-CAMERA-FL-07 existing PDF/document flow remains available', () {
    expect(uploadSrc.contains('FilePicker.platform.pickFiles'), isTrue);
    expect(uploadSrc.contains("'pdf'"), isTrue);
    expect(uploadSrc.contains("title: const Text('Choose PDF')"), isTrue);
  });

  test('RECORD-CAMERA-FL-08 duplicate submission is prevented', () {
    expect(uploadSrc.contains('if (_loading) return'), isTrue);
    expect(uploadSrc.contains('if (_picking || _loading) return'), isTrue);
    expect(uploadSrc.contains('LoadingButton'), isTrue);
    expect(uploadSrc.contains('loading: _loading'), isTrue);
  });

  test('RECORD-CAMERA-FL-09 no sensitive image/path/payload logging', () {
    expect(uploadSrc.contains('debugPrint'), isFalse);
    expect(uploadSrc.contains('print('), isFalse);
    expect(uploadSrc.contains('DebugLogger'), isFalse);
    expect(apiSrc.contains('debugPrint'), isFalse);
    expect(apiSrc.contains('print('), isFalse);
  });

  test('RECORD-CAMERA-FL-10 existing authenticated upload contract remains', () {
    expect(uploadSrc.contains("ApiClient.uploadFile('/records/upload'"), isTrue);
    expect(uploadSrc.contains('MultipartFile.fromFile'), isTrue);
    expect(apiSrc.contains("ApiClient.uploadFile('/records/upload'"), isTrue);
    expect(uploadSrc.contains('FirebaseMessaging'), isFalse);
    expect(uploadSrc.contains('/uploads'), isFalse);
  });
}
