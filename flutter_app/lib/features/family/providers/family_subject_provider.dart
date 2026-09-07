import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:vitapulse_ai/core/utils/auth_storage.dart';
import 'package:vitapulse_ai/features/family/domain/family_subject.dart';

/// Bridges [AuthStorage.clearAll] / logout to the in-memory subject controller.
class FamilySubjectBridge {
  static FamilySubjectController? _controller;

  static void attach(FamilySubjectController controller) {
    _controller = controller;
  }

  static void detach(FamilySubjectController controller) {
    if (identical(_controller, controller)) {
      _controller = null;
    }
  }

  /// Clears the active controller after credentials are wiped.
  static Future<void> onSessionCleared() async {
    final c = _controller;
    if (c != null) {
      await c.clear();
    }
  }

  /// Test/helper access — prefer [familySubjectProvider] in widgets.
  static FamilySubjectController? get debugController => _controller;
}

/// Persists only the numeric family member id in the existing app preferences
/// box (non-PHI). Avoids flutter_secure_storage plugin hangs in unit tests.
class HiveFamilySubjectPersistence implements FamilySubjectPersistence {
  static const _key = 'active_family_member_id';

  Box? _boxOrNull() {
    try {
      if (!Hive.isBoxOpen('app_preferences')) return null;
      return Hive.box('app_preferences');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int?> readFamilyMemberId() async {
    final box = _boxOrNull();
    if (box == null) return null;
    final raw = box.get(_key);
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString());
  }

  @override
  Future<void> writeFamilyMemberId(int? id) async {
    final box = _boxOrNull();
    if (box == null) return;
    if (id == null) {
      await box.delete(_key);
    } else {
      await box.put(_key, id);
    }
  }
}

final familySubjectProvider = Provider<FamilySubjectController>((ref) {
  final controller = FamilySubjectController(
    persistence: HiveFamilySubjectPersistence(),
  );
  FamilySubjectBridge.attach(controller);
  AuthStorage.familySubjectSessionClear = FamilySubjectBridge.onSessionCleared;
  ref.onDispose(() {
    FamilySubjectBridge.detach(controller);
    if (identical(
      AuthStorage.familySubjectSessionClear,
      FamilySubjectBridge.onSessionCleared,
    )) {
      AuthStorage.familySubjectSessionClear = null;
    }
  });
  return controller;
});
