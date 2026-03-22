import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitapulse_ai/features/health_monitoring/data/health_api.dart';

class HealthState {
  final Map<String, dynamic> summary;         // latest per metric type
  final Map<String, List<dynamic>> history;   // metricType → list of readings
  final bool isLoading;
  final bool isLogging;
  final String? error;

  const HealthState({
    this.summary = const {},
    this.history = const {},
    this.isLoading = false,
    this.isLogging = false,
    this.error,
  });

  HealthState copyWith({
    Map<String, dynamic>? summary,
    Map<String, List<dynamic>>? history,
    bool? isLoading,
    bool? isLogging,
    String? error,
  }) =>
      HealthState(
        summary: summary ?? this.summary,
        history: history ?? this.history,
        isLoading: isLoading ?? this.isLoading,
        isLogging: isLogging ?? this.isLogging,
        error: error,
      );
}

class HealthNotifier extends StateNotifier<HealthState> {
  HealthNotifier() : super(const HealthState());

  Future<void> loadSummary({int? familyMemberId}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await HealthApi.getSummary(familyMemberId: familyMemberId);
      state = state.copyWith(summary: data, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadHistory(String metricType,
      {int days = 30, int? familyMemberId}) async {
    try {
      final data = await HealthApi.getMetrics(
        metricType: metricType,
        familyMemberId: familyMemberId,
        days: days,
      );
      state = state.copyWith(
        history: {...state.history, metricType: data},
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<bool> logMetric({
    required String metricType,
    required double value,
    double? value2,
    String? unit,
    String? notes,
    int? familyMemberId,
  }) async {
    state = state.copyWith(isLogging: true, error: null);
    try {
      final reading = await HealthApi.logMetric(
        metricType: metricType,
        value: value,
        value2: value2,
        unit: unit,
        notes: notes,
        familyMemberId: familyMemberId,
      );
      // Update summary with latest reading
      final updatedSummary = {
        ...state.summary,
        metricType: reading,
      };
      // Prepend to history if already loaded
      final existingHistory = state.history[metricType] ?? [];
      state = state.copyWith(
        summary: updatedSummary,
        history: {...state.history, metricType: [reading, ...existingHistory]},
        isLogging: false,
      );
      return true;
    } catch (e) {
      state = state.copyWith(isLogging: false, error: e.toString());
      return false;
    }
  }
}

final healthProvider =
    StateNotifierProvider<HealthNotifier, HealthState>((ref) {
  final notifier = HealthNotifier();
  notifier.loadSummary();
  return notifier;
});
