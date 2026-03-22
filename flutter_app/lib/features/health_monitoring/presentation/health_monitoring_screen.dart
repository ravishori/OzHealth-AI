import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/theme/app_theme.dart';

class HealthMonitoringScreen extends StatefulWidget {
  const HealthMonitoringScreen({super.key});

  @override
  State<HealthMonitoringScreen> createState() => _HealthMonitoringScreenState();
}

class _HealthMonitoringScreenState extends State<HealthMonitoringScreen> {
  Map<String, dynamic>? _summary;
  bool _loading = true;
  String _error = '';

  static const _metricConfigs = [
    _MetricConfig(
      key: 'blood_pressure',
      label: 'Blood Pressure',
      unit: 'mmHg',
      icon: Icons.favorite,
      color: Color(0xFFD32F2F),
      normalRange: '120/80',
    ),
    _MetricConfig(
      key: 'blood_sugar',
      label: 'Blood Sugar',
      unit: 'mg/dL',
      icon: Icons.water_drop,
      color: Color(0xFF1565C0),
      normalRange: '70-100',
    ),
    _MetricConfig(
      key: 'heart_rate',
      label: 'Heart Rate',
      unit: 'bpm',
      icon: Icons.monitor_heart,
      color: Color(0xFFE65100),
      normalRange: '60-100',
    ),
    _MetricConfig(
      key: 'oxygen_saturation',
      label: 'Oxygen Saturation',
      unit: '%',
      icon: Icons.air,
      color: Color(0xFF00838F),
      normalRange: '95-100',
    ),
    _MetricConfig(
      key: 'weight',
      label: 'Weight',
      unit: 'kg',
      icon: Icons.scale,
      color: Color(0xFF558B2F),
      normalRange: 'Healthy BMI',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final resp = await ApiClient.get('/health-metrics/summary');
      setState(() {
        _summary = Map<String, dynamic>.from(resp.data as Map);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load health metrics.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Health Monitor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
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
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Log Metric', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }

    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppTheme.error, size: 56),
              const SizedBox(height: 16),
              Text(_error, style: const TextStyle(color: AppTheme.textSecondary), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: _loadSummary, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: _loadSummary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          _buildOverviewBanner(),
          const SizedBox(height: 16),
          ..._metricConfigs.map((config) => _buildMetricCard(config)),
        ],
      ),
    );
  }

  Widget _buildOverviewBanner() {
    final lastUpdated = _summary?['last_updated']?.toString() ?? '';
    String timeText = 'Just now';
    if (lastUpdated.isNotEmpty) {
      try {
        final dt = DateTime.parse(lastUpdated).toLocal();
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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryDark, AppTheme.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
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
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
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
                '${_metricConfigs.length}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24),
              ),
              const Text('Metrics', style: TextStyle(color: Colors.white70, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(_MetricConfig config) {
    final metricData = _summary?[config.key] as Map<String, dynamic>?;
    final latestValue = metricData?['latest']?.toString() ?? '--';
    final trend = metricData?['trend']?.toString() ?? 'stable';
    final readings = metricData?['readings'] as List? ?? [];
    final status = metricData?['status']?.toString() ?? 'unknown';

    final trendIcon = trend == 'up'
        ? Icons.trending_up
        : trend == 'down'
            ? Icons.trending_down
            : Icons.trending_flat;

    final trendColor = _trendColor(config, trend, status);

    final chartData = _buildChartData(readings, config.key);

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
                    color: config.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
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
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        'Normal: ${config.normalRange} ${config.unit}',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
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
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
            if (chartData.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 60,
                child: _MiniLineChart(
                  spots: chartData,
                  color: config.color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Last ${chartData.length} readings',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
              ),
            ] else if (latestValue == '--') ...[
              const SizedBox(height: 8),
              const Text(
                'No readings yet. Tap + to log.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
            ],

            if (status != 'unknown' && status.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor(status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    color: _statusColor(status),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<FlSpot> _buildChartData(List readings, String key) {
    if (readings.isEmpty) return [];
    final last5 = readings.length > 5 ? readings.sublist(readings.length - 5) : readings;
    List<FlSpot> spots = [];
    for (int i = 0; i < last5.length; i++) {
      final reading = last5[i];
      double? value;
      if (reading is Map) {
        // For BP, use systolic
        if (key == 'blood_pressure') {
          value = double.tryParse(reading['systolic']?.toString() ?? '');
        } else {
          value = double.tryParse(reading['value']?.toString() ?? '');
        }
      } else {
        value = double.tryParse(reading.toString());
      }
      if (value != null) {
        spots.add(FlSpot(i.toDouble(), value));
      }
    }
    return spots;
  }

  Color _trendColor(_MetricConfig config, String trend, String status) {
    if (status == 'normal') return AppTheme.success;
    if (status == 'high' || status == 'elevated') return AppTheme.error;
    if (status == 'low') return AppTheme.accent;
    return config.color;
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'normal':
        return AppTheme.success;
      case 'high':
      case 'elevated':
        return AppTheme.error;
      case 'low':
        return AppTheme.accent;
      case 'critical':
        return const Color(0xFF880E4F);
      default:
        return AppTheme.textSecondary;
    }
  }
}

class _MetricConfig {
  final String key;
  final String label;
  final String unit;
  final IconData icon;
  final Color color;
  final String normalRange;

  const _MetricConfig({
    required this.key,
    required this.label,
    required this.unit,
    required this.icon,
    required this.color,
    required this.normalRange,
  });
}

class _MiniLineChart extends StatelessWidget {
  final List<FlSpot> spots;
  final Color color;

  const _MiniLineChart({required this.spots, required this.color});

  @override
  Widget build(BuildContext context) {
    if (spots.isEmpty) return const SizedBox.shrink();

    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final padding = (maxY - minY) * 0.2;
    final chartMinY = (minY - padding).clamp(0.0, double.infinity);
    final chartMaxY = maxY + padding;

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        minY: chartMinY,
        maxY: chartMaxY == chartMinY ? chartMaxY + 1 : chartMaxY,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                radius: 3,
                color: color,
                strokeWidth: 1.5,
                strokeColor: Colors.white,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: color.withOpacity(0.08),
            ),
          ),
        ],
        lineTouchData: const LineTouchData(enabled: false),
      ),
    );
  }
}
