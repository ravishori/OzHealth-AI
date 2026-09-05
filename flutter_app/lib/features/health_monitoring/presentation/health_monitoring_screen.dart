import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vitapulse_ai/core/error/error_reporter.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/utils/debug_logger.dart';
import 'package:vitapulse_ai/shared/widgets/status_chip.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

class HealthMonitoringScreen extends StatefulWidget {
  const HealthMonitoringScreen({super.key});

  @override
  State<HealthMonitoringScreen> createState() => _HealthMonitoringScreenState();
}

class _HealthMonitoringScreenState extends State<HealthMonitoringScreen> {
  Map<String, dynamic>? _summary;
  bool        _loading    = true;
  String      _error      = '';
  Object?     _exception;            // actual caught error — used for email report
  StackTrace? _stackTrace;           // kept for email body and remote reporting

  List<_MetricConfig> _buildMetricConfigs(
      HealthcareColors hc, ColorScheme cs) => [
    _MetricConfig(
      key: 'blood_pressure',
      label: 'Blood Pressure',
      unit: 'mmHg',
      icon: Icons.favorite,
      color: hc.vitaCritical,
      normalRange: '120/80',
    ),
    _MetricConfig(
      key: 'blood_sugar',
      label: 'Blood Sugar',
      unit: 'mg/dL',
      icon: Icons.water_drop,
      color: hc.prescription,
      normalRange: '70-100',
    ),
    _MetricConfig(
      key: 'heart_rate',
      label: 'Heart Rate',
      unit: 'bpm',
      icon: Icons.monitor_heart,
      color: hc.vitaWarning,
      normalRange: '60-100',
    ),
    _MetricConfig(
      key: 'oxygen_saturation',
      label: 'Oxygen Saturation',
      unit: '%',
      icon: Icons.air,
      color: cs.secondary,
      normalRange: '95-100',
    ),
    _MetricConfig(
      key: 'weight',
      label: 'Weight',
      unit: 'kg',
      icon: Icons.scale,
      color: hc.discharge,
      normalRange: 'Healthy BMI',
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSummary());
  }

  Future<void> _loadSummary() async {
    setState(() {
      _loading    = true;
      _error      = '';
      _exception  = null;
      _stackTrace = null;
    });
    try {
      final resp = await ApiClient.get('/health-metrics/summary');
      setState(() {
        _summary = Map<String, dynamic>.from(resp.data as Map);
        _loading = false;
      });
    } catch (e, st) {
      // 1. Structured local log — always captured regardless of network state
      DebugLogger.error(
        'HealthMonitor',
        'Failed to load health metrics summary',
        e,
        st,
      );
      // 2. Remote crash report — fire-and-forget, never throws
      ErrorReporter.report(e, st, context: 'health_monitoring:load_summary');
      // 3. Surface friendly message + keep raw error for email report
      setState(() {
        _error      = _friendlyMessage(e);
        _exception  = e;
        _stackTrace = st;
        _loading    = false;
      });
    }
  }

  // Returns a human-readable message without leaking internal error details.
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

  // Opens the default mail client with a pre-filled error report.
  Future<void> _emailErrorReport() async {
    final errorType = _exception?.runtimeType.toString() ?? 'Unknown';
    // Truncate stack to first 10 lines to keep email body readable
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
      'Screen : Health Monitor (load_summary)\n'
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
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open the mail app.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Monitor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadSummary,
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/home/health/log');
          _loadSummary();
        },
        icon: const Icon(Icons.add),
        label: const Text(
          'Log Metric',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final cs      = Theme.of(context).colorScheme;
    final hc      = HealthcareColors.of(context);
    final configs = _buildMetricConfigs(hc, cs);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error.isNotEmpty) {
      return _HealthMonitorErrorState(
        message:     _error,
        exception:   _exception,
        onRetry:     _loadSummary,
        onEmailReport: _emailErrorReport,
        onLogMetric: () => context.push('/home/health/log'),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSummary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          _buildOverviewBanner(configs.length),
          const SizedBox(height: 16),
          ...configs.map((config) => _buildMetricCard(config)),
        ],
      ),
    );
  }

  Widget _buildOverviewBanner(int metricCount) {
    final cs          = Theme.of(context).colorScheme;
    final lastUpdated = _summary?['last_updated']?.toString() ?? '';
    String timeText   = 'Just now';
    if (lastUpdated.isNotEmpty) {
      try {
        final dt   = DateTime.parse(lastUpdated).toLocal();
        final diff = DateTime.now().difference(dt);
        if (diff.inMinutes < 60) {
          timeText = '${diff.inMinutes}m ago';
        } else if (diff.inHours < 24) {
          timeText = '${diff.inHours}h ago';
        } else {
          timeText = '${diff.inDays}d ago';
        }
      } catch (_) {}
    }

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
          const Icon(Icons.health_and_safety, color: Colors.white, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Health Overview',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Last updated: $timeText',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          Column(
            children: [
              Text(
                '$metricCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                ),
              ),
              const Text(
                'Metrics',
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

    final metricData = _summary?[config.key] as Map<String, dynamic>?;
    final rawValue   = metricData?['latest_value'];
    final rawValue2  = metricData?['latest_value2'];
    final String latestValue;
    if (rawValue == null) {
      latestValue = '--';
    } else {
      final double v = (rawValue as num).toDouble();
      if (config.key == 'blood_pressure' && rawValue2 != null) {
        final double v2 = (rawValue2 as num).toDouble();
        latestValue = '${v.toStringAsFixed(0)}/${v2.toStringAsFixed(0)}';
      } else {
        latestValue = v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
      }
    }
    final trend    = metricData?['trend']?.toString() ?? 'stable';
    final readings = metricData?['history'] as List? ?? [];
    final status   = metricData?['status']?.toString() ?? 'unknown';

    final trendIcon = trend == 'up'
        ? Icons.trending_up
        : trend == 'down'
            ? Icons.trending_down
            : Icons.trending_flat;

    final trendColor = _trendColor(config, trend, status);
    final chartData  = _buildChartData(readings, config.key);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
                        'Normal: ${config.normalRange} ${config.unit}',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          latestValue,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                            color: trendColor,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(trendIcon, color: trendColor, size: 18),
                      ],
                    ),
                    Text(
                      config.unit,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            if (chartData.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 60,
                child: _MiniLineChart(spots: chartData, color: config.color),
              ),
              const SizedBox(height: 4),
              Text(
                'Last ${chartData.length} readings',
                style: tt.bodySmall?.copyWith(
                  fontSize: 10,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ] else if (latestValue == '--') ...[
              const SizedBox(height: 8),
              Text(
                'No readings yet. Tap + to log.',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],

            if (status != 'unknown' && status.isNotEmpty) ...[
              const SizedBox(height: 8),
              StatusChip(
                label: status,
                color: _statusColor(status),
                icon: _statusIcon(status),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<FlSpot> _buildChartData(List readings, String key) {
    if (readings.isEmpty) return [];
    final last5 = readings.length > 5
        ? readings.sublist(readings.length - 5)
        : readings;
    List<FlSpot> spots = [];
    for (int i = 0; i < last5.length; i++) {
      final reading = last5[i];
      double? value;
      if (reading is Map) {
        value = (reading['value'] as num?)?.toDouble();
      } else {
        value = double.tryParse(reading.toString());
      }
      if (value != null) spots.add(FlSpot(i.toDouble(), value));
    }
    return spots;
  }

  Color _trendColor(_MetricConfig config, String trend, String status) {
    final hc = HealthcareColors.of(context);
    final cs = Theme.of(context).colorScheme;
    if (status == 'normal') return hc.vitaGood;
    if (status == 'high' || status == 'elevated') return cs.error;
    if (status == 'low') return hc.vitaWarning;
    return config.color;
  }

  Color _statusColor(String status) {
    final hc = HealthcareColors.of(context);
    final cs = Theme.of(context).colorScheme;
    switch (status.toLowerCase()) {
      case 'normal':
        return hc.vitaGood;
      case 'high':
      case 'elevated':
        return cs.error;
      case 'low':
        return hc.vitaWarning;
      case 'critical':
        return hc.vitaCritical;
      default:
        return cs.onSurfaceVariant;
    }
  }

  IconData _statusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'normal':
        return Icons.check_circle_outline;
      case 'high':
      case 'elevated':
        return Icons.arrow_upward;
      case 'low':
        return Icons.arrow_downward;
      case 'critical':
        return Icons.warning_amber_rounded;
      default:
        return Icons.info_outline;
    }
  }
}

// ── Custom error state ────────────────────────────────────────────────────────
// Shown when the health-metrics summary API call fails.
// Logs + remote-reports the error; provides Retry and email-report actions.

class _HealthMonitorErrorState extends StatelessWidget {
  final String      message;
  final Object?     exception;
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

    // Abbreviated error type shown in a small chip so the developer has
    // a quick clue without exposing raw stack traces to end users.
    final errorHint = exception
        ?.runtimeType.toString().replaceFirst('_', '').split('Exception').first;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Illustration ────────────────────────────────────────────────
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color:        cs.errorContainer.withValues(alpha: 0.35),
                    shape:        BoxShape.circle,
                  ),
                ),
                Icon(Icons.monitor_heart_outlined,
                    size: 52, color: cs.error.withValues(alpha: 0.75)),
                Positioned(
                  bottom: 8,
                  right:  8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: cs.error,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.warning_amber_rounded,
                        size: 14, color: Colors.white),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── Heading ─────────────────────────────────────────────────────
            Text(
              'Health Data Unavailable',
              style: tt.titleMedium!.copyWith(
                fontWeight: FontWeight.w800,
                color:      cs.onSurface,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 10),

            // ── Friendly description ─────────────────────────────────────────
            Text(
              message,
              style: tt.bodyMedium!.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),

            // ── Error type chip ──────────────────────────────────────────────
            if (errorHint != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color:        cs.errorContainer.withValues(alpha: 0.45),
                  borderRadius: AppRadius.brFull,
                  border:       Border.all(color: cs.error.withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bug_report_outlined, size: 12, color: cs.error),
                    const SizedBox(width: 4),
                    Text(
                      errorHint,
                      style: tt.labelSmall!.copyWith(
                        color:      cs.error,
                        fontWeight: FontWeight.w600,
                        fontSize:   10,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 28),

            // ── Primary action: Retry ────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onRetry,
                icon:      const Icon(Icons.refresh, size: 18),
                label:     const Text('Try Again'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const RoundedRectangleBorder(
                      borderRadius: AppRadius.brMd),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // ── Secondary action: Email error report ─────────────────────────
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onEmailReport,
                icon:      const Icon(Icons.email_outlined, size: 18),
                label:     const Text('Email Error Report'),
                style: OutlinedButton.styleFrom(
                  padding:        const EdgeInsets.symmetric(vertical: 14),
                  foregroundColor: cs.error,
                  side:            BorderSide(color: cs.error.withValues(alpha: 0.5)),
                  shape: const RoundedRectangleBorder(
                      borderRadius: AppRadius.brMd),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // ── Tertiary action: still log a reading ─────────────────────────
            TextButton.icon(
              onPressed: onLogMetric,
              icon:  Icon(Icons.add_circle_outline, size: 16, color: hc.vitaGood),
              label: Text(
                'Log a Reading Manually',
                style: TextStyle(color: hc.vitaGood),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Data class ────────────────────────────────────────────────────────────────

class _MetricConfig {
  final String   key;
  final String   label;
  final String   unit;
  final IconData icon;
  final Color    color;
  final String   normalRange;

  const _MetricConfig({
    required this.key,
    required this.label,
    required this.unit,
    required this.icon,
    required this.color,
    required this.normalRange,
  });
}

// ── Mini sparkline chart ──────────────────────────────────────────────────────

class _MiniLineChart extends StatelessWidget {
  final List<FlSpot> spots;
  final Color        color;

  const _MiniLineChart({required this.spots, required this.color});

  @override
  Widget build(BuildContext context) {
    if (spots.isEmpty) return const SizedBox.shrink();

    final cs      = Theme.of(context).colorScheme;
    final minY    = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY    = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final padding = (maxY - minY) * 0.2;
    final chartMinY = (minY - padding).clamp(0.0, double.infinity);
    final chartMaxY = maxY + padding;

    return LineChart(
      LineChartData(
        gridData:   const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        minY: chartMinY,
        maxY: chartMaxY == chartMinY ? chartMaxY + 1 : chartMaxY,
        lineBarsData: [
          LineChartBarData(
            spots:              spots,
            isCurved:           true,
            color:              color,
            barWidth:           2.5,
            isStrokeCapRound:   true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) =>
                  FlDotCirclePainter(
                radius:      3,
                color:       color,
                strokeWidth: 1.5,
                strokeColor: cs.surface,
              ),
            ),
            belowBarData: BarAreaData(
              show:  true,
              color: color.withValues(alpha: 0.08),
            ),
          ),
        ],
        lineTouchData: const LineTouchData(enabled: false),
      ),
    );
  }
}
