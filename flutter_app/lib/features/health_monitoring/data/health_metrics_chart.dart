/// Pure helpers for Health Metrics history and charts (no network).
///
/// Charts plot only stored samples. Missing dates are gaps, not invented
/// readings. Visual curves must not interpolate clinical values.
class RecordedMetricSample {
  final int? id;
  final DateTime recordedAt;
  final double value;
  final double? value2;
  final String? unit;
  final String? notes;
  final int? familyMemberId;
  final String metricType;

  const RecordedMetricSample({
    this.id,
    required this.recordedAt,
    required this.value,
    this.value2,
    this.unit,
    this.notes,
    this.familyMemberId,
    required this.metricType,
  });

  factory RecordedMetricSample.fromJson(Map<String, dynamic> json) {
    final rawAt = json['recorded_at'];
    if (rawAt is! String || rawAt.isEmpty) {
      throw const FormatException('recorded_at is required');
    }
    final at = DateTime.tryParse(rawAt)?.toLocal();
    if (at == null) {
      throw const FormatException('recorded_at is invalid');
    }
    if (json['value'] is! num) {
      throw const FormatException('value is required');
    }
    return RecordedMetricSample(
      id: json['id'] is num ? (json['id'] as num).toInt() : null,
      recordedAt: at,
      value: (json['value'] as num).toDouble(),
      value2: json['value2'] == null ? null : (json['value2'] as num).toDouble(),
      unit: json['unit']?.toString(),
      notes: json['notes']?.toString(),
      familyMemberId: json['family_member_id'] is num
          ? (json['family_member_id'] as num).toInt()
          : null,
      metricType: json['metric_type']?.toString() ?? '',
    );
  }

  String displayValue({bool bloodPressure = false}) {
    if (bloodPressure && value2 != null) {
      return '${value.toStringAsFixed(0)}/${value2!.toStringAsFixed(0)}';
    }
    return value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  }
}

class ChartPoint {
  final double x;
  final double y;
  final DateTime recordedAt;

  const ChartPoint({
    required this.x,
    required this.y,
    required this.recordedAt,
  });
}

class HealthMetricsChartData {
  static const int minTrendPoints = 2;

  static List<RecordedMetricSample> chronological(
    Iterable<RecordedMetricSample> input,
  ) {
    final copy = List<RecordedMetricSample>.from(input);
    copy.sort((a, b) {
      final c = a.recordedAt.compareTo(b.recordedAt);
      if (c != 0) return c;
      return (a.id ?? 0).compareTo(b.id ?? 0);
    });
    return copy;
  }

  static bool hasTrend(Iterable<RecordedMetricSample> input) =>
      chronological(input).length >= minTrendPoints;

  /// Time-scaled x from the earliest sample. Duplicate timestamps get +1ms
  /// so both stored points remain visible. No extra points are inserted.
  static List<ChartPoint> spots(Iterable<RecordedMetricSample> input) {
    final ordered = chronological(input);
    if (ordered.isEmpty) return const [];
    final origin = ordered.first.recordedAt.millisecondsSinceEpoch;
    final points = <ChartPoint>[];
    double lastX = -1;
    for (final sample in ordered) {
      var x = (sample.recordedAt.millisecondsSinceEpoch - origin).toDouble();
      if (x <= lastX) {
        x = lastX + 1;
      }
      lastX = x;
      points.add(ChartPoint(x: x, y: sample.value, recordedAt: sample.recordedAt));
    }
    return points;
  }

  static List<RecordedMetricSample> inRange(
    Iterable<RecordedMetricSample> input,
    DateTime fromInclusive,
  ) {
    return [
      for (final s in input)
        if (!s.recordedAt.isBefore(fromInclusive)) s,
    ];
  }
}

enum HealthMetricsRange {
  days7(7, '7 days'),
  days30(30, '30 days'),
  days90(90, '90 days');

  final int days;
  final String label;
  const HealthMetricsRange(this.days, this.label);
}

class HealthMetricKind {
  final String key;
  final String label;
  final String unit;

  const HealthMetricKind(this.key, this.label, this.unit);

  static const supported = [
    HealthMetricKind('blood_pressure', 'Blood Pressure', 'mmHg'),
    HealthMetricKind('blood_sugar', 'Blood Sugar', 'mg/dL'),
    HealthMetricKind('heart_rate', 'Heart Rate', 'bpm'),
    HealthMetricKind('oxygen_saturation', 'Oxygen Saturation', '%'),
    HealthMetricKind('weight', 'Weight', 'kg'),
  ];

  static HealthMetricKind? byKey(String key) {
    for (final k in supported) {
      if (k.key == key) return k;
    }
    return null;
  }
}
