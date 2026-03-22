import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitapulse_ai/features/records/data/records_api.dart';

class RecordsState {
  final List<dynamic> records;
  final bool isLoading;
  final bool isUploading;
  final String? error;

  const RecordsState({
    this.records = const [],
    this.isLoading = false,
    this.isUploading = false,
    this.error,
  });

  RecordsState copyWith({
    List<dynamic>? records,
    bool? isLoading,
    bool? isUploading,
    String? error,
  }) =>
      RecordsState(
        records: records ?? this.records,
        isLoading: isLoading ?? this.isLoading,
        isUploading: isUploading ?? this.isUploading,
        error: error,
      );
}

class RecordsNotifier extends StateNotifier<RecordsState> {
  RecordsNotifier() : super(const RecordsState());

  Future<void> load({String? recordType, int? familyMemberId}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await RecordsApi.getRecords(
        recordType: recordType,
        familyMemberId: familyMemberId,
      );
      state = state.copyWith(records: data, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<bool> upload({
    required String filePath,
    required String recordType,
    String? title,
    String? notes,
    int? familyMemberId,
    String? recordDate,
  }) async {
    state = state.copyWith(isUploading: true, error: null);
    try {
      final record = await RecordsApi.uploadRecord(
        filePath: filePath,
        recordType: recordType,
        title: title,
        notes: notes,
        familyMemberId: familyMemberId,
        recordDate: recordDate,
      );
      state = state.copyWith(
        records: [record, ...state.records],
        isUploading: false,
      );
      return true;
    } catch (e) {
      state = state.copyWith(isUploading: false, error: e.toString());
      return false;
    }
  }

  Future<bool> remove(int id) async {
    try {
      await RecordsApi.deleteRecord(id);
      state = state.copyWith(
        records: state.records.where((r) => r['id'] != id).toList(),
      );
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }
}

final recordsProvider =
    StateNotifierProvider<RecordsNotifier, RecordsState>((ref) {
  final notifier = RecordsNotifier();
  notifier.load();
  return notifier;
});
