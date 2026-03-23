import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitapulse_ai/features/ai_assistant/data/ai_api.dart';

class AiChatState {
  final int? conversationId;
  final List<Map<String, dynamic>> messages;   // {role, content, timestamp}
  final bool isTyping;
  final String? error;

  const AiChatState({
    this.conversationId,
    this.messages = const [],
    this.isTyping = false,
    this.error,
  });

  AiChatState copyWith({
    int? conversationId,
    List<Map<String, dynamic>>? messages,
    bool? isTyping,
    String? error,
  }) =>
      AiChatState(
        conversationId: conversationId ?? this.conversationId,
        messages: messages ?? this.messages,
        isTyping: isTyping ?? this.isTyping,
        error: error,
      );
}

class AiChatNotifier extends StateNotifier<AiChatState> {
  AiChatNotifier() : super(const AiChatState());

  /// Resume an existing conversation.
  Future<void> loadConversation(int id) async {
    try {
      final conv = await AiApi.getConversation(id);
      final msgs = (conv['messages'] as List<dynamic>)
          .map((m) => Map<String, dynamic>.from(m as Map))
          .toList();
      state = state.copyWith(conversationId: id, messages: msgs);
    } catch (e) {
      state = state.copyWith(error: ErrorHandler.getMessage(e));
    }
  }

  Future<void> sendMessage(String text,
      {String contextType = 'general'}) async {
    // Optimistically add user message
    final userMsg = <String, dynamic>{
      'role': 'user',
      'content': text,
      'timestamp': DateTime.now().toIso8601String(),
    };
    state = state.copyWith(
      messages: [...state.messages, userMsg],
      isTyping: true,
      error: null,
    );

    try {
      final result = await AiApi.chat(
        message: text,
        conversationId: state.conversationId,
        contextType: contextType,
      );

      final assistantMsg = <String, dynamic>{
        'role': 'assistant',
        'content': result['response'] ?? result['reply'] ?? '',
        'timestamp': DateTime.now().toIso8601String(),
      };
      state = state.copyWith(
        conversationId: result['conversation_id'] as int?,
        messages: [...state.messages, assistantMsg],
        isTyping: false,
      );
    } catch (e) {
      // Remove optimistic user message on failure
      state = state.copyWith(
        messages: state.messages
            .where((m) => !identical(m, userMsg))
            .toList(),
        isTyping: false,
        error: ErrorHandler.getMessage(e),
      );
    }
  }

  void startNewChat() {
    state = const AiChatState();
  }
}

final aiChatProvider =
    StateNotifierProvider.autoDispose<AiChatNotifier, AiChatState>((ref) {
  return AiChatNotifier();
});

// ── Conversation history list ─────────────────────────────────────────────────

final conversationsProvider = FutureProvider<List<dynamic>>((ref) async {
  return AiApi.getConversations();
});
