import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitapulse_ai/features/reminders/data/reminder_api.dart';

class RemindersState {
  final List<dynamic> reminders;
  final bool isLoading;
  final String? error;

  const RemindersState({
    this.reminders = const [],
    this.isLoading = false,
    this.error,
  });

  RemindersState copyWith({
    List<dynamic>? reminders,
    bool? isLoading,
    String? error,
  }) =>
      RemindersState(
        reminders: reminders ?? this.reminders,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class RemindersNotifier extends StateNotifier<RemindersState> {
  RemindersNotifier() : super(const RemindersState());

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await ReminderApi.getReminders();
      state = state.copyWith(reminders: data, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: ErrorHandler.getMessage(e));
    }
  }

  Future<bool> add(Map<String, dynamic> data) async {
    try {
      final reminder = await ReminderApi.createReminder(data);
      state = state.copyWith(reminders: [reminder, ...state.reminders]);
      return true;
    } catch (e) {
      state = state.copyWith(error: ErrorHandler.getMessage(e));
      return false;
    }
  }

  Future<bool> update(int id, Map<String, dynamic> data) async {
    try {
      final updated = await ReminderApi.updateReminder(id, data);
      state = state.copyWith(
        reminders: state.reminders
            .map((r) => (r['id'] == id) ? updated : r)
            .toList(),
      );
      return true;
    } catch (e) {
      state = state.copyWith(error: ErrorHandler.getMessage(e));
      return false;
    }
  }

  Future<bool> toggle(int id, bool isActive) async {
    try {
      await ReminderApi.toggleReminder(id, isActive);
      state = state.copyWith(
        reminders: state.reminders.map((r) {
          if (r['id'] == id) {
            return {...r as Map<String, dynamic>, 'is_active': isActive};
          }
          return r;
        }).toList(),
      );
      return true;
    } catch (e) {
      state = state.copyWith(error: ErrorHandler.getMessage(e));
      return false;
    }
  }

  Future<bool> remove(int id) async {
    try {
      await ReminderApi.deleteReminder(id);
      state = state.copyWith(
        reminders: state.reminders.where((r) => r['id'] != id).toList(),
      );
      return true;
    } catch (e) {
      state = state.copyWith(error: ErrorHandler.getMessage(e));
      return false;
    }
  }
}

final remindersProvider =
    StateNotifierProvider<RemindersNotifier, RemindersState>((ref) {
  final notifier = RemindersNotifier();
  notifier.load();
  return notifier;
});
