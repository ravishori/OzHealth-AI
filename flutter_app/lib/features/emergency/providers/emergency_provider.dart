import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitapulse_ai/features/emergency/data/emergency_api.dart';

class EmergencyState {
  final List<dynamic> contacts;
  final bool isLoading;
  final bool isSendingSOS;
  final String? sosResult;
  final String? error;

  const EmergencyState({
    this.contacts = const [],
    this.isLoading = false,
    this.isSendingSOS = false,
    this.sosResult,
    this.error,
  });

  EmergencyState copyWith({
    List<dynamic>? contacts,
    bool? isLoading,
    bool? isSendingSOS,
    String? sosResult,
    String? error,
  }) =>
      EmergencyState(
        contacts: contacts ?? this.contacts,
        isLoading: isLoading ?? this.isLoading,
        isSendingSOS: isSendingSOS ?? this.isSendingSOS,
        sosResult: sosResult ?? this.sosResult,
        error: error,
      );
}

class EmergencyNotifier extends StateNotifier<EmergencyState> {
  EmergencyNotifier() : super(const EmergencyState());

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await EmergencyApi.getContacts();
      state = state.copyWith(contacts: data, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<bool> addContact(Map<String, dynamic> data) async {
    try {
      final contact = await EmergencyApi.addContact(data);
      state = state.copyWith(contacts: [...state.contacts, contact]);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> removeContact(int id) async {
    try {
      await EmergencyApi.deleteContact(id);
      state = state.copyWith(
        contacts: state.contacts.where((c) => c['id'] != id).toList(),
      );
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<Map<String, dynamic>?> sendSOS({
    double? latitude,
    double? longitude,
    String? message,
  }) async {
    state = state.copyWith(isSendingSOS: true, error: null);
    try {
      final result = await EmergencyApi.sendSOS(
        latitude: latitude,
        longitude: longitude,
        message: message,
      );
      state = state.copyWith(
        isSendingSOS: false,
        sosResult: result['message'] as String?,
      );
      return result;
    } catch (e) {
      state = state.copyWith(isSendingSOS: false, error: e.toString());
      return null;
    }
  }
}

final emergencyProvider =
    StateNotifierProvider<EmergencyNotifier, EmergencyState>((ref) {
  final notifier = EmergencyNotifier();
  notifier.load();
  return notifier;
});
