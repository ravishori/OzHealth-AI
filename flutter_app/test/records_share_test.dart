import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/records/data/records_share.dart';

void main() {
  final screenSrc =
      File('lib/features/records/presentation/records_screen.dart')
          .readAsStringSync();
  final shareSrc =
      File('lib/features/records/data/records_share.dart').readAsStringSync();

  test('RECORD-SHARE-FL-01 download is requested before sharing', () {
    expect(shareSrc.contains("downloadBytes('/records/\$recordId/file')"),
        isTrue);
    expect(screenSrc.contains('RecordsShare.shareOwnedRecord'), isTrue);
    expect(screenSrc.contains('_shareRecordFile'), isTrue);
    final shareFn = shareSrc.substring(
      shareSrc.indexOf('static Future<void> shareOwnedRecord'),
    );
    final downloadIdx = shareFn.indexOf('download ?? defaultDownload');
    final shareIdx = shareFn.indexOf('Share.shareXFiles');
    expect(downloadIdx, greaterThanOrEqualTo(0));
    expect(shareIdx, greaterThan(downloadIdx));
  });

  test('RECORD-SHARE-FL-02 successful download writes a temp file', () async {
    final tmp = Directory.systemTemp.createTempSync('record_share_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    String? sharedPath;
    await RecordsShare.shareOwnedRecord(
      recordId: 7,
      record: {
        'record_type': 'lab_report',
        'record_date': '2026-09-06',
        'file_type': 'pdf',
      },
      download: (id) async {
        expect(id, 7);
        return [1, 2, 3, 4];
      },
      temporaryDirectory: () async => tmp,
      sharePath: (path) async {
        sharedPath = path;
        final f = File(path);
        expect(f.existsSync(), isTrue);
        expect(f.readAsBytesSync(), [1, 2, 3, 4]);
      },
    );
    expect(sharedPath, isNotNull);
    expect(
      sharedPath!.split(Platform.pathSeparator).last,
      'medical_record_lab_report_20260906.pdf',
    );
  });

  test('RECORD-SHARE-FL-03 native share is invoked with the temp file', () {
    expect(shareSrc.contains('Share.shareXFiles'), isTrue);
    expect(shareSrc.contains('XFile(path)'), isTrue);
    expect(screenSrc.contains('Share file'), isTrue);
    expect(screenSrc.contains('record_share_button'), isTrue);
  });

  test('RECORD-SHARE-FL-04 filename has no ids or clinical content', () {
    final name = safeMedicalRecordShareFilename(
      recordType: 'lab_report',
      recordDate: '2026-03-15T10:00:00Z',
      fileType: 'pdf',
      originalFileName: 'John_Smith_HbA1c_secret.pdf',
    );
    expect(name, 'medical_record_lab_report_20260315.pdf');
    expect(name.contains('John'), isFalse);
    expect(name.contains('Smith'), isFalse);
    expect(name.contains('HbA1c'), isFalse);
    expect(name.contains('secret'), isFalse);
    expect(RegExp(r'\d{3,}').hasMatch(name.replaceAll('20260315', '')), isFalse);

    final fallback = safeMedicalRecordShareFilename(
      recordType: null,
      recordDate: 'not-a-date',
      fileType: null,
      originalFileName: 'weird',
    );
    expect(fallback, 'medical_record_record_undated.bin');
    expect(fallback.contains('id'), isFalse);
  });

  test('RECORD-SHARE-FL-05 download failure does not invoke share', () async {
    var shareCalled = false;
    await expectLater(
      RecordsShare.shareOwnedRecord(
        recordId: 9,
        record: {'record_type': 'other', 'file_type': 'pdf'},
        download: (_) async => throw StateError('denied'),
        sharePath: (_) async => shareCalled = true,
      ),
      throwsA(isA<StateError>()),
    );
    expect(shareCalled, isFalse);
  });

  test('RECORD-SHARE-FL-06 existing view/download remains intact', () {
    expect(screenSrc.contains('_viewRecordFile'), isTrue);
    expect(screenSrc.contains("downloadBytes('/records/\$id/file')"), isTrue);
    expect(screenSrc.contains('launchUrl'), isTrue);
    expect(screenSrc.contains('LaunchMode.externalApplication'), isTrue);
    expect(screenSrc.contains('View / download file'), isTrue);
  });

  test('RECORD-SHARE-FL-07 loading state blocks duplicate file actions', () {
    expect(screenSrc.contains('fileBusy'), isTrue);
    expect(screenSrc.contains('onPressed: fileBusy'), isTrue);
    expect(screenSrc.contains('CircularProgressIndicator'), isTrue);
  });

  test('RECORD-SHARE-FL-08 share failure shows a safe error', () {
    expect(
      screenSrc.contains('Could not share file. Please try again.'),
      isTrue,
    );
    expect(shareSrc.contains('DebugLogger'), isFalse);
    expect(shareSrc.contains('print('), isFalse);
    expect(shareSrc.contains('debugPrint'), isFalse);
    expect(shareSrc.contains("record['notes']"), isFalse);
  });
}
