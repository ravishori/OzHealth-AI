import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitapulse_ai/features/family/data/family_api.dart';

class FamilyState {
  final List<dynamic> members;
  final bool isLoading;
  final String? error;

  const FamilyState({
    this.members = const [],
    this.isLoading = false,
    this.error,
  });

  FamilyState copyWith({
    List<dynamic>? members,
    bool? isLoading,
    String? error,
  }) =>
      FamilyState(
        members: members ?? this.members,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class FamilyNotifier extends StateNotifier<FamilyState> {
  FamilyNotifier() : super(const FamilyState());

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await FamilyApi.getMembers();
      state = state.copyWith(members: data, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: ErrorHandler.getMessage(e));
    }
  }

  Future<bool> add(Map<String, dynamic> data) async {
    try {
      final member = await FamilyApi.addMember(data);
      state = state.copyWith(members: [...state.members, member]);
      return true;
    } catch (e) {
      state = state.copyWith(error: ErrorHandler.getMessage(e));
      return false;
    }
  }

  Future<bool> update(int id, Map<String, dynamic> data) async {
    try {
      final updated = await FamilyApi.updateMember(id, data);
      state = state.copyWith(
        members: state.members
            .map((m) => (m['id'] == id) ? updated : m)
            .toList(),
      );
      return true;
    } catch (e) {
      state = state.copyWith(error: ErrorHandler.getMessage(e));
      return false;
    }
  }

  Future<bool> remove(int id) async {
    try {
      await FamilyApi.deleteMember(id);
      state = state.copyWith(
        members: state.members.where((m) => m['id'] != id).toList(),
      );
      return true;
    } catch (e) {
      state = state.copyWith(error: ErrorHandler.getMessage(e));
      return false;
    }
  }
}

final familyProvider =
    StateNotifierProvider<FamilyNotifier, FamilyState>((ref) {
  final notifier = FamilyNotifier();
  notifier.load();
  return notifier;
});
