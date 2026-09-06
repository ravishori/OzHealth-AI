/// HN-FAMILY-008 — group owner-scoped family members with owner-scoped reminders.
///
/// Presentation only. Authorization remains GET /family/ + GET /reminders/.
/// Personal reminders (`family_member_id` null) are excluded from the hub.
class FamilyMedicationGroup {
  final String name;
  final String relationship;
  final List<Map<String, dynamic>> reminders;

  const FamilyMedicationGroup({
    required this.name,
    required this.relationship,
    required this.reminders,
  });
}

List<FamilyMedicationGroup> groupFamilyMedications({
  required List<Map<String, dynamic>> members,
  required List<Map<String, dynamic>> reminders,
}) {
  final groups = <FamilyMedicationGroup>[];
  for (final member in members) {
    final rawId = member['id'];
    final memberId = rawId is int ? rawId : int.tryParse('$rawId');
    if (memberId == null) continue;
    final meds = <Map<String, dynamic>>[];
    for (final reminder in reminders) {
      final rawFm = reminder['family_member_id'];
      final fmId = rawFm is int ? rawFm : int.tryParse('$rawFm');
      if (fmId == memberId) meds.add(reminder);
    }
    groups.add(
      FamilyMedicationGroup(
        name: (member['name'] as String?)?.trim().isNotEmpty == true
            ? member['name'] as String
            : 'Family member',
        relationship: (member['relationship'] as String?) ?? '',
        reminders: meds,
      ),
    );
  }
  return groups;
}

String familyMedicationFrequencyLabel(String? raw) {
  switch ((raw ?? '').toLowerCase().replaceAll(' ', '_')) {
    case 'daily':
      return 'Daily';
    case 'twice_daily':
      return 'Twice Daily';
    case 'three_times_daily':
      return 'Three Times Daily';
    case 'four_times_daily':
      return 'Four Times Daily';
    case 'weekly':
      return 'Weekly';
    case 'fortnightly':
      return 'Fortnightly';
    case 'monthly':
      return 'Monthly';
    case 'as_needed':
      return 'As Needed';
    default:
      return raw ?? '';
  }
}

String familyMedicationTimesLabel(dynamic times) {
  if (times is List && times.isNotEmpty) {
    return times.map((e) => e.toString()).join(' · ');
  }
  return '';
}
