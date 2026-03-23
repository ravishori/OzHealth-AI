import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/theme/app_theme.dart';

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
        _members = (data as List<dynamic>)
            .cast<Map<String, dynamic>>();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load family members'),
            backgroundColor: AppTheme.error,
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
            child:
                const Text('Remove', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ApiClient.delete('/family/$id');
        setState(() => _members.removeWhere((m) => m['id'] == id));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$name removed'),
              backgroundColor: AppTheme.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to remove member'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
      }
    }
  }

  void _showDetailSheet(Map<String, dynamic> member) {
    final conditions =
        (member['medical_conditions'] as List<dynamic>?)?.cast<String>() ?? [];
    final allergies =
        (member['allergies'] as List<dynamic>?)?.cast<String>() ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                    color: Colors.grey.shade300,
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
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 14),
                        ),
                      ],
                    ),
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
                const Color(0xFF1565C0),
                'No conditions recorded',
              ),
              const SizedBox(height: 14),
              _chipsBlock(
                'Allergies',
                Icons.warning_amber_outlined,
                allergies,
                AppTheme.accent,
                'No allergies recorded',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatarCircle(String name) {
    final initials = name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    return CircleAvatar(
      radius: 26,
      backgroundColor: AppTheme.primary.withOpacity(0.15),
      child: Text(
        initials,
        style: const TextStyle(
            color: AppTheme.primary,
            fontWeight: FontWeight.bold,
            fontSize: 16),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.primary),
        const SizedBox(width: 10),
        Text('$label: ',
            style:
                const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w500, fontSize: 14)),
        ),
      ],
    );
  }

  Widget _chipsBlock(String title, IconData icon, List<String> items,
      Color color, String emptyText) {
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
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13))
        else
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: items
                .map(
                  (item) => Chip(
                    label: Text(item,
                        style: TextStyle(color: color, fontSize: 12)),
                    backgroundColor: color.withOpacity(0.1),
                    side: BorderSide(color: color.withOpacity(0.3)),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Family Members'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final added = await context.push('/home/family/add');
          if (added == true) _loadMembers();
        },
        backgroundColor: AppTheme.primary,
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
                      itemBuilder: (ctx, i) =>
                          _buildMemberTile(_members[i]),
                    ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.family_restroom,
              size: 72, color: AppTheme.primary.withOpacity(0.4)),
          const SizedBox(height: 16),
          const Text('No family members yet',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          const Text(
            'Add your family members to track\ntheir health profiles',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
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
          color: AppTheme.error,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
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
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13)),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (age != null)
                    _pill(Icons.cake_outlined, '$age yrs'),
                  if (age != null && bloodGroup.isNotEmpty)
                    const SizedBox(width: 8),
                  if (bloodGroup.isNotEmpty)
                    _pill(Icons.bloodtype_outlined, bloodGroup),
                ],
              ),
            ],
          ),
          trailing: const Icon(Icons.chevron_right,
              color: AppTheme.textSecondary),
          onTap: () => _showDetailSheet(member),
        ),
      ),
    );
  }

  Widget _pill(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppTheme.primary),
        const SizedBox(width: 3),
        Text(text,
            style: const TextStyle(fontSize: 12, color: AppTheme.primary)),
      ],
    );
  }
}
