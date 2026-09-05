import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:vitapulse_ai/features/eprescriptions/data/eprescription_api.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

/// Full-detail view for a validated ePrescription.
///
/// Features:
///   📁  Auto-save to Records
///   ⏰  Refill Reminders (per medicine)
///   ⚠️  Drug Interaction Checker (AI)
///   👨‍👩‍👦  Share with Family
class EPrescriptionResultScreen extends StatefulWidget {
  final int eprescriptionId;

  const EPrescriptionResultScreen({
    super.key,
    required this.eprescriptionId,
  });

  @override
  State<EPrescriptionResultScreen> createState() =>
      _EPrescriptionResultScreenState();
}

class _EPrescriptionResultScreenState
    extends State<EPrescriptionResultScreen> {
  Map<String, dynamic>? _data;
  bool    _loading = true;
  String? _error;

  bool _savingToRecords = false;

  List<Map<String, dynamic>> _reminders = [];
  final bool _remindersLoading = false;

  Map<String, dynamic>? _interactions;
  bool _interactionsLoading = false;
  bool _interactionsExpanded = false;

  List<Map<String, dynamic>> _shares = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        EPrescriptionApi.get(widget.eprescriptionId),
        EPrescriptionApi.getRefillReminders(widget.eprescriptionId),
        EPrescriptionApi.getShares(widget.eprescriptionId),
      ]);
      if (mounted) {
        setState(() {
          _data      = results[0] as Map<String, dynamic>;
          _reminders = results[1] as List<Map<String, dynamic>>;
          _shares    = results[2] as List<Map<String, dynamic>>;
          _loading   = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error   = ErrorHandler.getMessage(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggleSaveToRecords() async {
    if (_savingToRecords) return;
    final saved = _data?['saved_to_records'] as bool? ?? false;
    setState(() => _savingToRecords = true);
    try {
      final result = saved
          ? await EPrescriptionApi.unsaveFromRecords(
              widget.eprescriptionId)
          : await EPrescriptionApi.saveToRecords(
              widget.eprescriptionId);
      if (mounted) {
        setState(() {
          _data!['saved_to_records'] =
              result['saved_to_records'] ?? !saved;
          _savingToRecords = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(saved
              ? 'Removed from medical records.'
              : '✅ Saved to your medical records!'),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _savingToRecords = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ErrorHandler.getMessage(e)),
        ));
      }
    }
  }

  Future<void> _showRefillReminderSheet() async {
    final cs = Theme.of(context).colorScheme;
    final medicines =
        (_data?['medicines'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
    if (medicines.isEmpty) return;

    String? selectedMed = medicines.first['name'] as String?;
    DateTime? selectedDate;
    final noteCtrl = TextEditingController();
    bool submitting = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('⏰  Set Refill Reminder',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  'Choose a medicine and the date you need to refill.',
                  style: TextStyle(
                      color: cs.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 20),
                const Text('Medicine',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: cs.outline),
                    borderRadius: AppRadius.brSm,
                  ),
                  child: DropdownButton<String>(
                    value: selectedMed,
                    isExpanded: true,
                    underline: const SizedBox(),
                    items: medicines.map((m) {
                      final name = m['name'] as String? ?? '';
                      return DropdownMenuItem(
                          value: name, child: Text(name));
                    }).toList(),
                    onChanged: (v) => setS(() => selectedMed = v),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Refill Date',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: selectedDate ??
                          DateTime.now()
                              .add(const Duration(days: 7)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now()
                          .add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setS(() => selectedDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: cs.outline),
                      borderRadius: AppRadius.brSm,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today,
                            size: 18, color: cs.primary),
                        const SizedBox(width: 10),
                        Text(
                          selectedDate != null
                              ? '${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}'
                              : 'Tap to select date',
                          style: TextStyle(
                            fontSize: 14,
                            color: selectedDate != null
                                ? cs.onSurface
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    hintText: 'e.g. "Ask Dr for new prescription"',
                    border: OutlineInputBorder(
                        borderRadius: AppRadius.brSm),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          vertical: 14),
                    ),
                    onPressed: (submitting ||
                            selectedDate == null ||
                            selectedMed == null)
                        ? null
                        : () async {
                            setS(() => submitting = true);
                            final messenger =
                                ScaffoldMessenger.of(context);
                            final nav = Navigator.of(ctx);
                            try {
                              final reminder = await EPrescriptionApi
                                  .addRefillReminder(
                                epId:         widget.eprescriptionId,
                                medicineName: selectedMed!,
                                refillDate:   selectedDate!,
                                note: noteCtrl.text.trim().isEmpty
                                    ? null
                                    : noteCtrl.text.trim(),
                              );
                              if (mounted) {
                                setState(() => _reminders = [
                                      ..._reminders,
                                      reminder
                                    ]);
                                nav.pop();
                              }
                              messenger.showSnackBar(const SnackBar(
                                content: Text('⏰ Refill reminder set!'),
                              ));
                            } catch (e) {
                              setS(() => submitting = false);
                              messenger.showSnackBar(SnackBar(
                                content:
                                    Text(ErrorHandler.getMessage(e)),
                              ));
                            }
                          },
                    child: submitting
                        ? SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.onPrimary,
                            ))
                        : const Text('Set Reminder',
                            style: TextStyle(fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    noteCtrl.dispose();
  }

  Future<void> _deleteReminder(int reminderId) async {
    try {
      await EPrescriptionApi.deleteRefillReminder(
          widget.eprescriptionId, reminderId);
      if (mounted) {
        setState(() =>
            _reminders.removeWhere((r) => r['id'] == reminderId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reminder deleted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ErrorHandler.getMessage(e)),
        ));
      }
    }
  }

  Future<void> _checkInteractions() async {
    if (_interactionsLoading) return;
    setState(() {
      _interactionsLoading = true;
      _interactionsExpanded = false;
    });
    try {
      final result = await EPrescriptionApi.checkInteractions(
          widget.eprescriptionId);
      if (mounted) {
        setState(() {
          _interactions         = result;
          _interactionsLoading  = false;
          _interactionsExpanded = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _interactionsLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ErrorHandler.getMessage(e)),
        ));
      }
    }
  }

  Future<void> _showShareSheet() async {
    final cs = Theme.of(context).colorScheme;
    List<Map<String, dynamic>> familyMembers = [];
    bool fmLoading = true;
    String? fmError;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          if (fmLoading) {
            ApiClient.get('/family/').then((resp) {
              final raw =
                  (resp.data as List<dynamic>? ?? [])
                      .cast<Map<String, dynamic>>();
              setS(() {
                familyMembers = raw;
                fmLoading = false;
              });
            }).catchError((e) {
              setS(() {
                fmError = ErrorHandler.getMessage(e);
                fmLoading = false;
              });
            });
          }

          final sharedIds =
              _shares.map((s) => s['family_member_id'] as int).toSet();

          return Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('👨‍👩‍👦  Share with Family',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  'Select a family member to share this prescription with.',
                  style: TextStyle(
                      color: cs.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 16),
                if (fmLoading)
                  const Center(child: CircularProgressIndicator())
                else if (fmError != null)
                  Text(fmError!, style: TextStyle(color: cs.error))
                else if (familyMembers.isEmpty)
                  Text('No family members added yet.',
                      style: TextStyle(color: cs.onSurfaceVariant))
                else
                  ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxHeight: 320),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: familyMembers.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final fm       = familyMembers[i];
                        final fmId     = fm['id'] as int;
                        final isShared = sharedIds.contains(fmId);
                        final name     = fm['name'] as String? ?? '';
                        final rel =
                            fm['relationship'] as String? ?? '';

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                cs.primary.withValues(alpha: 0.12),
                            child: Text(
                              name.isNotEmpty
                                  ? name[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                  color: cs.primary,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          subtitle:
                              rel.isNotEmpty ? Text(rel) : null,
                          trailing: isShared
                              ? IconButton(
                                  icon: Icon(Icons.person_remove,
                                      color: cs.error),
                                  tooltip: 'Remove access',
                                  onPressed: () async {
                                    final share = _shares.firstWhere(
                                        (s) =>
                                            s['family_member_id'] ==
                                            fmId,
                                        orElse: () => {});
                                    if (share.isEmpty) return;
                                    final messenger =
                                        ScaffoldMessenger.of(context);
                                    try {
                                      await EPrescriptionApi.revokeShare(
                                          widget.eprescriptionId,
                                          share['id'] as int);
                                      if (mounted) {
                                        setState(() => _shares
                                            .removeWhere((s) =>
                                                s['family_member_id'] ==
                                                fmId));
                                        setS(() =>
                                            sharedIds.remove(fmId));
                                      }
                                    } catch (e) {
                                      messenger.showSnackBar(SnackBar(
                                        content: Text(
                                            ErrorHandler.getMessage(e)),
                                      ));
                                    }
                                  },
                                )
                              : IconButton(
                                  icon: Icon(Icons.person_add,
                                      color: cs.primary),
                                  tooltip: 'Share prescription',
                                  onPressed: () async {
                                    try {
                                      final share =
                                          await EPrescriptionApi.share(
                                              widget.eprescriptionId,
                                              fmId);
                                      setState(() => _shares = [
                                            ..._shares,
                                            share
                                          ]);
                                      setS(() => sharedIds.add(fmId));
                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                          content: Text(
                                              'Shared with $name ✅'),
                                        ));
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                          content: Text(
                                              ErrorHandler.getMessage(
                                                  e)),
                                        ));
                                      }
                                    }
                                  },
                                ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ePrescription'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'My ePrescriptions',
            onPressed: () => context.go('/home/eprescriptions'),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: cs.error),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final d         = _data!;
    final medicines = (d['medicines'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final alerts = _buildAlerts(medicines);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeaderCard(data: d),
          const SizedBox(height: 12),

          _AutoSaveCard(
            saved:    d['saved_to_records'] as bool? ?? false,
            loading:  _savingToRecords,
            onToggle: _toggleSaveToRecords,
          ),
          const SizedBox(height: 12),

          if (alerts.isNotEmpty) ...[
            ...alerts,
            const SizedBox(height: 8),
          ],

          Row(
            children: [
              const Text('Medicines',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: AppRadius.brSm,
                ),
                child: Text(
                  '${medicines.length}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: cs.primary),
                ),
              ),
              if (d['tga_enriched'] == true) ...[
                const Spacer(),
                Row(
                  children: [
                    Icon(Icons.verified,
                        size: 14, color: hc.discharge),
                    const SizedBox(width: 4),
                    Text('TGA enriched',
                        style: TextStyle(
                            fontSize: 11, color: hc.discharge)),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),

          ...medicines.map((m) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _MedicineCard(medicine: m),
              )),

          const SizedBox(height: 16),

          if (medicines.length >= 2) ...[
            _InteractionSection(
              medicines:  medicines,
              result:     _interactions,
              loading:    _interactionsLoading,
              expanded:   _interactionsExpanded,
              onCheck:    _checkInteractions,
              onToggle:   () => setState(
                  () => _interactionsExpanded = !_interactionsExpanded),
            ),
            const SizedBox(height: 12),
          ],

          _RefillRemindersSection(
            reminders: _reminders,
            loading:   _remindersLoading,
            onAdd:     _showRefillReminderSheet,
            onDelete:  _deleteReminder,
          ),
          const SizedBox(height: 12),

          _ShareSection(
            shares:  _shares,
            onShare: _showShareSheet,
            onRevoke: (shareId) async {
              try {
                await EPrescriptionApi.revokeShare(
                    widget.eprescriptionId, shareId);
                setState(() => _shares
                    .removeWhere((s) => s['id'] == shareId));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Share removed.')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ErrorHandler.getMessage(e)),
                  ));
                }
              }
            },
          ),
          const SizedBox(height: 20),

          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            icon:  const Icon(Icons.alarm_add),
            label: const Text('Add Medication Reminders',
                style: TextStyle(fontSize: 15)),
            onPressed: () => context.go('/home/reminders/add'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            icon:  const Icon(Icons.list_alt),
            label: const Text('View All ePrescriptions',
                style: TextStyle(fontSize: 15)),
            onPressed: () => context.go('/home/eprescriptions'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  List<Widget> _buildAlerts(List<Map<String, dynamic>> medicines) {
    final hc     = HealthcareColors.of(context);
    final alerts = <Widget>[];
    for (final m in medicines) {
      final schedule = m['schedule']      as String? ?? '';
      final name     = m['name']          as String? ?? 'Unknown';
      final tgaReg   = m['tga_registered'] as bool?;

      if (schedule == 'S8') {
        alerts.add(_AlertBanner(
          icon:    Icons.warning_amber_rounded,
          color:   hc.vitaCritical,
          message: '$name is a controlled substance (Schedule 8). '
              'Strict record-keeping requirements apply.',
        ));
      } else if (schedule == 'S4') {
        alerts.add(_AlertBanner(
          icon:    Icons.info_outline,
          color:   hc.vitaWarning,
          message: '$name is a prescription-only medicine (Schedule 4).',
        ));
      }
      if (tgaReg == false) {
        alerts.add(_AlertBanner(
          icon:    Icons.help_outline,
          color:   hc.labReport,
          message:
              '$name was not found in the TGA Register. Confirm with your pharmacist.',
        ));
      }
    }
    return alerts;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Feature sections
// ═══════════════════════════════════════════════════════════════════════════════

/// ── 📁 Auto-save card ────────────────────────────────────────────────────────
class _AutoSaveCard extends StatelessWidget {
  final bool saved;
  final bool loading;
  final VoidCallback onToggle;

  const _AutoSaveCard({
    required this.saved,
    required this.loading,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final hc    = HealthcareColors.of(context);
    final cs    = Theme.of(context).colorScheme;
    final color = saved ? hc.discharge : hc.radiology;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: AppRadius.brMd,
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            saved ? Icons.folder_copy : Icons.folder_outlined,
            color: color, size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  saved
                      ? 'Saved to Medical Records'
                      : 'Save to Medical Records',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: color),
                ),
                Text(
                  saved
                      ? 'This prescription is in your health records.'
                      : 'Keep a permanent copy in your health records.',
                  style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          loading
              ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: color,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.brSm),
                    backgroundColor: color.withValues(alpha: 0.1),
                  ),
                  onPressed: onToggle,
                  child: Text(saved ? 'Remove' : 'Save',
                      style: const TextStyle(fontSize: 12)),
                ),
        ],
      ),
    );
  }
}

/// ── ⚠️ Drug Interaction Section ─────────────────────────────────────────────
class _InteractionSection extends StatelessWidget {
  final List<Map<String, dynamic>> medicines;
  final Map<String, dynamic>? result;
  final bool loading;
  final bool expanded;
  final VoidCallback onCheck;
  final VoidCallback onToggle;

  const _InteractionSection({
    required this.medicines,
    required this.result,
    required this.loading,
    required this.expanded,
    required this.onCheck,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: AppRadius.brLg,
        boxShadow: [
          BoxShadow(
              color: cs.shadow.withValues(alpha: 0.08),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: result != null
                ? const BorderRadius.vertical(top: Radius.circular(16))
                : AppRadius.brLg,
            onTap: result != null ? onToggle : null,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: hc.vitaCritical.withValues(alpha: 0.1),
                      borderRadius: AppRadius.brSm,
                    ),
                    child: Icon(Icons.biotech,
                        size: 20, color: hc.vitaCritical),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Drug Interaction Check',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        Text('AI-powered safety analysis',
                            style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  if (loading)
                    const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2))
                  else if (result != null)
                    Icon(
                        expanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        color: cs.onSurfaceVariant)
                  else
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: hc.vitaCritical,
                        backgroundColor:
                            hc.vitaCritical.withValues(alpha: 0.08),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        shape: const RoundedRectangleBorder(
                            borderRadius: AppRadius.brSm),
                      ),
                      onPressed: onCheck,
                      child: const Text('Check',
                          style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),
          ),
          if (expanded && result != null) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: _InteractionResultView(result: result!),
            ),
          ],
        ],
      ),
    );
  }
}

class _InteractionResultView extends StatelessWidget {
  final Map<String, dynamic> result;
  const _InteractionResultView({required this.result});

  @override
  Widget build(BuildContext context) {
    final analysis = result['interaction_analysis'];
    final dupes    = result['duplicate_check'];

    String analysisText = '';
    if (analysis is Map) {
      analysisText = analysis['analysis']?.toString() ??
          analysis['result']?.toString() ??
          analysis.toString();
    } else if (analysis is String) {
      analysisText = analysis;
    }

    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (analysisText.isNotEmpty) ...[
          const Text('Interaction Analysis',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: hc.vitaWarning.withValues(alpha: 0.08),
              borderRadius: AppRadius.brSm,
              border: Border.all(
                  color: hc.vitaWarning.withValues(alpha: 0.5)),
            ),
            child: Text(analysisText,
                style: TextStyle(fontSize: 12, color: cs.onSurface)),
          ),
        ],
        if (dupes != null) ...[
          const SizedBox(height: 10),
          const Text('Duplicate Check',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 6),
          Text(
            dupes.toString(),
            style: TextStyle(
                fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

/// ── ⏰ Refill Reminders Section ──────────────────────────────────────────────
class _RefillRemindersSection extends StatelessWidget {
  final List<Map<String, dynamic>> reminders;
  final bool loading;
  final VoidCallback onAdd;
  final void Function(int reminderId) onDelete;

  const _RefillRemindersSection({
    required this.reminders,
    required this.loading,
    required this.onAdd,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: AppRadius.brLg,
        boxShadow: [
          BoxShadow(
              color: cs.shadow.withValues(alpha: 0.08),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: hc.vitaWarning.withValues(alpha: 0.1),
                  borderRadius: AppRadius.brSm,
                ),
                child: Icon(Icons.notification_add,
                    size: 20, color: hc.vitaWarning),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Refill Reminders',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    Text('Get notified when it\'s time to refill',
                        style: TextStyle(
                            fontSize: 11, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: hc.vitaWarning,
                  backgroundColor:
                      hc.vitaWarning.withValues(alpha: 0.08),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  shape: const RoundedRectangleBorder(
                      borderRadius: AppRadius.brSm),
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add', style: TextStyle(fontSize: 12)),
                onPressed: onAdd,
              ),
            ],
          ),
          if (reminders.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...reminders.map((r) => _ReminderChip(
                  reminder: r,
                  onDelete: () => onDelete(r['id'] as int),
                )),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              'No refill reminders set yet.',
              style: TextStyle(
                  fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReminderChip extends StatelessWidget {
  final Map<String, dynamic> reminder;
  final VoidCallback onDelete;

  const _ReminderChip({required this.reminder, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs      = Theme.of(context).colorScheme;
    final hc      = HealthcareColors.of(context);
    final rawDate = reminder['refill_date'] as String?;
    final date    = rawDate != null ? DateTime.tryParse(rawDate) : null;
    final isPast  = date != null && date.isBefore(DateTime.now());

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isPast
            ? cs.error.withValues(alpha: 0.05)
            : hc.vitaWarning.withValues(alpha: 0.08),
        borderRadius: AppRadius.brSm,
        border: Border.all(
          color: isPast
              ? cs.error.withValues(alpha: 0.3)
              : hc.vitaWarning.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isPast ? Icons.alarm_off : Icons.alarm,
            size: 15,
            color: isPast ? cs.error : hc.vitaWarning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reminder['medicine_name'] as String? ?? '',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                if (date != null)
                  Text(
                    '${date.day}/${date.month}/${date.year}${isPast ? '  (overdue)' : ''}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isPast ? cs.error : cs.onSurfaceVariant,
                    ),
                  ),
                if (reminder['note'] != null &&
                    (reminder['note'] as String).isNotEmpty)
                  Text(
                    reminder['note'] as String,
                    style: TextStyle(
                        fontSize: 11, color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onDelete,
            child: Icon(Icons.close,
                size: 16, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// ── 👨‍👩‍👦 Share Section ────────────────────────────────────────────────────────
class _ShareSection extends StatelessWidget {
  final List<Map<String, dynamic>> shares;
  final VoidCallback onShare;
  final void Function(int shareId) onRevoke;

  const _ShareSection({
    required this.shares,
    required this.onShare,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    final cs           = Theme.of(context).colorScheme;
    final hc           = HealthcareColors.of(context);
    final sectionColor = hc.prescription;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: AppRadius.brLg,
        boxShadow: [
          BoxShadow(
              color: cs.shadow.withValues(alpha: 0.08),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: sectionColor.withValues(alpha: 0.1),
                  borderRadius: AppRadius.brSm,
                ),
                child: Icon(Icons.group_add,
                    size: 20, color: sectionColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Shared with Family',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    Text('Let family members view this prescription',
                        style: TextStyle(
                            fontSize: 11, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: sectionColor,
                  backgroundColor:
                      sectionColor.withValues(alpha: 0.08),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  shape: const RoundedRectangleBorder(
                      borderRadius: AppRadius.brSm),
                ),
                icon: const Icon(Icons.share, size: 16),
                label: const Text('Share',
                    style: TextStyle(fontSize: 12)),
                onPressed: onShare,
              ),
            ],
          ),
          if (shares.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: shares
                  .map((s) => _ShareBadge(
                        share:   s,
                        onRevoke: () => onRevoke(s['id'] as int),
                      ))
                  .toList(),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              'Not shared with any family members yet.',
              style: TextStyle(
                  fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _ShareBadge extends StatelessWidget {
  final Map<String, dynamic> share;
  final VoidCallback onRevoke;

  const _ShareBadge({required this.share, required this.onRevoke});

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final hc   = HealthcareColors.of(context);
    final name = share['family_member_name'] as String? ?? 'Family Member';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: hc.prescription.withValues(alpha: 0.08),
        borderRadius: AppRadius.brFull,
        border: Border.all(
            color: hc.prescription.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person, size: 13, color: hc.prescription),
          const SizedBox(width: 4),
          Text(name,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: hc.prescription)),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRevoke,
            child: Icon(Icons.close,
                size: 13, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Header card
// ═══════════════════════════════════════════════════════════════════════════════

class _HeaderCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _HeaderCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs         = Theme.of(context).colorScheme;
    final provColor  = cs.primary;
    final provider   = (data['provider'] as String? ?? 'erx').toUpperCase();
    final status     = data['status']           as String? ?? 'validated';
    final patient    = data['patient_name']     as String? ?? 'Unknown Patient';
    final prescriber = data['prescriber_name']  as String? ?? '';
    final practice   = data['prescriber_practice'] as String? ?? '';
    final provNum    =
        data['prescriber_provider_number'] as String? ?? '';
    final last4    = data['token_last4']       as String?;
    final rawRxDate = data['prescription_date'] as String?;
    final rawExp    = data['expiry_date']       as String?;
    final rxDate    = rawRxDate != null ? DateTime.tryParse(rawRxDate) : null;
    final expDate   = rawExp    != null ? DateTime.tryParse(rawExp)    : null;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: AppRadius.brLg,
        boxShadow: [
          BoxShadow(
              color: cs.shadow.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: provColor.withValues(alpha: 0.1),
                  borderRadius: AppRadius.brFull,
                  border:
                      Border.all(color: provColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_user, size: 14, color: provColor),
                    const SizedBox(width: 5),
                    Text(
                      provider == 'MOCK' ? 'eRx (Demo)' : provider,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: provColor),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              _StatusBadge(status: status),
            ],
          ),
          const SizedBox(height: 14),
          _InfoRow(
              icon: Icons.person, label: 'Patient', value: patient),
          const Divider(height: 16),
          if (prescriber.isNotEmpty)
            _InfoRow(
                icon: Icons.medical_information,
                label: 'Prescriber',
                value: prescriber),
          if (practice.isNotEmpty)
            _InfoRow(
                icon: Icons.local_hospital,
                label: 'Practice',
                value: practice),
          if (provNum.isNotEmpty)
            _InfoRow(
                icon: Icons.badge,
                label: 'Provider #',
                value: provNum),
          if (rxDate != null || expDate != null)
            const Divider(height: 16),
          if (rxDate != null)
            _InfoRow(
                icon: Icons.calendar_today,
                label: 'Prescribed',
                value: _fmtDate(rxDate)),
          if (expDate != null)
            _InfoRow(
              icon: Icons.event_busy,
              label: 'Expires',
              value: _fmtDate(expDate),
              valueColor:
                  expDate.isBefore(DateTime.now()) ? cs.error : null,
            ),
          if (last4 != null) ...[
            const Divider(height: 16),
            _InfoRow(
                icon: Icons.tag,
                label: 'Token',
                value: '****$last4',
                valueFontFamily: 'monospace'),
          ],
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

// ═══════════════════════════════════════════════════════════════════════════════
// Medicine card
// ═══════════════════════════════════════════════════════════════════════════════

class _MedicineCard extends StatefulWidget {
  final Map<String, dynamic> medicine;
  const _MedicineCard({required this.medicine});

  @override
  State<_MedicineCard> createState() => _MedicineCardState();
}

class _MedicineCardState extends State<_MedicineCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs           = Theme.of(context).colorScheme;
    final hc           = HealthcareColors.of(context);
    final m            = widget.medicine;
    final name         = m['name']          as String? ?? 'Unknown';
    final genericName  = m['generic_name']  as String?;
    final dosage       = m['dosage']        as String?;
    final frequency    = m['frequency']     as String?;
    final quantity     = m['quantity']      as String?;
    final repeats      = m['repeats']       as int?;
    final instructions = m['instructions']  as String?;
    final drugClass    = m['drug_class']    as String?;
    final sideEffects  = m['side_effects']  as String?;
    final warnings     = m['warnings']      as String?;
    final schedule     = m['schedule']      as String?;

    final hasTga = drugClass != null ||
        sideEffects != null ||
        warnings != null;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: AppRadius.brLg,
        boxShadow: [
          BoxShadow(
              color: cs.shadow.withValues(alpha: 0.08),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: hasTga
                ? () => setState(() => _expanded = !_expanded)
                : null,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.1),
                          borderRadius: AppRadius.brSm,
                        ),
                        child: Icon(Icons.medication,
                            size: 20, color: cs.primary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                            if (genericName != null &&
                                genericName != name)
                              Text(genericName,
                                  style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 12)),
                          ],
                        ),
                      ),
                      if (schedule != null)
                        _ScheduleBadge(schedule: schedule),
                      if (hasTga)
                        Icon(
                          _expanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: cs.onSurfaceVariant,
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (dosage != null)
                        _Chip(Icons.thermostat, dosage),
                      if (frequency != null)
                        _Chip(Icons.schedule, frequency),
                      if (quantity != null)
                        _Chip(Icons.inventory_2_outlined, quantity),
                      if (repeats != null)
                        _Chip(Icons.repeat,
                            '$repeats repeat${repeats == 1 ? '' : 's'}'),
                    ],
                  ),
                  if (instructions != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: AppRadius.brSm,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline,
                              size: 15,
                              color: cs.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(instructions,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_expanded && hasTga) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.verified_outlined,
                          size: 14, color: hc.discharge),
                      const SizedBox(width: 5),
                      Text('TGA Information',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: hc.discharge)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (drugClass != null)
                    _TgaRow('Drug Class', drugClass),
                  if (sideEffects != null)
                    _TgaRow('Side Effects', sideEffects),
                  if (warnings != null)
                    _TgaRow('Warnings', warnings, color: cs.error),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Small reusable widgets
// ═══════════════════════════════════════════════════════════════════════════════

class _Chip extends StatelessWidget {
  final IconData icon;
  final String   label;
  const _Chip(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.25),
        borderRadius: AppRadius.brSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: cs.primary),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(fontSize: 11, color: cs.primary)),
        ],
      ),
    );
  }
}

class _ScheduleBadge extends StatelessWidget {
  final String schedule;
  const _ScheduleBadge({required this.schedule});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);
    final color = switch (schedule) {
      'S8' => hc.vitaCritical,
      'S4' => hc.vitaWarning,
      'S3' => hc.prescription,
      _    => cs.onSurfaceVariant,
    };
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(schedule,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color)),
    );
  }
}

class _TgaRow extends StatelessWidget {
  final String label, value;
  final Color? color;
  const _TgaRow(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: RichText(
          text: TextSpan(
            style: DefaultTextStyle.of(context)
                .style
                .copyWith(fontSize: 12),
            children: [
              TextSpan(
                text: '$label: ',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              TextSpan(
                text: value,
                style: TextStyle(
                    color: color ??
                        Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String   label, value;
  final Color?   valueColor;
  final String?  valueFontFamily;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.valueFontFamily,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13, color: cs.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: valueColor,
                fontFamily: valueFontFamily,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertBanner extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final String   message;

  const _AlertBanner({
    required this.icon,
    required this.color,
    required this.message,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: AppRadius.brSm,
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message,
                  style: TextStyle(fontSize: 12, color: color)),
            ),
          ],
        ),
      );
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);
    final (color, label) = switch (status) {
      'validated' => (hc.discharge,        'Valid'),
      'dispensed' => (hc.prescription,     'Dispensed'),
      'expired'   => (cs.error,            'Expired'),
      _           => (cs.onSurfaceVariant, status),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppRadius.brMd,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color)),
    );
  }
}
