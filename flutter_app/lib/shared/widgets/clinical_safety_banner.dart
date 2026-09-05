import 'package:flutter/material.dart';
import 'package:vitapulse_ai/features/legal/legal_copy.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

/// Context for [ClinicalSafetyBanner] — maps to [LegalCopy] banner strings.
enum ClinicalDisclaimerKind {
  ai,
  medicine,
  prescriptionOcr,
  symptom,
  lab,
  interaction,
  emergency,
}

/// Compact, readable safety banner for clinical / AI patient-facing screens.
///
/// Does not use modals. Does not claim diagnosis, prescribing, or emergency care.
class ClinicalSafetyBanner extends StatelessWidget {
  final ClinicalDisclaimerKind kind;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final bool rounded;

  const ClinicalSafetyBanner({
    super.key,
    required this.kind,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.margin,
    this.rounded = false,
  });

  static String textFor(ClinicalDisclaimerKind kind) {
    switch (kind) {
      case ClinicalDisclaimerKind.ai:
        return LegalCopy.aiBanner;
      case ClinicalDisclaimerKind.medicine:
        return LegalCopy.medicineBanner;
      case ClinicalDisclaimerKind.prescriptionOcr:
        return LegalCopy.prescriptionOcrBanner;
      case ClinicalDisclaimerKind.symptom:
        return LegalCopy.symptomBanner;
      case ClinicalDisclaimerKind.lab:
        return LegalCopy.labBanner;
      case ClinicalDisclaimerKind.interaction:
        return LegalCopy.interactionBanner;
      case ClinicalDisclaimerKind.emergency:
        return LegalCopy.emergencyBanner;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);
    final text = textFor(kind);

    final Color bg;
    final Color fg;
    final Color border;
    final IconData icon;

    switch (kind) {
      case ClinicalDisclaimerKind.emergency:
        bg = hc.emergency.withValues(alpha: 0.08);
        fg = cs.onSurface;
        border = hc.emergency.withValues(alpha: 0.25);
        icon = Icons.info_outline_rounded;
        break;
      case ClinicalDisclaimerKind.symptom:
        bg = hc.vitaWarning.withValues(alpha: 0.08);
        fg = cs.onSurfaceVariant;
        border = hc.vitaWarning.withValues(alpha: 0.4);
        icon = Icons.info_outline;
        break;
      default:
        bg = cs.secondaryContainer.withValues(alpha: 0.55);
        fg = cs.onSecondaryContainer;
        border = cs.outlineVariant.withValues(alpha: 0.35);
        icon = Icons.info_outline;
        break;
    }

    Widget child = Material(
      color: bg,
      borderRadius: rounded ? AppRadius.brMd : null,
      child: Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: rounded ? AppRadius.brMd : null,
          border: Border.all(color: border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: kind == ClinicalDisclaimerKind.emergency
                ? hc.emergency
                : fg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (margin != null) {
      child = Padding(padding: margin!, child: child);
    }
    return Semantics(
      container: true,
      label: text,
      child: child,
    );
  }
}
