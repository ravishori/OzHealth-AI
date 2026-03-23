import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitapulse_ai/features/profile/data/user_api.dart';

// ─── State ───────────────────────────────────────────────────────────────────

class ProfileState {
  final Map<String, dynamic>? user;
  final bool isLoading;
  final String? error;

  const ProfileState({this.user, this.isLoading = false, this.error});

  ProfileState copyWith({
    Map<String, dynamic>? user,
    bool? isLoading,
    String? error,
  }) =>
      ProfileState(
        user: user ?? this.user,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class ProfileNotifier extends StateNotifier<ProfileState> {
  ProfileNotifier() : super(const ProfileState());

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await UserApi.getMe();
      state = state.copyWith(user: data, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<bool> update(Map<String, dynamic> data) async {
    try {
      final updated = await UserApi.updateMe(data);
      state = state.copyWith(user: updated);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> uploadPhoto(String filePath) async {
    try {
      final result = await UserApi.uploadPhoto(filePath);
      final updatedUser = {...?state.user, ...result};
      state = state.copyWith(user: updatedUser);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final profileProvider =
    StateNotifierProvider<ProfileNotifier, ProfileState>((ref) {
  final notifier = ProfileNotifier();
  notifier.load();
  return notifier;
});
