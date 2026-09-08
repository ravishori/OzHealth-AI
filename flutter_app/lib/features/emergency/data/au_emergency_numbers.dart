import 'package:flutter/material.dart';

/// HN-SOS-004 — Australian emergency / health-support dial numbers.
///
/// Single source of truth for SOS screen tiles. Dial-first only: opening a
/// number launches the platform dialler; HealthNest does not auto-call or
/// claim that emergency services were contacted.
enum AuEmergencyCategory {
  /// Life-threatening / emergency services routes (000, 112, 106 TTY).
  emergency,

  /// Non-000 health information / safety advice lines.
  healthSupport,
}

class AuEmergencyNumber {
  final String label;
  final String description;
  final String subtitle;
  final AuEmergencyCategory category;
  final String semanticLabel;
  final IconData icon;

  const AuEmergencyNumber({
    required this.label,
    required this.description,
    required this.subtitle,
    required this.category,
    required this.semanticLabel,
    required this.icon,
  });

  /// Digits only for `tel:` URIs.
  String get dialDigits => label.replaceAll(' ', '');
}

/// Authoritative set for HN-SOS-004 (project checklist / AU emergency coverage).
const List<AuEmergencyNumber> kAustralianEmergencyNumbers = [
  AuEmergencyNumber(
    label: '000',
    description: 'Emergency Services',
    subtitle: 'Police · Fire · Ambulance',
    category: AuEmergencyCategory.emergency,
    semanticLabel: 'Call emergency services 000',
    icon: Icons.emergency_rounded,
  ),
  AuEmergencyNumber(
    label: '112',
    description: 'Emergency Services',
    subtitle: 'From a mobile',
    category: AuEmergencyCategory.emergency,
    semanticLabel: 'Call emergency number 112',
    icon: Icons.phone_android_rounded,
  ),
  AuEmergencyNumber(
    label: '106',
    description: 'TTY',
    subtitle: 'TTY emergency number',
    category: AuEmergencyCategory.emergency,
    semanticLabel: 'Call TTY emergency number 106',
    icon: Icons.hearing_disabled_rounded,
  ),
  AuEmergencyNumber(
    label: '13 11 26',
    description: 'Poisons Information',
    subtitle: '24/7 toxicology advice',
    category: AuEmergencyCategory.healthSupport,
    semanticLabel: 'Call Poisons Information Centre 13 11 26',
    icon: Icons.science_outlined,
  ),
  AuEmergencyNumber(
    label: '1800 022 222',
    description: 'Health Direct',
    subtitle: 'Free health advice line',
    category: AuEmergencyCategory.healthSupport,
    semanticLabel: 'Call Healthdirect 1800 022 222',
    icon: Icons.local_hospital_outlined,
  ),
];
