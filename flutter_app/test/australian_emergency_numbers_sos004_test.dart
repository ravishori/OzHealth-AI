import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/emergency/data/au_emergency_numbers.dart';
import 'package:vitapulse_ai/features/legal/legal_copy.dart';

/// HN-SOS-004 — Australian emergency numbers contracts.
void main() {
  final screenSrc = File(
    'lib/features/emergency/presentation/emergency_screen.dart',
  ).readAsStringSync();
  final numbersSrc = File(
    'lib/features/emergency/data/au_emergency_numbers.dart',
  ).readAsStringSync();

  AuEmergencyNumber byLabel(String label) =>
      kAustralianEmergencyNumbers.firstWhere((n) => n.label == label);

  test('SOS004-01 000 is displayed', () {
    expect(kAustralianEmergencyNumbers.any((n) => n.label == '000'), isTrue);
    expect(screenSrc.contains("label == '000'"), isTrue);
    expect(screenSrc.contains('Primary emergency'), isTrue);
  });

  test('SOS004-02 112 is displayed', () {
    expect(kAustralianEmergencyNumbers.any((n) => n.label == '112'), isTrue);
    expect(LegalCopy.emergencyBanner.contains('112'), isTrue);
    expect(byLabel('112').category, AuEmergencyCategory.emergency);
    expect(byLabel('112').subtitle.toLowerCase(), contains('mobile'));
  });

  test('SOS004-03 106 (TTY) is displayed', () {
    final n = byLabel('106');
    expect(n.description, 'TTY');
    expect(n.subtitle.toLowerCase(), contains('tty'));
    expect(n.category, AuEmergencyCategory.emergency);
    expect(screenSrc.contains('au_number_\${n.dialDigits}'), isTrue);
    expect(n.dialDigits, '106');
  });

  test('SOS004-04 13 11 26 is displayed', () {
    expect(
      kAustralianEmergencyNumbers.any((n) => n.label == '13 11 26'),
      isTrue,
    );
    expect(byLabel('13 11 26').description, contains('Poisons'));
  });

  test('SOS004-05 1800 022 222 is displayed', () {
    expect(
      kAustralianEmergencyNumbers.any((n) => n.label == '1800 022 222'),
      isTrue,
    );
    expect(byLabel('1800 022 222').description.toLowerCase(), contains('health'));
  });

  test('SOS004-06 000 remains the primary emergency action', () {
    final emergency = kAustralianEmergencyNumbers
        .where((n) => n.category == AuEmergencyCategory.emergency)
        .toList();
    expect(emergency.first.label, '000');
    expect(screenSrc.contains("isPrimary: n.label == '000'"), isTrue);
    expect(screenSrc.contains('Primary emergency'), isTrue);
  });

  test('SOS004-07 106 is clearly identified as TTY', () {
    final n = byLabel('106');
    expect(n.description, 'TTY');
    expect(n.semanticLabel.toLowerCase(), contains('tty'));
    expect(n.semanticLabel, isNot(contains('SMS')));
    expect(n.semanticLabel.toLowerCase(), isNot(contains('whatsapp')));
    expect(n.semanticLabel.toLowerCase(), isNot(contains('chat emergency')));
  });

  test('SOS004-08 Poisons Information Centre is not represented as 000', () {
    final n = byLabel('13 11 26');
    expect(n.category, AuEmergencyCategory.healthSupport);
    expect(n.label, isNot('000'));
    expect(n.description.toLowerCase(), isNot(contains('emergency services')));
    expect(screenSrc.contains('Health support'), isTrue);
    expect(
      screenSrc.contains('not a substitute for calling 000'),
      isTrue,
    );
  });

  test('SOS004-09 Healthdirect is not represented as 000', () {
    final n = byLabel('1800 022 222');
    expect(n.category, AuEmergencyCategory.healthSupport);
    expect(n.label, isNot('000'));
    expect(n.description.toLowerCase(), isNot(contains('emergency services')));
  });

  test('SOS004-10 each actionable number uses existing dial mechanism', () {
    expect(screenSrc.contains('Future<void> _callNumber(String number)'), isTrue);
    expect(screenSrc.contains("Uri.parse('tel:\$cleaned')"), isTrue);
    expect(screenSrc.contains('canLaunchUrl(uri)'), isTrue);
    expect(screenSrc.contains('launchUrl(uri)'), isTrue);
    expect(screenSrc.contains('onCall: () => _callNumber(n.label)'), isTrue);
    // Single dial helper — no second launcher.
    expect('tel:'.allMatches(screenSrc).length, greaterThanOrEqualTo(1));
    expect(screenSrc.contains('kAustralianEmergencyNumbers'), isTrue);
  });

  test('SOS004-11 UI does not claim call completed when dialler launched', () {
    expect(screenSrc.contains('does not place the call'), isTrue);
    expect(
      screenSrc.contains(
        'Opens the phone dialler. Does not complete the call automatically.',
      ),
      isTrue,
    );
    expect(screenSrc.toLowerCase().contains('emergency services notified'), isFalse);
    expect(screenSrc.toLowerCase().contains('has contacted 000'), isFalse);
    expect(screenSrc.toLowerCase().contains('call was completed'), isFalse);
    expect(screenSrc.toLowerCase().contains('successfully called'), isFalse);
    expect(numbersSrc.toLowerCase().contains('does not auto-call'), isTrue);
  });

  test('SOS004-12 dial-launch failure shows established safe error state', () {
    expect(screenSrc.contains("Cannot launch phone dialler."), isTrue);
    expect(screenSrc.contains('_showError('), isTrue);
  });

  group('SOS004 accessibility semantics', () {
    test('000 semantic label', () {
      expect(
        byLabel('000').semanticLabel,
        'Call emergency services 000',
      );
    });

    test('112 semantic label', () {
      expect(
        byLabel('112').semanticLabel,
        'Call emergency number 112',
      );
    });

    test('106 identifies TTY', () {
      expect(
        byLabel('106').semanticLabel,
        'Call TTY emergency number 106',
      );
    });

    test('13 11 26 includes service name', () {
      expect(
        byLabel('13 11 26').semanticLabel,
        contains('Poisons Information'),
      );
    });

    test('1800 022 222 includes service name', () {
      expect(
        byLabel('1800 022 222').semanticLabel.toLowerCase(),
        contains('healthdirect'),
      );
    });

    test('emergency vs support not color-only', () {
      expect(screenSrc.contains("title: 'Emergency'"), isTrue);
      expect(screenSrc.contains("title: 'Health support'"), isTrue);
      expect(screenSrc.contains('Advice lines'), isTrue);
      expect(screenSrc.contains('emphasizeEmergency'), isTrue);
      expect(screenSrc.contains('Semantics('), isTrue);
      expect(screenSrc.contains('semanticLabel'), isTrue);
    });
  });
}
