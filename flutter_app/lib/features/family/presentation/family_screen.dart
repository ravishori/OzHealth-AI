import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _members = [];

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() => _loading = true);
    try {
      final resp = await ApiClient.get('/family/');
      final data = resp.data;
      setState(() {
        _members = (data as List<dynamic>).cast<Map<String, dynamic>>();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to load family members'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _deleteMember(int id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove $name from your family?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Remove',
                style: TextStyle(
                    color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ApiClient.delete('/family/$id');
        setState(() => _members.removeWhere((m) => m['id'] == id));
        if (mounted) {
          final hc = HealthcareColors.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$name removed'),
              backgroundColor: hc.vitaGood,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Failed to remove member'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  void _showDetailSheet(Map<String, dynamic> member) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);
    final conditions =
        (member['medical_conditions'] as List<dynamic>?)?.cast<String>() ?? [];
    final allergies =
        (member['allergies'] as List<dynamic>?)?.cast<String>() ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.bottomSheet,
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.85,
        expand: false,
        builder: (ctx, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _avatarCircle(member['name'] as String? ?? '?'),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member['name'] as String? ?? '',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          member['relationship'] as String? ?? '',
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit family member',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final id = member['id'] as int?;
                      if (id == null) return;
                      final updated = await context.push<bool>(
                        '/home/family/edit/$id',
                        extra: member,
                      );
                      if (updated == true && mounted) {
                        await _loadMembers();
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              _detailRow(Icons.cake_outlined, 'Age',
                  member['age'] != null ? '${member['age']} years' : 'N/A'),
              const SizedBox(height: 8),
              _detailRow(Icons.person_outline, 'Gender',
                  (member['gender'] as String?) ?? 'N/A'),
              const SizedBox(height: 8),
              _detailRow(Icons.bloodtype_outlined, 'Blood Group',
                  (member['blood_group'] as String?) ?? 'N/A'),
              const SizedBox(height: 16),
              _chipsBlock(
                'Medical Conditions',
                Icons.local_hospital_outlined,
                conditions,
                hc.prescription,
                'No conditions recorded',
              ),
              const SizedBox(height: 14),
              _chipsBlock(
                'Allergies',
                Icons.warning_amber_outlined,
                allergies,
                cs.secondary,
                'No allergies recorded',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatarCircle(String name) {
    final cs = Theme.of(context).colorScheme;
    final initials = name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    return CircleAvatar(
      radius: 26,
      backgroundColor: cs.primary.withValues(alpha: 0.15),
      child: Text(
        initials,
        style: TextStyle(
            color: cs.primary, fontWeight: FontWeight.bold, fontSize: 16),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 10),
        Text('$label: ',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
        Expanded(
          child: Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        ),
      ],
    );
  }

  Widget _chipsBlock(String title, IconData icon, List<String> items,
      Color color, String emptyText) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14)),
          ],
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Text(emptyText,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13))
        else
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: items
                .map(
                  (item) => Chip(
                    label: Text(item,
                        style: TextStyle(color: color, fontSize: 12)),
                    backgroundColor: color.withValues(alpha: 0.1),
                    side: BorderSide(color: color.withValues(alpha: 0.3)),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Family Members'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final added = await context.push('/home/family/add');
          if (added == true) _loadMembers();
        },
        backgroundColor: cs.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadMembers,
              child: _members.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                      itemCount: _members.length,
                      itemBuilder: (ctx, i) => _buildMemberTile(_members[i]),
                    ),
            ),
    );
  }

  Widget _buildEmptyState() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.family_restroom,
              size: 72, color: cs.primary.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text('No family members yet',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text(
            'Add your family members to track\ntheir health profiles',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              final added = await context.push('/home/family/add');
              if (added == true) _loadMembers();
            },
            icon: const Icon(Icons.add),
            label: const Text('Add Family Member'),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberTile(Map<String, dynamic> member) {
    final cs = Theme.of(context).colorScheme;
    final id = member['id'] as int;
    final name = member['name'] as String? ?? 'Unknown';
    final relationship = member['relationship'] as String? ?? '';
    final age = member['age'];
    final bloodGroup = member['blood_group'] as String? ?? '';

    return Dismissible(
      key: ValueKey(id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: cs.error,
          borderRadius: AppRadius.brMd,
        ),
        child:
            const Icon(Icons.delete_outline, color: Colors.white, size: 28),
      ),
      confirmDismiss: (_) async {
        await _deleteMember(id, name);
        return false; // state is managed manually
      },
      child: Card(
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: _avatarCircle(name),
          title: Text(name,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 15)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(relationship,
                  style:
                      TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (age != null) _pill(Icons.cake_outlined, '$age yrs'),
                  if (age != null && bloodGroup.isNotEmpty)
                    const SizedBox(width: 8),
                  if (bloodGroup.isNotEmpty)
                    _pill(Icons.bloodtype_outlined, bloodGroup),
                ],
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Edit family member',
                icon: Icon(Icons.edit_outlined, color: cs.primary),
                onPressed: () async {
                  final updated = await context.push<bool>(
                    '/home/family/edit/$id',
                    extra: member,
                  );
                  if (updated == true && mounted) {
                    await _loadMembers();
                  }
                },
              ),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
          onTap: () => _showDetailSheet(member),
        ),
      ),
    );
  }

  Widget _pill(IconData icon, String text) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: cs.primary),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 12, color: cs.primary)),
      ],
    );
  }
}
