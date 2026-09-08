import 'package:flutter/material.dart';
import 'package:vitapulse_ai/features/reminders/data/medication_history_api.dart';
import 'package:vitapulse_ai/features/reminders/data/reminder_api.dart';
import 'package:vitapulse_ai/shared/widgets/empty_state.dart';
import 'package:vitapulse_ai/shared/widgets/shimmer_box.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_spacing.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

/// HN-MEDMGMT-006 — dose adherence history timeline.
///
/// Distinguishes TAKEN / SKIPPED / MISSED. Schedule is not mutated by recording.
class MedicationHistoryScreen extends StatefulWidget {
  final Future<List<Map<String, dynamic>>> Function({
    int? medicationScheduleId,
  })? loadHistory;
  final Future<Map<String, dynamic>> Function({
    int? medicationScheduleId,
  })? loadSummary;
  final Future<List<dynamic>> Function()? loadReminders;
  final Future<Map<String, dynamic>> Function({
    required int medicationScheduleId,
    required String status,
    required DateTime scheduledFor,
  })? recordDose;
  final int? initialScheduleId;

  const MedicationHistoryScreen({
    super.key,
    this.loadHistory,
    this.loadSummary,
    this.loadReminders,
    this.recordDose,
    this.initialScheduleId,
  });

  @override
  State<MedicationHistoryScreen> createState() =>
      _MedicationHistoryScreenState();
}

class _MedicationHistoryScreenState extends State<MedicationHistoryScreen> {
  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _medications = [];
  Map<String, dynamic>? _summary;
  bool _loading = true;
  String _error = '';
  int? _filterScheduleId;
  bool _submitting = false;
  String? _submittingStatus;

  @override
  void initState() {
    super.initState();
    _filterScheduleId = widget.initialScheduleId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  /// Clears in-memory history (e.g. after logout / user switch).
  void clearLocalHistory() {
    if (!mounted) return;
    setState(() {
      _events = [];
      _summary = null;
      _error = '';
      _medications = [];
    });
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final loadHistory = widget.loadHistory ??
          ({int? medicationScheduleId}) => MedicationHistoryApi.listHistory(
                medicationScheduleId: medicationScheduleId,
              );
      final loadSummary = widget.loadSummary ??
          ({int? medicationScheduleId}) => MedicationHistoryApi.summary(
                medicationScheduleId: medicationScheduleId,
              );
      final loadReminders =
          widget.loadReminders ?? () => ReminderApi.getReminders();

      final results = await Future.wait([
        loadHistory(medicationScheduleId: _filterScheduleId),
        loadSummary(medicationScheduleId: _filterScheduleId),
        loadReminders(),
      ]);

      final reminders = (results[2] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (!mounted) return;
      setState(() {
        _events = results[0] as List<Map<String, dynamic>>;
        _summary = results[1] as Map<String, dynamic>;
        _medications = reminders;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load medication history.';
        _loading = false;
        // Do not keep stale events on error after a failed refresh mid-session
        // when we had no successful load — keep prior only if already shown.
      });
    }
  }

  DateTime _defaultScheduledFor(Map<String, dynamic>? med) {
    final now = DateTime.now();
    final times = med?['times'];
    if (times is List && times.isNotEmpty) {
      final raw = times.first.toString();
      final parts = raw.split(':');
      if (parts.length >= 2) {
        final h = int.tryParse(parts[0]) ?? now.hour;
        final m = int.tryParse(parts[1]) ?? 0;
        return DateTime(now.year, now.month, now.day, h, m).toUtc();
      }
    }
    return DateTime.utc(now.year, now.month, now.day, now.hour, now.minute);
  }

  Future<void> _recordStatus(String status) async {
    if (_submitting) return;
    final scheduleId = _filterScheduleId;
    if (scheduleId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a medication to record a dose'),
        ),
      );
      return;
    }
    Map<String, dynamic>? med;
    for (final m in _medications) {
      if (m['id'] == scheduleId) {
        med = m;
        break;
      }
    }
    final record = widget.recordDose ??
        ({
          required int medicationScheduleId,
          required String status,
          required DateTime scheduledFor,
        }) =>
            MedicationHistoryApi.recordDose(
              medicationScheduleId: medicationScheduleId,
              status: status,
              scheduledFor: scheduledFor,
            );

    setState(() {
      _submitting = true;
      _submittingStatus = status;
    });
    try {
      await record(
        medicationScheduleId: scheduleId,
        status: status,
        scheduledFor: _defaultScheduledFor(med),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Recorded as ${_statusLabel(status)}')),
      );
      await _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to record dose')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _submittingStatus = null;
        });
      }
    }
  }

  static String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'taken':
        return 'Taken';
      case 'skipped':
        return 'Skipped';
      case 'missed':
        return 'Missed';
      default:
        return status;
    }
  }

  Color _statusColor(BuildContext context, String status) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);
    switch (status.toLowerCase()) {
      case 'taken':
        return hc.vitaGood;
      case 'skipped':
        return hc.vitaWarning;
      case 'missed':
        return cs.error;
      default:
        return cs.onSurfaceVariant;
    }
  }

  String _fmt(dynamic value) {
    if (value == null) return '—';
    final raw = value.toString();
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      key: const Key('medication_history_screen'),
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Medication History',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            key: const Key('medication_history_refresh'),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _reload,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilter(context),
          if (_filterScheduleId != null) _buildRecordActions(context),
          if (_summary != null && !_loading && _error.isEmpty)
            _buildSummary(context),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildFilter(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = <DropdownMenuItem<int?>>[
      const DropdownMenuItem<int?>(
        value: null,
        child: Text('All medications'),
      ),
      ..._medications.map((m) {
        final id = m['id'];
        final intId = id is int ? id : int.tryParse('$id');
        return DropdownMenuItem<int?>(
          value: intId,
          child: Text(
            m['medicine_name']?.toString() ?? 'Medication',
            overflow: TextOverflow.ellipsis,
          ),
        );
      }),
    ];
    // Keep dropdown valid when initialScheduleId is set before meds load.
    if (_filterScheduleId != null &&
        !items.any((i) => i.value == _filterScheduleId)) {
      items.add(
        DropdownMenuItem<int?>(
          value: _filterScheduleId,
          child: const Text('Selected medication'),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: DropdownButtonFormField<int?>(
        key: const Key('medication_history_filter'),
        value: _filterScheduleId,
        decoration: InputDecoration(
          labelText: 'Medication',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        items: items,
        onChanged: (value) {
          setState(() => _filterScheduleId = value);
          _reload();
        },
        dropdownColor: cs.surface,
      ),
    );
  }

  Widget _buildRecordActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: FilledButton(
              key: const Key('dose_taken_button'),
              onPressed: _submitting ? null : () => _recordStatus('taken'),
              child: _submitting && _submittingStatus == 'taken'
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Taken'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              key: const Key('dose_skipped_button'),
              onPressed: _submitting ? null : () => _recordStatus('skipped'),
              child: _submitting && _submittingStatus == 'skipped'
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Skipped'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              key: const Key('dose_missed_button'),
              onPressed: _submitting ? null : () => _recordStatus('missed'),
              child: _submitting && _submittingStatus == 'missed'
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Missed'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);
    final taken = _summary?['taken'] ?? 0;
    final skipped = _summary?['skipped'] ?? 0;
    final missed = _summary?['missed'] ?? 0;
    final pct = _summary?['adherence_percent'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        key: const Key('medication_adherence_summary'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _sumChip('Taken', '$taken', hc.vitaGood),
            _sumChip('Skipped', '$skipped', hc.vitaWarning),
            _sumChip('Missed', '$missed', cs.error),
            _sumChip(
              'Adherence',
              pct == null ? '—' : '$pct%',
              cs.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sumChip(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return ListView(
        key: const Key('medication_history_loading'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: const [
          ShimmerCard(height: 72),
          ShimmerCard(height: 72),
          ShimmerCard(height: 72),
        ],
      );
    }

    if (_error.isNotEmpty) {
      return Center(
        key: const Key('medication_history_error'),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, color: cs.error, size: 48),
              const SizedBox(height: 12),
              Text(_error, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_events.isEmpty) {
      return const EmptyState(
        key: Key('medication_history_empty'),
        icon: Icons.history_rounded,
        title: 'No dose history yet',
        subtitle:
            'Record Taken, Skipped, or Missed for a medication to build your timeline.',
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        key: const Key('medication_history_timeline'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _events.length,
        itemBuilder: (context, index) {
          final event = _events[index];
          return _DoseEventTile(
            event: event,
            statusLabel: _statusLabel(event['status']?.toString() ?? ''),
            statusColor:
                _statusColor(context, event['status']?.toString() ?? ''),
            scheduledText: _fmt(event['scheduled_for']),
            recordedText: _fmt(event['recorded_at']),
          );
        },
      ),
    );
  }
}

class _DoseEventTile extends StatelessWidget {
  final Map<String, dynamic> event;
  final String statusLabel;
  final Color statusColor;
  final String scheduledText;
  final String recordedText;

  const _DoseEventTile({
    required this.event,
    required this.statusLabel,
    required this.statusColor,
    required this.scheduledText,
    required this.recordedText,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = event['medicine_name']?.toString() ?? 'Medication';
    final dosage = event['dosage']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.x3),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 5, right: 12),
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: cs.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      key: Key('dose_status_${event['id']}_$statusLabel'),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                if (dosage.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    dosage,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  'Scheduled: $scheduledText',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                Text(
                  'Recorded: $recordedText',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
