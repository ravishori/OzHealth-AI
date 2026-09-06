import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:vitapulse_ai/features/family/data/family_api.dart';
import 'package:vitapulse_ai/features/family/data/family_medications.dart';
import 'package:vitapulse_ai/features/reminders/data/reminder_api.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_spacing.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

typedef FamilyListLoader = Future<List<Map<String, dynamic>>> Function();

/// HN-FAMILY-008 — family medications hub backed by existing reminders.
class FamilyMedicationsScreen extends StatefulWidget {
  final FamilyListLoader? loadMembers;
  final FamilyListLoader? loadReminders;

  const FamilyMedicationsScreen({
    super.key,
    this.loadMembers,
    this.loadReminders,
  });

  @override
  State<FamilyMedicationsScreen> createState() =>
      _FamilyMedicationsScreenState();
}

class _FamilyMedicationsScreenState extends State<FamilyMedicationsScreen> {
  bool _loading = true;
  bool _inFlight = false;
  String? _error;
  List<FamilyMedicationGroup> _groups = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<List<Map<String, dynamic>>> _defaultMembers() async {
    final raw = await FamilyApi.getMembers();
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> _defaultReminders() async {
    final raw = await ReminderApi.getReminders();
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _load() async {
    if (_inFlight) return;
    _inFlight = true;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final members = await (widget.loadMembers ?? _defaultMembers)();
      final reminders = await (widget.loadReminders ?? _defaultReminders)();
      if (!mounted) return;
      setState(() {
        _groups = groupFamilyMedications(
          members: members,
          reminders: reminders,
        );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorHandler.getMessage(e);
        _loading = false;
      });
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _openReminder(Map<String, dynamic> reminder) async {
    final changed = await context.push(
      '/home/reminders/edit',
      extra: reminder,
    );
    if (changed == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Family Medications')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(key: Key('family-meds-loading')),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: AppSpacing.screenPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                key: const Key('family-meds-error'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('family-meds-retry'),
                onPressed: _inFlight ? null : _load,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_groups.isEmpty) {
      return Center(
        child: Padding(
          padding: AppSpacing.screenPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'No family members yet',
                key: Key('family-meds-no-members'),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Add a family member, then link a reminder to them.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.push('/home/family'),
                child: const Text('Open family profiles'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: AppSpacing.screenPadding,
        itemCount: _groups.length,
        itemBuilder: (context, i) => _MemberMedicationsCard(
          group: _groups[i],
          onOpenReminder: _openReminder,
        ),
      ),
    );
  }
}

class _MemberMedicationsCard extends StatelessWidget {
  final FamilyMedicationGroup group;
  final Future<void> Function(Map<String, dynamic> reminder) onOpenReminder;

  const _MemberMedicationsCard({
    required this.group,
    required this.onOpenReminder,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              group.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            if (group.relationship.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                group.relationship,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
            ],
            const SizedBox(height: 12),
            if (group.reminders.isEmpty)
              Text(
                'No medications are currently linked to this family member.',
                key: Key('family-meds-empty-${group.name}'),
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              )
            else
              ...group.reminders.map(
                (reminder) => _ReminderRow(
                  reminder: reminder,
                  accent: hc.prescription,
                  onTap: () => onOpenReminder(reminder),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReminderRow extends StatelessWidget {
  final Map<String, dynamic> reminder;
  final Color accent;
  final VoidCallback onTap;

  const _ReminderRow({
    required this.reminder,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = reminder['medicine_name']?.toString() ?? 'Medication';
    final dosage = reminder['dosage']?.toString() ?? '';
    final freq = familyMedicationFrequencyLabel(
      reminder['frequency']?.toString(),
    );
    final times = familyMedicationTimesLabel(reminder['times']);
    final instructions = reminder['instructions']?.toString() ?? '';
    final refill = reminder['refill_date']?.toString() ?? '';
    final active = reminder['is_active'] != false;

    final bits = <String>[
      if (dosage.isNotEmpty) dosage,
      if (freq.isNotEmpty) freq,
      if (times.isNotEmpty) times,
    ];

    return ListTile(
      key: Key('family-meds-reminder-$name'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.medication_outlined, color: accent),
      title: Text(name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (bits.isNotEmpty) Text(bits.join(' · ')),
          if (instructions.isNotEmpty)
            Text(instructions, style: TextStyle(color: cs.onSurfaceVariant)),
          if (refill.isNotEmpty) Text('Refill $refill'),
          if (!active)
            Text('Inactive', style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      ),
      trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
      onTap: onTap,
    );
  }
}
