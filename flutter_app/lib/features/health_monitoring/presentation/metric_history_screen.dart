import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vitapulse_ai/features/health_monitoring/data/health_api.dart';
import 'package:vitapulse_ai/features/health_monitoring/data/health_metrics_chart.dart';
import 'package:vitapulse_ai/features/legal/legal_copy.dart';
import 'package:vitapulse_ai/shared/widgets/clinical_safety_banner.dart';

class MetricHistoryScreen extends StatefulWidget {
  final String metricType;
  final String label;
  final String unit;
  final int initialDays;
  final int? familyMemberId;
  final String subjectLabel;

  const MetricHistoryScreen({
    super.key,
    required this.metricType,
    required this.label,
    required this.unit,
    this.initialDays = 30,
    this.familyMemberId,
    this.subjectLabel = 'Myself',
  });

  @override
  State<MetricHistoryScreen> createState() => _MetricHistoryScreenState();
}

class _MetricHistoryScreenState extends State<MetricHistoryScreen> {
  late HealthMetricsRange _range;
  bool _loading = true;
  String _error = '';
  List<RecordedMetricSample> _samples = const [];

  bool get _isBp => widget.metricType == 'blood_pressure';

  @override
  void initState() {
    super.initState();
    _range = HealthMetricsRange.values.firstWhere(
      (r) => r.days == widget.initialDays,
      orElse: () => HealthMetricsRange.days30,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final rows = await HealthApi.getMetrics(
        metricType: widget.metricType,
        familyMemberId: widget.familyMemberId,
        days: _range.days,
      );
      final samples = <RecordedMetricSample>[];
      for (final row in rows) {
        try {
          if (row is Map<String, dynamic>) {
            samples.add(RecordedMetricSample.fromJson(row));
          } else if (row is Map) {
            samples.add(
              RecordedMetricSample.fromJson(Map<String, dynamic>.from(row)),
            );
          }
        } on FormatException {
          // Skip malformed rows rather than inventing a timestamp/value.
        }
      }
      setState(() {
        _samples = samples;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _error = 'Unable to load your recorded measurements. Please try again.';
        _loading = false;
      });
    }
  }

  Map<String, dynamic> _metricExtra(RecordedMetricSample sample) => {
        'id': sample.id,
        'metric_type': sample.metricType,
        'value': sample.value,
        'value2': sample.value2,
        'notes': sample.notes,
        'recorded_at': sample.recordedAt.toIso8601String(),
        'family_member_id': sample.familyMemberId,
        'unit': sample.unit,
      };

  Future<void> _openEdit(RecordedMetricSample sample) async {
    if (sample.id == null) return;
    await context.push('/home/health/log', extra: {
      'familyMemberId': widget.familyMemberId ?? sample.familyMemberId,
      'metric': _metricExtra(sample),
    });
    if (mounted) await _load();
  }

  Future<void> _confirmDelete(RecordedMetricSample sample) async {
    if (sample.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete reading?'),
        content: const Text(
          'This removes the recorded measurement from your history. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await HealthApi.deleteMetric(sample.id!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reading deleted')),
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to delete reading. Please try again.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.label),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final ordered = HealthMetricsChartData.chronological(_samples);
    final latest = ordered.isEmpty ? null : ordered.last;
    final chartPoints = HealthMetricsChartData.spots(ordered);
    final hasTrend = HealthMetricsChartData.hasTrend(ordered);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          const ClinicalSafetyBanner(
            kind: ClinicalDisclaimerKind.healthMetrics,
            rounded: true,
          ),
          const SizedBox(height: 12),
          Text(
            'Recorded measurements for ${widget.subjectLabel}',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final range in HealthMetricsRange.values)
                ChoiceChip(
                  label: Text(range.label),
                  selected: _range == range,
                  onSelected: (_) {
                    setState(() => _range = range);
                    _load();
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (latest == null)
            _EmptyHistory(label: widget.label)
          else ...[
            Text(
              'Latest reading',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                title: Text(
                  '${latest.displayValue(bloodPressure: _isBp)} ${widget.unit}',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  DateFormat('d MMM yyyy, h:mm a').format(latest.recordedAt),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Trend of your recorded measurements',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (!hasTrend)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Not enough readings for a trend yet. Log at least two '
                    '${widget.label.toLowerCase()} measurements.',
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              )
            else
              SizedBox(
                height: 220,
                child: _HistoryChart(
                  points: chartPoints,
                  unit: widget.unit,
                ),
              ),
            const SizedBox(height: 20),
            Text(
              'Your recent readings',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ...ordered.reversed.map((sample) {
              return Card(
                child: ListTile(
                  title: Text(
                    '${sample.displayValue(bloodPressure: _isBp)} ${widget.unit}',
                  ),
                  subtitle: Text(
                    DateFormat('d MMM yyyy, h:mm a').format(sample.recordedAt),
                  ),
                  trailing: sample.id == null
                      ? (sample.notes == null || sample.notes!.isEmpty
                          ? null
                          : Icon(Icons.notes, color: cs.onSurfaceVariant))
                      : PopupMenuButton<String>(
                          onSelected: (action) {
                            if (action == 'edit') {
                              _openEdit(sample);
                            } else if (action == 'delete') {
                              _confirmDelete(sample);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                        ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  final String label;
  const _EmptyHistory({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.show_chart, size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'No recorded ${label.toLowerCase()} measurements in this period.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              LegalCopy.healthMetricsEmptyHint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryChart extends StatelessWidget {
  final List<ChartPoint> points;
  final String unit;

  const _HistoryChart({required this.points, required this.unit});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spots = [for (final p in points) FlSpot(p.x, p.y)];
    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final pad = ((maxY - minY).abs() * 0.15).clamp(0.5, 20.0);
    final first = points.first.recordedAt;
    final last = points.last.recordedAt;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 16, 8),
        child: Column(
          children: [
            Expanded(
              child: LineChart(
                LineChartData(
                  minY: minY - pad,
                  maxY: maxY == minY ? maxY + pad : maxY + pad,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: ((maxY - minY).abs() / 3).clamp(1, 50),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        getTitlesWidget: (value, meta) => Text(
                          value.toStringAsFixed(0),
                          style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: false,
                      color: cs.primary,
                      barWidth: 2,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(show: false),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touched) => [
                        for (final t in touched)
                          LineTooltipItem(
                            '${t.y.toStringAsFixed(1)} $unit',
                            TextStyle(color: cs.onPrimary, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('d MMM').format(first),
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
                Text(
                  DateFormat('d MMM').format(last),
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
