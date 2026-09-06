import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vitapulse_ai/core/error/error_reporter.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/utils/debug_logger.dart';
import 'package:vitapulse_ai/features/health_monitoring/data/health_api.dart';
import 'package:vitapulse_ai/features/health_monitoring/data/health_metrics_chart.dart';
import 'package:vitapulse_ai/shared/widgets/clinical_safety_banner.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

class HealthMonitoringScreen extends StatefulWidget {
  const HealthMonitoringScreen({super.key});

  @override
  State<HealthMonitoringScreen> createState() => _HealthMonitoringScreenState();
}

class _HealthMonitoringScreenState extends State<HealthMonitoringScreen> {
  bool _loading = true;
  String _error = '';
  Object? _exception;
  StackTrace? _stackTrace;
  HealthMetricsRange _range = HealthMetricsRange.days30;
  List<RecordedMetricSample> _samples = const [];
  List<Map<String, dynamic>> _familyMembers = const [];
  int? _familyMemberId;
  bool _loadingFamily = true;

  String get _subjectLabel {
    if (_familyMemberId == null) return 'Myself';
    for (final m in _familyMembers) {
      if (m['id'] == _familyMemberId) {
        return m['name']?.toString() ?? 'Family member';
      }
    }
    return 'Family member';
  }

  Map<String, Object?> _logRouteExtra() => {
        'familyMemberId': _familyMemberId,
        'subjectLabel': _subjectLabel,
      };

  List<_MetricConfig> _buildMetricConfigs(
      HealthcareColors hc, ColorScheme cs) =>
      [
        _MetricConfig(
          key: 'blood_pressure',
          label: 'Blood Pressure',
          unit: 'mmHg',
          icon: Icons.favorite,
          color: hc.vitaCritical,
        ),
        _MetricConfig(
          key: 'blood_sugar',
          label: 'Blood Sugar',
          unit: 'mg/dL',
          icon: Icons.water_drop,
          color: hc.prescription,
        ),
        _MetricConfig(
          key: 'heart_rate',
          label: 'Heart Rate',
          unit: 'bpm',
          icon: Icons.monitor_heart,
          color: hc.vitaWarning,
        ),
        _MetricConfig(
          key: 'oxygen_saturation',
          label: 'Oxygen Saturation',
          unit: '%',
          icon: Icons.air,
          color: cs.secondary,
        ),
        _MetricConfig(
          key: 'weight',
          label: 'Weight',
          unit: 'kg',
          icon: Icons.scale,
          color: hc.discharge,
        ),
      ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFamilyMembers();
      _loadMetrics();
    });
  }

  Future<void> _loadFamilyMembers() async {
    try {
      final resp = await ApiClient.get('/family/');
      if (!mounted) return;
      setState(() {
        _familyMembers = List<Map<String, dynamic>>.from(
          resp.data is List ? resp.data : (resp.data['members'] ?? []),
        );
        _loadingFamily = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingFamily = false);
    }
  }

  Future<void> _loadMetrics() async {
    setState(() {
      _loading = true;
      _error = '';
      _exception = null;
      _stackTrace = null;
    });
    try {
      final rows = await HealthApi.getMetrics(
        familyMemberId: _familyMemberId,
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
      if (!mounted) return;
      setState(() {
        _samples = samples;
        _loading = false;
      });
    } catch (e, st) {
      DebugLogger.error(
        'HealthMonitor',
        'Failed to load health metrics',
        e,
        st,
      );
      ErrorReporter.report(e, st, context: 'health_monitoring:load_metrics');
      if (!mounted) return;
      setState(() {
        _error = _friendlyMessage(e);
        _exception = e;
        _stackTrace = st;
        _loading = false;
      });
    }
  }

  String _friendlyMessage(Object e) {
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionError:
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Could not reach the server. Check your internet or Wi-Fi and try again.';
        default:
          break;
      }
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        return 'Your session has expired. Please sign in again.';
      }
      if (status != null && status >= 500) {
        return 'The server encountered a problem. Please try again in a moment.';
      }
    }
    return 'Unable to load your health data. Please try again.';
  }

  Future<void> _emailErrorReport() async {
    final errorType = _exception?.runtimeType.toString() ?? 'Unknown';
    final stackSnippet = _stackTrace
            ?.toString()
            .split('\n')
            .take(10)
            .join('\n') ??
        'No stack trace available';

    final subject = Uri.encodeComponent(
        'HealthNest — Health Monitor Error Report');
    final body = Uri.encodeComponent(
      'HealthNest — Health Monitor Error Report\n'
      '══════════════════════════════════════════\n'
      'Time   : ${DateTime.now().toLocal()}\n'
      'Screen : Health Monitor (load_metrics)\n'
      'Error  : $errorType\n'
      'Message: ${_exception ?? "none"}\n\n'
      'Stack trace (first 10 lines):\n$stackSnippet\n\n'
      '──────────────────────────────────────────\n'
      '[Auto-generated by HealthNest v1.0.0]',
    );

    final uri = Uri.parse(
        'mailto:ravidigitalforge@gmail.com?subject=$subject&body=$body');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the mail app.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  List<RecordedMetricSample> _forType(String key) =>
      [for (final s in _samples) if (s.metricType == key) s];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Monitor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadMetrics,
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/home/health/log', extra: _logRouteExtra());
          _loadMetrics();
        },
        icon: const Icon(Icons.add),
        label: const Text(
          'Add health reading',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);
    final configs = _buildMetricConfigs(hc, cs);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error.isNotEmpty) {
      return _HealthMonitorErrorState(
        message: _error,
        exception: _exception,
        onRetry: _loadMetrics,
        onEmailReport: _emailErrorReport,
        onLogMetric: () =>
            context.push('/home/health/log', extra: _logRouteExtra()),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMetrics,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          const ClinicalSafetyBanner(
            kind: ClinicalDisclaimerKind.healthMetrics,
            rounded: true,
          ),
          const SizedBox(height: 12),
          _buildSubjectRow(),
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
                    _loadMetrics();
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          _buildOverviewBanner(configs),
          const SizedBox(height: 16),
          if (_samples.isEmpty)
            _EmptyMetrics(
              onAdd: () =>
                  context.push('/home/health/log', extra: _logRouteExtra()),
            )
          else
            ...configs.map((config) => _buildMetricCard(config)),
        ],
      ),
    );
  }

  Widget _buildSubjectRow() {
    if (_loadingFamily) {
      return const LinearProgressIndicator(minHeight: 2);
    }
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Showing readings for',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: _familyMemberId,
          isExpanded: true,
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('Myself')),
            ..._familyMembers.map(
              (m) => DropdownMenuItem<int?>(
                value: m['id'] as int?,
                child: Text(m['name']?.toString() ?? 'Unknown'),
              ),
            ),
          ],
          onChanged: (v) {
            setState(() => _familyMemberId = v);
            _loadMetrics();
          },
        ),
      ),
    );
  }

  Widget _buildOverviewBanner(List<_MetricConfig> configs) {
    final cs = Theme.of(context).colorScheme;
    final withData = configs.where((c) => _forType(c.key).isNotEmpty).length;
    final gradientDark = Color.lerp(cs.primary, Colors.black, 0.45)!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [gradientDark, cs.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppRadius.brLg,
      ),
      child: Row(
        children: [
          const Icon(Icons.monitor_heart, color: Colors.white, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recorded measurements',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$_subjectLabel · last ${_range.days} days',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          Column(
            children: [
              Text(
                '$withData',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                ),
              ),
              const Text(
                'with data',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(_MetricConfig config) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final samples = _forType(config.key);
    final ordered = HealthMetricsChartData.chronological(samples);
    final latest = ordered.isEmpty ? null : ordered.last;
    final latestValue = latest == null
        ? '--'
        : latest.displayValue(bloodPressure: config.key == 'blood_pressure');
    final chartPoints = HealthMetricsChartData.spots(ordered);
    final spots = [for (final p in chartPoints) FlSpot(p.x, p.y)];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: AppRadius.brMd,
        onTap: () async {
          await context.push('/home/health/history', extra: {
            'metricType': config.key,
            'label': config.label,
            'unit': config.unit,
            'days': _range.days,
            'familyMemberId': _familyMemberId,
            'subjectLabel': _subjectLabel,
          });
          _loadMetrics();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: config.color.withValues(alpha: 0.1),
                      borderRadius: AppRadius.brSm,
                    ),
                    child: Icon(config.icon, color: config.color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          config.label,
                          style: tt.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          latest == null
                              ? 'No recorded measurement in this period'
                              : 'Latest reading · ${config.unit}',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    latestValue,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
              if (HealthMetricsChartData.hasTrend(ordered)) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 60,
                  child: _MiniLineChart(spots: spots, color: config.color),
                ),
                const SizedBox(height: 4),
                Text(
                  'Trend of your recorded measurements (${ordered.length})',
                  style: tt.bodySmall?.copyWith(
                    fontSize: 10,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ] else if (ordered.length == 1) ...[
                const SizedBox(height: 8),
                Text(
                  'Not enough readings for a trend yet.',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyMetrics extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyMetrics({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.monitor_heart_outlined, size: 48, color: cs.primary),
            const SizedBox(height: 12),
            Text(
              'No recorded measurements yet',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Add a health reading to start your history.',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add health reading'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthMonitorErrorState extends StatelessWidget {
  final String message;
  final Object? exception;
  final VoidCallback onRetry;
  final VoidCallback onEmailReport;
  final VoidCallback onLogMetric;

  const _HealthMonitorErrorState({
    required this.message,
    required this.onRetry,
    required this.onEmailReport,
    required this.onLogMetric,
    this.exception,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hc = HealthcareColors.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.monitor_heart_outlined, size: 52, color: cs.error),
            const SizedBox(height: 24),
            Text(
              'Health Data Unavailable',
              style: tt.titleMedium!.copyWith(
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: tt.bodyMedium!.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Try Again'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onEmailReport,
                icon: const Icon(Icons.email_outlined, size: 18),
                label: const Text('Email Error Report'),
              ),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: onLogMetric,
              icon: Icon(Icons.add_circle_outline, size: 16, color: hc.vitaGood),
              label: Text(
                'Add a health reading',
                style: TextStyle(color: hc.vitaGood),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricConfig {
  final String key;
  final String label;
  final String unit;
  final IconData icon;
  final Color color;

  const _MetricConfig({
    required this.key,
    required this.label,
    required this.unit,
    required this.icon,
    required this.color,
  });
}

class _MiniLineChart extends StatelessWidget {
  final List<FlSpot> spots;
  final Color color;

  const _MiniLineChart({required this.spots, required this.color});

  @override
  Widget build(BuildContext context) {
    if (spots.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final padding = (maxY - minY).abs() * 0.2;
    final chartMinY = minY - (padding == 0 ? 1 : padding);
    final chartMaxY = maxY + (padding == 0 ? 1 : padding);

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        minY: chartMinY,
        maxY: chartMaxY,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: color,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) =>
                  FlDotCirclePainter(
                radius: 3,
                color: color,
                strokeWidth: 1.5,
                strokeColor: cs.surface,
              ),
            ),
            belowBarData: BarAreaData(show: false),
          ),
        ],
        lineTouchData: const LineTouchData(enabled: false),
      ),
    );
  }
}
