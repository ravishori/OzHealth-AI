import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// HN-RX-003 — Flutter contracts for manual prescription entry.
void main() {
  final entrySrc = File(
    'lib/features/prescriptions/presentation/prescription_manual_entry_screen.dart',
  ).readAsStringSync();
  final reviewSrc = File(
    'lib/features/prescriptions/presentation/prescription_manual_review_screen.dart',
  ).readAsStringSync();
  final apiSrc = File(
    'lib/features/prescriptions/data/prescription_api.dart',
  ).readAsStringSync();
  final routerSrc = File('lib/core/router/app_router.dart').readAsStringSync();
  final drawerSrc =
      File('lib/features/home/presentation/app_drawer.dart').readAsStringSync();
  final ocrReviewSrc = File(
    'lib/features/prescriptions/presentation/prescription_review_screen.dart',
  ).readAsStringSync();
  final scanSrc = File(
    'lib/features/prescriptions/presentation/prescription_scan_screen.dart',
  ).readAsStringSync();

  test('RX-MANUAL-FE-01 manual entry screen opens via route', () {
    expect(routerSrc.contains('prescriptions/manual'), isTrue);
    expect(routerSrc.contains('PrescriptionManualEntryScreen'), isTrue);
    expect(entrySrc.contains("Key('prescription_manual_entry_screen')"), isTrue);
    expect(drawerSrc.contains('/home/prescriptions/manual'), isTrue);
  });

  test('RX-MANUAL-FE-02 medicine can be entered or catalogue-selected', () {
    expect(entrySrc.contains("Key('manual_rx_medicine_name_"), isTrue);
    expect(entrySrc.contains('MedicineApi.search'), isTrue);
    expect(entrySrc.contains('catalog_medicine_id'), isTrue);
    expect(entrySrc.contains('_pickFromCatalogue'), isTrue);
    expect(entrySrc.contains("Key('manual_rx_add_medicine')"), isTrue);
  });

  test('RX-MANUAL-FE-03 review screen appears with preserved data', () {
    expect(routerSrc.contains('prescriptions/manual/review'), isTrue);
    expect(routerSrc.contains('PrescriptionManualReviewScreen'), isTrue);
    expect(reviewSrc.contains("Key('prescription_manual_review_screen')"), isTrue);
    expect(entrySrc.contains("'medicines': medicines"), isTrue);
    expect(entrySrc.contains("'doctor_name':"), isTrue);
    expect(reviewSrc.contains("Key('manual_rx_review_med_"), isTrue);
  });

  test('RX-MANUAL-FE-04 doctor_name can be entered edited cleared', () {
    expect(entrySrc.contains("Key('manual_rx_doctor_name')"), isTrue);
    expect(reviewSrc.contains("Key('manual_rx_review_doctor_name')"), isTrue);
    expect(apiSrc.contains("if (doctorName != null && doctorName.trim().isNotEmpty)"),
        isTrue);
  });

  test('RX-MANUAL-FE-05 confirm invokes manual prescription API contract', () {
    expect(apiSrc.contains('/prescriptions/manual'), isTrue);
    expect(apiSrc.contains('createManualPrescription'), isTrue);
    expect(reviewSrc.contains('PrescriptionApi.createManualPrescription'), isTrue);
    expect(reviewSrc.contains("Key('manual_rx_confirm_save')"), isTrue);
    expect(reviewSrc.contains("/home/prescriptions/\$id") ||
            reviewSrc.contains('/home/prescriptions/\$id'),
        isTrue);
    // Must not route confirm through OCR confirm multipart.
    expect(reviewSrc.contains('/prescriptions/confirm'), isFalse);
    expect(reviewSrc.contains('/prescriptions/ocr'), isFalse);
  });

  test('RX-MANUAL-FE-06 cancellation does not save', () {
    expect(entrySrc.contains("Key('manual_rx_cancel')"), isTrue);
    expect(reviewSrc.contains("Key('manual_rx_discard')"), isTrue);
    expect(reviewSrc.contains('Cancel without saving'), isTrue);
    // Discard navigates home without calling create API in that handler.
    final discardIdx = reviewSrc.indexOf("Key('manual_rx_discard')");
    expect(discardIdx, greaterThan(-1));
    final discardBlock = reviewSrc.substring(discardIdx, discardIdx + 350);
    expect(discardBlock.contains('createManualPrescription'), isFalse);
    expect(discardBlock.contains("context.go('/home')"), isTrue);
  });

  test('RX-MANUAL-FE-07 family subject defaults to Self', () {
    expect(entrySrc.contains("Key('manual_rx_family_member')"), isTrue);
    expect(entrySrc.contains("'Self'"), isTrue);
    expect(entrySrc.contains("'/family/'"), isTrue);
    expect(entrySrc.contains("'family_member_id': _selectedFamilyMemberId"), isTrue);
    expect(apiSrc.contains('family_member_id'), isTrue);
  });

  test('RX-MANUAL-FE-10 Self omits family_member_id; owned id submitted', () {
    // API only includes family_member_id when non-null (Self → omit/NULL).
    expect(apiSrc.contains('if (familyMemberId != null)'), isTrue);
    expect(
      apiSrc.contains("'family_member_id': familyMemberId"),
      isTrue,
    );
    expect(entrySrc.contains('_selectedFamilyMemberId'), isTrue);
    expect(reviewSrc.contains('familyMemberId: widget.familyMemberId'), isTrue);
  });

  test('RX-MANUAL-FE-11 required validation and double-submit guard', () {
    expect(entrySrc.contains('_formKey.currentState!.validate()'), isTrue);
    expect(entrySrc.contains('Enter at least one medicine name.'), isTrue);
    expect(entrySrc.contains("validator: (v)"), isTrue);
    expect(reviewSrc.contains('onPressed: _saving ? null : _confirm'), isTrue);
    expect(reviewSrc.contains('setState(() => _saving = true)'), isTrue);
  });

  test('RX-MANUAL-FE-12 API failure handled safely without OCR confirm', () {
    expect(reviewSrc.contains('on DioException catch'), isTrue);
    expect(reviewSrc.contains('Could not save prescription.'), isTrue);
    expect(reviewSrc.contains('Text(e.toString())'), isFalse);
    expect(reviewSrc.contains('/prescriptions/confirm'), isFalse);
  });

  test('RX-MANUAL-FE-08 safety banner non-clinical', () {
    expect(entrySrc.contains('ClinicalDisclaimerKind.prescriptionManual'), isTrue);
    expect(reviewSrc.contains('ClinicalDisclaimerKind.prescriptionManual'), isTrue);
    final legal = File('lib/features/legal/legal_copy.dart').readAsStringSync();
    expect(legal.contains('prescriptionManualBanner'), isTrue);
    final bannerStart = legal.indexOf('prescriptionManualBanner');
    final banner = legal.substring(bannerStart, bannerStart + 450).toLowerCase();
    expect(banner.contains('does not verify'), isTrue);
    expect(banner.contains('authenticity'), isTrue);
    expect(banner.contains('ahpra'), isFalse);
    expect(banner.contains('clinically verified'), isFalse);
    expect(banner.contains('prescription authenticity verified'), isFalse);
  });

  test('RX-MANUAL-FE-09 OCR path remains intact and separate', () {
    expect(scanSrc.contains('/prescriptions/ocr'), isTrue);
    expect(ocrReviewSrc.contains('/prescriptions/confirm'), isTrue);
    expect(routerSrc.contains('PrescriptionReviewScreen'), isTrue);
    expect(routerSrc.contains('prescriptions/scan'), isTrue);
  });
}
