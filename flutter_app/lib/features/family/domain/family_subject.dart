library;

/// HN-FAMILY-010 — active family subject (Self vs owned active family member).
///
/// Security: the authenticated user remains the principal. Subject selection is
/// a client UI/data context only and must never imply authorization bypass.
/// Backend owner-scoped checks remain authoritative.

/// Shared ownership filter used by health / Rx selectors and the subject store.
int? ownedFamilyMemberSelection({
  required int? requestedId,
  required List<Map<String, dynamic>> ownedMembers,
}) {
  if (requestedId == null) return null;
  for (final m in ownedMembers) {
    if (!_isActiveMember(m)) continue;
    final raw = m['id'];
    if (raw == requestedId) return requestedId;
    if (raw is num && raw.toInt() == requestedId) return requestedId;
  }
  return null;
}

bool _isActiveMember(Map<String, dynamic> member) {
  final active = member['is_active'];
  if (active == false || active == 0 || active == 'false') return false;
  return true;
}

/// Returns true when [member] is selectable as an active owned subject entry.
bool isSelectableOwnedFamilyMember(Map<String, dynamic> member) {
  if (member['id'] == null) return false;
  return _isActiveMember(member);
}

List<Map<String, dynamic>> filterSelectableFamilyMembers(
  List<Map<String, dynamic>> members,
) {
  return members
      .where((m) => isSelectableOwnedFamilyMember(m))
      .map((m) => Map<String, dynamic>.from(m))
      .toList(growable: false);
}

int? _parseMemberId(dynamic raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString());
}

String displayNameForMember(Map<String, dynamic> member) {
  final name = member['name']?.toString().trim();
  if (name != null && name.isNotEmpty) return name;
  return 'Family member';
}

/// Immutable snapshot of the active subject.
class FamilySubjectSnapshot {
  const FamilySubjectSnapshot({
    required this.familyMemberId,
    required this.displayName,
    required this.ownedActiveMembers,
  });

  /// `null` means Self.
  final int? familyMemberId;
  final String displayName;
  final List<Map<String, dynamic>> ownedActiveMembers;

  bool get isSelf => familyMemberId == null;

  static const self = FamilySubjectSnapshot(
    familyMemberId: null,
    displayName: 'Myself',
    ownedActiveMembers: [],
  );
}

/// Persistence stores only a non-PHI family member id (or clears it).
abstract class FamilySubjectPersistence {
  Future<int?> readFamilyMemberId();
  Future<void> writeFamilyMemberId(int? id);
}

/// In-memory persistence for unit tests.
class MemoryFamilySubjectPersistence implements FamilySubjectPersistence {
  int? _id;

  @override
  Future<int?> readFamilyMemberId() async => _id;

  @override
  Future<void> writeFamilyMemberId(int? id) async {
    _id = id;
  }
}

/// Pure subject controller — no logging of names/ids/PHI.
class FamilySubjectController {
  FamilySubjectController({
    FamilySubjectPersistence? persistence,
    FamilySubjectSnapshot? initial,
  })  : _persistence = persistence ?? MemoryFamilySubjectPersistence(),
        _snapshot = initial ?? FamilySubjectSnapshot.self;

  final FamilySubjectPersistence _persistence;
  FamilySubjectSnapshot _snapshot;
  final List<void Function()> _listeners = [];

  FamilySubjectSnapshot get snapshot => _snapshot;

  int? get familyMemberId => _snapshot.familyMemberId;

  String get displayName => _snapshot.displayName;

  List<Map<String, dynamic>> get ownedActiveMembers =>
      _snapshot.ownedActiveMembers;

  bool get isSelf => _snapshot.isSelf;

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _emit(FamilySubjectSnapshot next) {
    _snapshot = next;
    for (final l in List<void Function()>.from(_listeners)) {
      l();
    }
  }

  Future<void> _persist(int? id) async {
    try {
      await _persistence.writeFamilyMemberId(id);
    } catch (_) {
      // Persistence is best-effort; in-memory subject remains authoritative.
    }
  }

  Future<int?> _readPersisted() async {
    try {
      return await _persistence.readFamilyMemberId();
    } catch (_) {
      return null;
    }
  }

  /// Replace the owned-active roster and re-validate the current selection.
  Future<void> setOwnedActiveMembers(
    List<Map<String, dynamic>> members,
  ) async {
    final selectable = filterSelectableFamilyMembers(members);
    final kept = ownedFamilyMemberSelection(
      requestedId: _snapshot.familyMemberId,
      ownedMembers: selectable,
    );
    final name = kept == null
        ? 'Myself'
        : displayNameForMember(
            selectable.firstWhere(
              (m) => _parseMemberId(m['id']) == kept,
            ),
          );
    _emit(
      FamilySubjectSnapshot(
        familyMemberId: kept,
        displayName: name,
        ownedActiveMembers: selectable,
      ),
    );
    await _persist(kept);
  }

  Future<void> selectSelf() async {
    _emit(
      FamilySubjectSnapshot(
        familyMemberId: null,
        displayName: 'Myself',
        ownedActiveMembers: _snapshot.ownedActiveMembers,
      ),
    );
    await _persist(null);
  }

  /// Returns true when selection applied; false when rejected (unowned/inactive).
  Future<bool> selectFamilyMember(int id) async {
    final kept = ownedFamilyMemberSelection(
      requestedId: id,
      ownedMembers: _snapshot.ownedActiveMembers,
    );
    if (kept == null) return false;
    final member = _snapshot.ownedActiveMembers.firstWhere(
      (m) => _parseMemberId(m['id']) == kept,
    );
    _emit(
      FamilySubjectSnapshot(
        familyMemberId: kept,
        displayName: displayNameForMember(member),
        ownedActiveMembers: _snapshot.ownedActiveMembers,
      ),
    );
    await _persist(kept);
    return true;
  }

  /// Restore persisted id against [members]; invalid ids fall back to Self.
  Future<void> restore({
    required List<Map<String, dynamic>> members,
  }) async {
    final selectable = filterSelectableFamilyMembers(members);
    final stored = await _readPersisted();
    final kept = ownedFamilyMemberSelection(
      requestedId: stored,
      ownedMembers: selectable,
    );
    final name = kept == null
        ? 'Myself'
        : displayNameForMember(
            selectable.firstWhere(
              (m) => _parseMemberId(m['id']) == kept,
            ),
          );
    _emit(
      FamilySubjectSnapshot(
        familyMemberId: kept,
        displayName: name,
        ownedActiveMembers: selectable,
      ),
    );
    if (stored != kept) {
      await _persist(kept);
    }
  }

  /// Logout / session end — Self default, clear persistence and roster.
  Future<void> clear() async {
    await _persist(null);
    _emit(FamilySubjectSnapshot.self);
  }
}
