import 'package:flutter/material.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

/// AI-powered health insights & predictive alerts.
///
/// Calls:
///   GET /insights/alerts            — predictive alerts from recent metrics
///   GET /insights/consultation-advice — when to see a doctor
class HealthInsightsScreen extends StatefulWidget {
  const HealthInsightsScreen({super.key});

  @override
  State<HealthInsightsScreen> createState() => _HealthInsightsScreenState();
}

class _HealthInsightsScreenState extends State<HealthInsightsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  Map<String, dynamic>? _alerts;
  Map<String, dynamic>? _advice;
  bool _alertsLoading = true;
  bool _adviceLoading = true;
  String? _alertsError;
  String? _adviceError;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    _loadAlerts();
    _loadAdvice();
  }

  Future<void> _loadAlerts() async {
    setState(() {
      _alertsLoading = true;
      _alertsError = null;
    });
    try {
      final resp = await ApiClient.get('/insights/alerts');
      if (mounted) {
        setState(() {
          _alerts = resp.data as Map<String, dynamic>?;
          _alertsLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _alertsError = ErrorHandler.getMessage(e);
          _alertsLoading = false;
        });
      }
    }
  }

  Future<void> _loadAdvice() async {
    setState(() {
      _adviceLoading = true;
      _adviceError = null;
    });
    try {
      final resp = await ApiClient.get('/insights/consultation-advice');
      if (mounted) {
        setState(() {
          _advice = resp.data as Map<String, dynamic>?;
          _adviceLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _adviceError = ErrorHandler.getMessage(e);
          _adviceLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Insights'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.warning_amber_rounded, size: 20), text: 'Alerts'),
            Tab(icon: Icon(Icons.local_hospital, size: 20), text: 'Consultation'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadAll,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _AlertsTab(
            loading: _alertsLoading,
            error: _alertsError,
            data: _alerts,
            onRetry: _loadAlerts,
          ),
          _ConsultationTab(
            loading: _adviceLoading,
            error: _adviceError,
            data: _advice,
            onRetry: _loadAdvice,
          ),
        ],
      ),
    );
  }
}

// ─── Alerts Tab ───────────────────────────────────────────────────────────────

class _AlertsTab extends StatelessWidget {
  final bool loading;
  final String? error;
  final Map<String, dynamic>? data;
  final VoidCallback onRetry;

  const _AlertsTab({
    required this.loading,
    required this.error,
    required this.data,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);

    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return _ErrorView(message: error!, onRetry: onRetry);

    final raw = data ?? {};
    final alerts = raw['alerts'] as List<dynamic>? ??
        raw['predictive_alerts'] as List<dynamic>? ??
        [];
    final summary =
        raw['summary'] as String? ?? raw['analysis'] as String? ?? '';

    if (alerts.isEmpty && summary.isEmpty) {
      return _EmptyState(
        icon: Icons.check_circle_outline,
        title: 'All Clear!',
        subtitle:
            'No health alerts detected based on your recent data. Keep tracking your vitals regularly.',
        color: hc.vitaGood,
      );
    }

    return RefreshIndicator(
      onRefresh: () async => onRetry(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (summary.isNotEmpty) ...[
            _SummaryCard(text: summary),
            const SizedBox(height: 16),
          ],
          if (alerts.isNotEmpty) ...[
            Text(
              '${alerts.length} Alert${alerts.length == 1 ? '' : 's'} Found',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            ...alerts.map(
                (a) => _AlertCard(alert: a as Map<String, dynamic>? ?? {})),
          ],
        ],
      ),
    );
  }
}

// ─── Consultation Tab ─────────────────────────────────────────────────────────

class _ConsultationTab extends StatelessWidget {
  final bool loading;
  final String? error;
  final Map<String, dynamic>? data;
  final VoidCallback onRetry;

  const _ConsultationTab({
    required this.loading,
    required this.error,
    required this.data,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);

    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return _ErrorView(message: error!, onRetry: onRetry);

    final raw = data ?? {};
    final advice =
        raw['advice'] as String? ?? raw['recommendation'] as String? ?? '';
    final urgency = raw['urgency'] as String? ?? 'routine';
    final reasons = raw['reasons'] as List<dynamic>? ?? [];
    final actions = raw['next_steps'] as List<dynamic>? ??
        raw['actions'] as List<dynamic>? ??
        [];

    final urgencyColor = switch (urgency.toLowerCase()) {
      'urgent' || 'high' => cs.error,
      'moderate' => hc.vitaWarning,
      _ => hc.vitaGood,
    };

    final urgencyIcon = switch (urgency.toLowerCase()) {
      'urgent' || 'high' => Icons.emergency,
      'moderate' => Icons.warning_amber_rounded,
      _ => Icons.check_circle_outline,
    };

    return RefreshIndicator(
      onRefresh: () async => onRetry(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Urgency badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: urgencyColor.withValues(alpha: 0.10),
              borderRadius: AppRadius.brMd,
              border:
                  Border.all(color: urgencyColor.withValues(alpha: 0.30)),
            ),
            child: Row(
              children: [
                Icon(urgencyIcon, color: urgencyColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        urgency.toUpperCase(),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: urgencyColor,
                          fontSize: 12,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        'Consultation Priority',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (advice.isNotEmpty) _SummaryCard(text: advice),

          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Why You Should Consult',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            ...reasons.map((r) => _BulletItem(
                  text: r.toString(),
                  icon: Icons.info_outline,
                  color: cs.secondary,
                )),
          ],

          if (actions.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Next Steps',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            ...actions.map((a) => _BulletItem(
                  text: a.toString(),
                  icon: Icons.chevron_right,
                  color: hc.vitaGood,
                )),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─── Small reusable widgets ───────────────────────────────────────────────────

class _AlertCard extends StatelessWidget {
  final Map<String, dynamic> alert;
  const _AlertCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);

    final title =
        alert['title'] as String? ?? alert['type'] as String? ?? 'Alert';
    final message =
        alert['message'] as String? ?? alert['details'] as String? ?? '';
    final severity =
        alert['severity'] as String? ?? alert['priority'] as String? ?? 'medium';

    final color = switch (severity.toLowerCase()) {
      'high' || 'critical' => cs.error,
      'medium' => hc.vitaWarning,
      _ => cs.secondary,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.06),
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: AppRadius.brSm,
            ),
            child: Icon(Icons.warning_amber_rounded, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                if (message.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(message,
                      style: TextStyle(
                          fontSize: 13, color: cs.onSurfaceVariant)),
                ],
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: AppRadius.brSm,
            ),
            child: Text(
              severity.toUpperCase(),
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.bold, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String text;
  const _SummaryCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: AppRadius.brMd,
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.06),
            blurRadius: 6,
          ),
        ],
      ),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 14, color: cs.onSurfaceVariant, height: 1.5),
      ),
    );
  }
}

class _BulletItem extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  const _BulletItem(
      {required this.text, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 13, color: cs.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final Color color;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: color),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: cs.error),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
