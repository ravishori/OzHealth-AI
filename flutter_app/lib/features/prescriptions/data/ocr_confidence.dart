/// HN-OCR-003 — canonical OCR confidence contract (0.0 .. 1.0).
///
/// Backend API returns unit-interval confidence. If a legacy 0..100 value
/// appears, convert exactly once at this boundary — never compare 0..100
/// against [ocrReviewThreshold] without conversion.
class OcrConfidence {
  OcrConfidence._();

  /// Product threshold: strictly below → needs review. Equal-to is OK.
  static const double ocrReviewThreshold = 0.60;

  /// Normalize to 0.0..1.0. Returns null for missing/invalid (fail closed).
  static double? normalize(dynamic raw) {
    if (raw == null) return null;
    if (raw is! num) return null;
    var value = raw.toDouble();
    if (value.isNaN || value < 0) return null;
    if (value > 1.0) {
      value = value / 100.0;
    }
    if (value > 1.0) return null;
    return value;
  }

  static bool isLowConfidence(double? confidence) {
    if (confidence == null) return true;
    return confidence < ocrReviewThreshold;
  }

  /// User-facing percentage string, e.g. "95%". Null if unknown.
  static String? formatPercent(double? unitConfidence) {
    if (unitConfidence == null) return null;
    final pct = (unitConfidence * 100).round();
    return '$pct%';
  }
}
