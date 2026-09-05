import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/legal/legal_copy.dart';

void main() {
  test('SOS honesty + emergency disclaimer contracts are present', () {
    const honestySubtitle =
        'Records your GPS for dial-back. Contacts are NOT auto-notified.';
    const disclaimer = LegalCopy.emergencyBanner;
    const emptyContacts =
        'Add contacts you can dial manually in an emergency';

    expect(honestySubtitle.contains('NOT auto-notified'), isTrue);
    expect(disclaimer.contains('Medical emergency disclaimer'), isTrue);
    expect(disclaimer.contains('call 000'), isTrue);
    expect(emptyContacts.contains('dial manually'), isTrue);
    expect(honestySubtitle.toLowerCase().contains('shared with contacts'),
        isFalse);
  });

  test('SOS hold uses explicit 3s controller not onLongPress', () {
    final holdSrc = File(
            'lib/features/emergency/presentation/sos_hold_button.dart')
        .readAsStringSync();
    final screenSrc = File(
            'lib/features/emergency/presentation/emergency_screen.dart')
        .readAsStringSync();
    expect(holdSrc.contains('holdDuration = Duration(seconds: 3)'), isTrue);
    expect(holdSrc.contains('onLongPress:'), isFalse);
    expect(holdSrc.contains('onPointerDown'), isTrue);
    expect(screenSrc.contains('SosHoldButton'), isTrue);
    expect(screenSrc.contains('onLongPress:'), isFalse);
    expect(screenSrc.contains('launchUrl') && screenSrc.contains('tel:'),
        isTrue);
    expect(screenSrc.contains('ClinicalDisclaimerKind.emergency'), isTrue);
  });
}
