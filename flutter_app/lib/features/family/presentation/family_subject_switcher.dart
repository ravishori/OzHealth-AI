import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitapulse_ai/features/family/data/family_api.dart';
import 'package:vitapulse_ai/features/family/domain/family_subject.dart';
import 'package:vitapulse_ai/features/family/providers/family_subject_provider.dart';

/// Compact Self / family member switcher for the drawer and feature headers.
class FamilySubjectSwitcher extends ConsumerStatefulWidget {
  const FamilySubjectSwitcher({
    super.key,
    this.compact = false,
    this.onChanged,
    this.loadMembers,
    this.lightOnDark = false,
  });

  final bool compact;
  final VoidCallback? onChanged;
  final Future<List<Map<String, dynamic>>> Function()? loadMembers;

  /// When true, styles for a dark/primary drawer header.
  final bool lightOnDark;

  @override
  ConsumerState<FamilySubjectSwitcher> createState() =>
      _FamilySubjectSwitcherState();
}

class _FamilySubjectSwitcherState extends ConsumerState<FamilySubjectSwitcher> {
  bool _loading = true;
  String? _loadError;
  FamilySubjectController? _controller;

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ref.read(familySubjectProvider);
    if (!identical(_controller, next)) {
      _controller?.removeListener(_onControllerChanged);
      _controller = next;
      _controller!.addListener(_onControllerChanged);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshMembers());
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _defaultLoad() async {
    final raw = await FamilyApi.getMembers();
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _refreshMembers() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final members = await (widget.loadMembers ?? _defaultLoad)();
      final controller = ref.read(familySubjectProvider);
      await controller.restore(members: members);
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Could not load family list';
      });
    }
  }

  Future<void> _onSelect(int? id) async {
    final controller = ref.read(familySubjectProvider);
    if (id == null) {
      await controller.selectSelf();
    } else {
      final ok = await controller.selectFamilyMember(id);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('That family profile is not available.'),
          ),
        );
      }
    }
    widget.onChanged?.call();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(familySubjectProvider);
    final snap = controller.snapshot;
    final onDark = widget.lightOnDark;
    final labelColor = onDark ? Colors.white70 : null;
    final valueColor = onDark ? Colors.white : null;

    if (_loading) {
      return const LinearProgressIndicator(
        key: Key('family-subject-loading'),
        minHeight: 2,
      );
    }
    if (_loadError != null) {
      return Text(
        _loadError!,
        key: const Key('family-subject-error'),
        style: TextStyle(color: labelColor, fontSize: 12),
      );
    }

    final members = snap.ownedActiveMembers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.compact ? 'Viewing as' : 'Active profile',
          key: const Key('family-subject-label'),
          style: TextStyle(
            color: labelColor,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<int?>(
          key: ValueKey('family-subject-${snap.familyMemberId}'),
          initialValue: snap.familyMemberId,
          isExpanded: true,
          dropdownColor: onDark ? Colors.white : null,
          decoration: InputDecoration(
            isDense: true,
            filled: onDark,
            fillColor: onDark ? Colors.white.withValues(alpha: 0.12) : null,
            border: const OutlineInputBorder(),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          style: TextStyle(color: valueColor, fontSize: 14),
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('Myself'),
            ),
            ...members.map((m) {
              final id = m['id'];
              final int? parsed =
                  id is int ? id : (id is num ? id.toInt() : int.tryParse('$id'));
              return DropdownMenuItem<int?>(
                value: parsed,
                child: Text(displayNameForMember(m)),
              );
            }),
          ],
          onChanged: _onSelect,
        ),
        if (members.isEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'No family members yet — add someone under Family.',
            key: const Key('family-subject-empty'),
            style: TextStyle(color: labelColor, fontSize: 11),
          ),
        ],
      ],
    );
  }
}
