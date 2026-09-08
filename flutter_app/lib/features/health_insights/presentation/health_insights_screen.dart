import 'package:flutter/material.dart';
import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:vitapulse_ai/features/health_insights/data/health_insights_api.dart';
import 'package:vitapulse_ai/features/legal/legal_copy.dart';
import 'package:vitapulse_ai/shared/widgets/clinical_safety_banner.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

typedef InsightsFetchFn = Future<Map<String, dynamic>> Function();

/// HN-FUTURE-003 — Health Insights grounded in recorded HealthNest data.
class HealthInsightsScreen extends StatefulWidget {
  const HealthInsightsScreen({
    super.key,
    this.fetchSummary,
    this.fetchAdvice,
  });

  final InsightsFetchFn? fetchSummary;
  final InsightsFetchFn? fetchAdvice;

  @override
  State<HealthInsightsScreen> createState() => _HealthInsightsScreenState();
}

class _HealthInsightsScreenState extends State<HealthInsightsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _advice;
  bool _loading = false;
  String? _error;

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
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summaryFn =
          widget.fetchSummary ?? () => HealthInsightsApi.fetchSummary();
      final adviceFn = widget.fetchAdvice ??
          () => HealthInsightsApi.fetchConsultationAdvice();
      final results = await Future.wait([summaryFn(), adviceFn()]);
      if (!mounted) return;
      setState(() {
        _summary = results[0];
        _advice = results[1];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorHandler.getMessage(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('health_insights_screen'),
      appBar: AppBar(
        title: const Text('Health Insights'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(
              key: Key('insights_tab_overview'),
              icon: Icon(Icons.insights_outlined, size: 20),
              text: 'Overview',
            ),
            Tab(
              key: Key('insights_tab_consultation'),
              icon: Icon(Icons.local_hospital, size: 20),
              text: 'Consultation',
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('insights_refresh_button'),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadAll,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _OverviewTab(
            loading: _loading && _summary == null,
            error: _error,
            data: _summary,
            onRetry: _loadAll,
          ),
          _ConsultationTab(
            loading: _loading && _advice == null,
            error: _error,
            data: _advice,
            onRetry: _loadAll,
          ),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  final bool loading;
  final String? error;
  final Map<String, dynamic>? data;
  final VoidCallback onRetry;

  const _OverviewTab({
    required this.loading,
    required this.error,
    required this.data,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);

    if (loading) {
      return const Center(
        key: Key('insights_loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (error != null && data == null) {
      return _ErrorView(
        key: const Key('insights_error'),
        message: error!,
        onRetry: onRetry,
      );
    }

    final raw = data ?? {};
    final insights = (raw['insights'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        [];
    final disclaimer =
        raw['disclaimer']?.toString() ?? LegalCopy.aiBanner;
    final periodDays = raw['period_days'] ?? 30;
    final avail = raw['data_availability'] as Map? ?? {};

    final grounded =
        insights.where((i) => i['status'] == 'grounded').toList();
    final insufficient =
        insights.where((i) => i['status'] == 'insufficient_data').toList();

    return RefreshIndicator(
      onRefresh: () async => onRetry(),
      child: ListView(
        key: const Key('insights_overview_list'),
        padding: const EdgeInsets.all(16),
        children: [
          const ClinicalSafetyBanner(
            key: Key('insights_safety_banner'),
            kind: ClinicalDisclaimerKind.ai,
            rounded: true,
            padding: EdgeInsets.all(12),
          ),
          const SizedBox(height: 12),
          Container(
            key: const Key('insights_purpose_banner'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.08),
              borderRadius: AppRadius.brMd,
              border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
            ),
            child: Text(
              'Insights summarise your recorded HealthNest data for the last '
              '$periodDays days. They are informational only — not a diagnosis.',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Data used: ${avail['metrics_count'] ?? 0} metrics · '
            '${avail['dose_events_count'] ?? 0} dose events · '
            '${avail['lab_record_count'] ?? 0} lab records',
            key: const Key('insights_data_availability'),
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),

          if (grounded.isEmpty && insufficient.isNotEmpty) ...[
            _EmptyState(
              key: const Key('insights_insufficient_state'),
              icon: Icons.hourglass_empty,
              title: 'Not enough data yet',
              subtitle:
                  'Record a few more measurements or medication dose outcomes '
                  'to identify personal trends.',
              color: hc.vitaWarning,
            ),
            const SizedBox(height: 12),
          ],

          if (grounded.isNotEmpty) ...[
            Text(
              'Grounded insights',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            ...grounded.map((i) => _InsightCard(insight: i)),
          ],

          if (insufficient.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Needs more data',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            ...insufficient.map((i) => _InsightCard(insight: i)),
          ],

          const SizedBox(height: 12),
          Text(
            disclaimer,
            key: const Key('insights_disclaimer'),
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

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

    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && data == null) {
      return _ErrorView(message: error!, onRetry: onRetry);
    }

    final raw = data ?? {};
    final advice =
        raw['advice'] as String? ?? raw['recommendation'] as String? ?? '';
    final urgency = raw['urgency'] as String? ?? 'routine';
    final reasons = raw['reasons'] as List<dynamic>? ?? [];
    final actions = raw['next_steps'] as List<dynamic>? ??
        raw['actions'] as List<dynamic>? ??
        [];

    return RefreshIndicator(
      onRefresh: () async => onRetry(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ClinicalSafetyBanner(
            kind: ClinicalDisclaimerKind.ai,
            rounded: true,
            padding: EdgeInsets.all(12),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: hc.vitaGood.withValues(alpha: 0.10),
              borderRadius: AppRadius.brMd,
              border: Border.all(color: hc.vitaGood.withValues(alpha: 0.30)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: cs.primary, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        urgency.toUpperCase(),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: cs.primary,
                          fontSize: 12,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        'Informational consultation context',
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
            const Text('Based on your recorded data',
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
            const Text('Suggested next steps',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            ...actions.map((a) => _BulletItem(
                  text: a.toString(),
                  icon: Icons.chevron_right,
                  color: hc.vitaGood,
                )),
          ],
          const SizedBox(height: 16),
          Text(
            raw['disclaimer']?.toString() ?? LegalCopy.aiBanner,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final Map<String, dynamic> insight;
  const _InsightCard({required this.insight});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);
    final status = insight['status']?.toString() ?? '';
    final insufficient = status == 'insufficient_data';
    final color = insufficient ? hc.vitaWarning : cs.primary;
    final category = insight['category']?.toString() ?? 'insight';
    final source = insight['source']?.toString() ?? '';
    final period = insight['period']?.toString() ?? '';
    final reviewState = insight['review_state']?.toString();

    // Never present unreviewed lab as confirmed.
    final labUnreviewed = category == 'lab' &&
        (reviewState == 'unreviewed_excluded' || insufficient);

    return Container(
      key: Key('insight_card_${insight['id'] ?? category}'),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  insight['title']?.toString() ?? 'Insight',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
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
                  insufficient ? 'NEEDS DATA' : 'GROUNDED',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            insight['summary']?.toString() ?? '',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            [
              if (category.isNotEmpty) 'Category: $category',
              if (source.isNotEmpty) 'Source: $source',
              if (period.isNotEmpty) 'Period: $period',
            ].join(' · '),
            key: const Key('insight_source_period'),
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          if (labUnreviewed) ...[
            const SizedBox(height: 6),
            Text(
              'Unreviewed lab extractions are not shown as confirmed results.',
              style: TextStyle(fontSize: 11, color: hc.vitaWarning),
            ),
          ],
          if (insight['suggestion'] != null) ...[
            const SizedBox(height: 6),
            Text(
              insight['suggestion'].toString(),
              style: TextStyle(fontSize: 12, color: cs.primary),
            ),
          ],
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
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Icon(icon, size: 48, color: color),
          const SizedBox(height: 12),
          Text(title,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView(
      {super.key, required this.message, required this.onRetry});

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
              key: const Key('insights_retry_button'),
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
