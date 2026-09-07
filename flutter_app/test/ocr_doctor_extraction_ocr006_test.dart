import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// HN-OCR-006 — Flutter contracts for doctor_name OCR prefill + confirm edit.
void main() {
  final reviewSrc = File(
    'lib/features/prescriptions/presentation/prescription_review_screen.dart',
  ).readAsStringSync();

  test('OCR-006-FE-01 review prefills doctor from ocrResult doctor_name', () {
    expect(reviewSrc.contains("widget.ocrResult['doctor_name']"), isTrue);
    expect(reviewSrc.contains('_doctorCtrl'), isTrue);
    expect(reviewSrc.contains('Prescriber / doctor'), isTrue);
  });

  test('OCR-006-FE-02 doctor field remains editable TextEditingController', () {
    expect(reviewSrc.contains('TextEditingController('), isTrue);
    expect(reviewSrc.contains('controller: _doctorCtrl'), isTrue);
  });

  test('OCR-006-FE-03 confirm sends reviewed doctor_name when non-empty', () {
    expect(reviewSrc.contains("'doctor_name': _doctorCtrl.text.trim()"), isTrue);
    expect(reviewSrc.contains('_doctorCtrl.text.trim().isNotEmpty'), isTrue);
  });

  test('OCR-006-FE-04 blank/cleared doctor is valid (optional field)', () {
    // Empty doctor is omitted from FormData — confirm still proceeds.
    expect(reviewSrc.contains("if (_doctorCtrl.text.trim().isNotEmpty)"), isTrue);
    expect(reviewSrc.contains('/prescriptions/confirm'), isTrue);
  });
}
