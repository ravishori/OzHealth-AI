import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// HN-MED-007 — Flutter contracts for duplicate medicine warnings.
void main() {
  final detailSrc = File(
    'lib/features/prescriptions/presentation/prescription_detail_screen.dart',
  ).readAsStringSync();
  final reviewSrc = File(
    'lib/features/prescriptions/presentation/prescription_review_screen.dart',
  ).readAsStringSync();

  test('MED-DUP-FE-01 no warning when safe / empty', () {
    expect(detailSrc.contains("dups['safe'] == true"), isTrue);
    expect(detailSrc.contains('dupList.isEmpty'), isTrue);
    expect(detailSrc.contains('SizedBox.shrink()'), isTrue);
  });

  test('MED-DUP-FE-02 possible duplicate warning is displayed', () {
    expect(detailSrc.contains('Possible duplicate medicines'), isTrue);
    expect(detailSrc.contains("Key('prescription_duplicate_warnings')") ||
            detailSrc.contains('prescription_duplicate_warnings'),
        isTrue);
    expect(detailSrc.contains('duplicate_warnings'), isTrue);
    expect(detailSrc.contains('_buildDuplicateWarnings'), isTrue);
  });

  test('MED-DUP-FE-03 warning identifies affected medicines', () {
    expect(detailSrc.contains('_medicineLabel'), isTrue);
    expect(detailSrc.contains("d['medicine_a']"), isTrue);
    expect(detailSrc.contains("d['medicine_b']"), isTrue);
  });

  test('MED-DUP-FE-04 warning does not make unsupported clinical claims', () {
    expect(detailSrc.contains('Possible duplicate medicines'), isTrue);
    expect(detailSrc.toLowerCase().contains('not a diagnosis'), isTrue);
    expect(detailSrc.toLowerCase().contains('pharmacist'), isTrue);
    // Must not order patients to stop therapy.
    expect(detailSrc.toLowerCase().contains('you must not take'), isFalse);
    expect(detailSrc.toLowerCase().contains('these medicines are unsafe'), isFalse);
    expect(detailSrc.toLowerCase().contains('your doctor made an error'), isFalse);
  });

  test('MED-DUP-FE-05 existing prescription detail/review behaviour intact', () {
    expect(detailSrc.contains("ApiClient.get('/prescriptions/"), isTrue);
    expect(detailSrc.contains('_buildMedicinesTable'), isTrue);
    expect(detailSrc.contains('_buildAllergyAlerts'), isTrue);
    expect(reviewSrc.contains('/prescriptions/confirm'), isTrue);
    expect(reviewSrc.contains("/home/prescriptions/\$id") ||
            reviewSrc.contains('/home/prescriptions/\$id'),
        isTrue);
  });
}
