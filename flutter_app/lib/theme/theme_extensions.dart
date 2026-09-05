import 'package:flutter/material.dart';
import 'design_tokens/app_radius.dart';
import 'design_tokens/app_spacing.dart';

enum AppIconStyle { filled, outlined }
enum AppAnimationSpeed { normal, reduced, off }

/// Healthcare-specific design tokens attached to every ThemeData as an extension.
/// Access with: HealthcareColors.of(context).emergency
@immutable
class HealthcareColors extends ThemeExtension<HealthcareColors> {
  const HealthcareColors({
    // ── Clinical record type colors ───────────────────────────────────────────
    required this.emergency,
    required this.emergencyContainer,
    required this.onEmergencyContainer,
    required this.prescription,
    required this.prescriptionContainer,
    required this.labReport,
    required this.labReportContainer,
    required this.radiology,
    required this.radiologyContainer,
    required this.discharge,
    required this.dischargeContainer,
    // ── AI / Intelligence ─────────────────────────────────────────────────────
    required this.aiAccent,
    required this.aiContainer,
    required this.onAiContainer,
    // ── Vitals / Monitoring ───────────────────────────────────────────────────
    required this.vitaGood,
    required this.vitaWarning,
    required this.vitaCritical,
    // ── UX Preferences ────────────────────────────────────────────────────────
    required this.cardRadius,
    required this.iconStyle,
    required this.animationMultiplier,
    required this.contentPadding,
    required this.density,
  });

  // Clinical colors
  final Color emergency;
  final Color emergencyContainer;
  final Color onEmergencyContainer;
  final Color prescription;
  final Color prescriptionContainer;
  final Color labReport;
  final Color labReportContainer;
  final Color radiology;
  final Color radiologyContainer;
  final Color discharge;
  final Color dischargeContainer;

  // AI colors
  final Color aiAccent;
  final Color aiContainer;
  final Color onAiContainer;

  // Vital status
  final Color vitaGood;
  final Color vitaWarning;
  final Color vitaCritical;

  // UX preferences
  final BorderRadiusGeometry cardRadius;
  final AppIconStyle iconStyle;
  final double animationMultiplier; // 1.0 normal | 0.5 reduced | 0.0 off
  final EdgeInsetsGeometry contentPadding;
  final AppDisplayDensity density;

  // ── Convenience accessor ───────────────────────────────────────────────────

  static HealthcareColors of(BuildContext context) {
    final ext = Theme.of(context).extension<HealthcareColors>();
    assert(ext != null, 'HealthcareColors ThemeExtension not registered.');
    return ext!;
  }

  bool get useFilledIcons => iconStyle == AppIconStyle.filled;

  Duration animatedDuration(Duration base) {
    if (animationMultiplier == 0) return Duration.zero;
    return Duration(
      microseconds: (base.inMicroseconds * animationMultiplier).round(),
    );
  }

  // ── ThemeExtension API ─────────────────────────────────────────────────────

  @override
  HealthcareColors copyWith({
    Color? emergency,
    Color? emergencyContainer,
    Color? onEmergencyContainer,
    Color? prescription,
    Color? prescriptionContainer,
    Color? labReport,
    Color? labReportContainer,
    Color? radiology,
    Color? radiologyContainer,
    Color? discharge,
    Color? dischargeContainer,
    Color? aiAccent,
    Color? aiContainer,
    Color? onAiContainer,
    Color? vitaGood,
    Color? vitaWarning,
    Color? vitaCritical,
    BorderRadiusGeometry? cardRadius,
    AppIconStyle? iconStyle,
    double? animationMultiplier,
    EdgeInsetsGeometry? contentPadding,
    AppDisplayDensity? density,
  }) =>
      HealthcareColors(
        emergency:            emergency            ?? this.emergency,
        emergencyContainer:   emergencyContainer   ?? this.emergencyContainer,
        onEmergencyContainer: onEmergencyContainer ?? this.onEmergencyContainer,
        prescription:         prescription         ?? this.prescription,
        prescriptionContainer: prescriptionContainer ?? this.prescriptionContainer,
        labReport:            labReport            ?? this.labReport,
        labReportContainer:   labReportContainer   ?? this.labReportContainer,
        radiology:            radiology            ?? this.radiology,
        radiologyContainer:   radiologyContainer   ?? this.radiologyContainer,
        discharge:            discharge            ?? this.discharge,
        dischargeContainer:   dischargeContainer   ?? this.dischargeContainer,
        aiAccent:             aiAccent             ?? this.aiAccent,
        aiContainer:          aiContainer          ?? this.aiContainer,
        onAiContainer:        onAiContainer        ?? this.onAiContainer,
        vitaGood:             vitaGood             ?? this.vitaGood,
        vitaWarning:          vitaWarning          ?? this.vitaWarning,
        vitaCritical:         vitaCritical         ?? this.vitaCritical,
        cardRadius:           cardRadius           ?? this.cardRadius,
        iconStyle:            iconStyle            ?? this.iconStyle,
        animationMultiplier:  animationMultiplier  ?? this.animationMultiplier,
        contentPadding:       contentPadding       ?? this.contentPadding,
        density:              density              ?? this.density,
      );

  @override
  HealthcareColors lerp(ThemeExtension<HealthcareColors>? other, double t) {
    if (other is! HealthcareColors) return this;
    return HealthcareColors(
      emergency:            Color.lerp(emergency,            other.emergency,            t)!,
      emergencyContainer:   Color.lerp(emergencyContainer,   other.emergencyContainer,   t)!,
      onEmergencyContainer: Color.lerp(onEmergencyContainer, other.onEmergencyContainer, t)!,
      prescription:         Color.lerp(prescription,         other.prescription,         t)!,
      prescriptionContainer: Color.lerp(prescriptionContainer, other.prescriptionContainer, t)!,
      labReport:            Color.lerp(labReport,            other.labReport,            t)!,
      labReportContainer:   Color.lerp(labReportContainer,   other.labReportContainer,   t)!,
      radiology:            Color.lerp(radiology,            other.radiology,            t)!,
      radiologyContainer:   Color.lerp(radiologyContainer,   other.radiologyContainer,   t)!,
      discharge:            Color.lerp(discharge,            other.discharge,            t)!,
      dischargeContainer:   Color.lerp(dischargeContainer,   other.dischargeContainer,   t)!,
      aiAccent:             Color.lerp(aiAccent,             other.aiAccent,             t)!,
      aiContainer:          Color.lerp(aiContainer,          other.aiContainer,          t)!,
      onAiContainer:        Color.lerp(onAiContainer,        other.onAiContainer,        t)!,
      vitaGood:             Color.lerp(vitaGood,             other.vitaGood,             t)!,
      vitaWarning:          Color.lerp(vitaWarning,          other.vitaWarning,          t)!,
      vitaCritical:         Color.lerp(vitaCritical,         other.vitaCritical,         t)!,
      cardRadius:    t < 0.5 ? cardRadius           : other.cardRadius,
      iconStyle:     t < 0.5 ? iconStyle            : other.iconStyle,
      animationMultiplier: lerpDouble(animationMultiplier, other.animationMultiplier, t)!,
      contentPadding: t < 0.5 ? contentPadding      : other.contentPadding,
      density:        t < 0.5 ? density             : other.density,
    );
  }
}

double? lerpDouble(double? a, double? b, double t) {
  if (a == null && b == null) return null;
  return (a ?? 0) * (1.0 - t) + (b ?? 0) * t;
}

/// Base healthcare clinical colors — shared semantics across all themes.
const HealthcareColors _baseHealthcareColors = HealthcareColors(
  emergency:            Color(0xFFB71C1C),
  emergencyContainer:   Color(0xFFFFDAD6),
  onEmergencyContainer: Color(0xFF410002),
  prescription:         Color(0xFF1565C0),
  prescriptionContainer: Color(0xFFD3E4FF),
  labReport:            Color(0xFF6A1B9A),
  labReportContainer:   Color(0xFFEAD5FF),
  radiology:            Color(0xFF0277BD),
  radiologyContainer:   Color(0xFFCCEFFF),
  discharge:            Color(0xFF2E7D32),
  dischargeContainer:   Color(0xFFB9F6CA),
  aiAccent:             Color(0xFFF59E0B),
  aiContainer:          Color(0xFFFFF8E1),
  onAiContainer:        Color(0xFF3E2800),
  vitaGood:             Color(0xFF2E7D32),
  vitaWarning:          Color(0xFFF57F17),
  vitaCritical:         Color(0xFFB71C1C),
  cardRadius:           AppRadius.brLg,
  iconStyle:            AppIconStyle.filled,
  animationMultiplier:  1.0,
  contentPadding:       EdgeInsets.all(AppSpacing.x4),
  density:              AppDisplayDensity.comfortable,
);

HealthcareColors healthcareColorsFor({
  required AppCardStyle cardStyle,
  required AppIconStyle iconStyle,
  required AppAnimationSpeed animationSpeed,
  required AppDisplayDensity density,
  Color? emergency,
  Color? prescription,
  Color? labReport,
  Color? radiology,
  Color? discharge,
  Color? aiAccent,
  Color? aiContainer,
  Color? onAiContainer,
  Color? vitaGood,
  Color? vitaWarning,
  Color? vitaCritical,
}) =>
    _baseHealthcareColors.copyWith(
      emergency:   emergency,
      prescription: prescription,
      labReport:   labReport,
      radiology:   radiology,
      discharge:   discharge,
      aiAccent:    aiAccent,
      aiContainer: aiContainer,
      onAiContainer: onAiContainer,
      vitaGood:    vitaGood,
      vitaWarning: vitaWarning,
      vitaCritical: vitaCritical,
      cardRadius:  AppRadius.cardRadius(cardStyle),
      iconStyle:   iconStyle,
      animationMultiplier: switch (animationSpeed) {
        AppAnimationSpeed.normal  => 1.0,
        AppAnimationSpeed.reduced => 0.5,
        AppAnimationSpeed.off     => 0.0,
      },
      contentPadding: AppSpacing.densityPadding(density),
      density:     density,
    );
