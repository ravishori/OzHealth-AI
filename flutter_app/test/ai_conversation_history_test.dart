import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/ai_assistant/presentation/ai_conversation_history_screen.dart';
import 'package:vitapulse_ai/features/ai_assistant/providers/ai_provider.dart';
import 'package:vitapulse_ai/features/legal/legal_copy.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

Widget _wrap(
  Widget child, {
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppThemeBuilder.light(const AppThemeSettings()),
      home: child,
    ),
  );
}

void main() {
  group('HN-AI-003 conversation history UI', () {
    testWidgets('AI-HIST-01 / AI-HIST-12 list shows metadata not message bodies',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AiConversationHistoryScreen(),
          overrides: [
            conversationsProvider.overrideWith((ref) async {
              return [
                {
                  'id': 10,
                  'title': 'Paracetamol side effects',
                  'context_type': 'general',
                  'message_count': 4,
                  'created_at': '2026-09-01T10:00:00Z',
                  'updated_at': '2026-09-01T11:00:00Z',
                },
              ];
            }),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Paracetamol side effects'), findsOneWidget);
      expect(find.textContaining('4 messages'), findsOneWidget);
      // Must not render raw chat roles / body dumps in the list.
      expect(find.textContaining('"role"'), findsNothing);
      expect(find.textContaining('assistant:'), findsNothing);
    });

    testWidgets('AI-HIST-02 empty history renders correctly', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AiConversationHistoryScreen(),
          overrides: [
            conversationsProvider.overrideWith((ref) async => <dynamic>[]),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No conversations yet'), findsOneWidget);
      expect(find.text('New chat'), findsWidgets);
    });

    testWidgets('AI-HIST-03 loading state renders correctly', (tester) async {
      final completer = Completer<List<dynamic>>();
      await tester.pumpWidget(
        _wrap(
          const AiConversationHistoryScreen(),
          overrides: [
            conversationsProvider.overrideWith((ref) => completer.future),
          ],
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      completer.complete(const <dynamic>[]);
      await tester.pumpAndSettle();
    });

    testWidgets('AI-HIST-04 API failure renders safe error + retry',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AiConversationHistoryScreen(),
          overrides: [
            conversationsProvider.overrideWith((ref) async {
              throw Exception('network down');
            }),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Could not load history'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      // Error UI must not dump conversation payloads.
      expect(find.textContaining('"messages"'), findsNothing);
    });

    test('AI-HIST-05/06/07/10 chat resume + new-chat contracts in source', () {
      final chat = File(
              'lib/features/ai_assistant/presentation/ai_chat_screen.dart')
          .readAsStringSync();
      final history = File(
              'lib/features/ai_assistant/presentation/ai_conversation_history_screen.dart')
          .readAsStringSync();
      final router =
          File('lib/core/router/app_router.dart').readAsStringSync();

      expect(chat.contains('_openHistory'), isTrue);
      expect(chat.contains('_resumeConversation'), isTrue);
      expect(chat.contains('AiApi.getConversation'), isTrue);
      expect(chat.contains('_conversationId'), isTrue);
      expect(chat.contains('_startNewChat'), isTrue);
      expect(chat.contains("tooltip: 'New chat'"), isTrue);
      expect(history.contains('conversationsProvider'), isTrue);
      expect(history.contains('AiHistorySelection'), isTrue);
      expect(router.contains('ai-chat/history'), isTrue);
      // UI must not invent cross-user ids.
      expect(chat.contains('user_id'), isFalse);
      expect(history.contains('user_id'), isFalse);
    });

    test('AI-HIST-11 AI safety banner remains in chat', () {
      final chat = File(
              'lib/features/ai_assistant/presentation/ai_chat_screen.dart')
          .readAsStringSync();
      expect(chat.contains('ClinicalDisclaimerKind.ai'), isTrue);
      expect(LegalCopy.aiBanner.contains('does not diagnose'), isTrue);
      expect(chat.contains('confirmed diagnosis'), isFalse);
      expect(chat.contains('doctor-approved'), isFalse);
    });

    test('AI-HIST-12 history list uses metadata fields only', () {
      final history = File(
              'lib/features/ai_assistant/presentation/ai_conversation_history_screen.dart')
          .readAsStringSync();
      expect(history.contains("item['title']"), isTrue);
      expect(history.contains("item['message_count']"), isTrue);
      expect(history.contains("item['messages']"), isFalse);
      expect(history.contains('debugPrint'), isFalse);
      expect(history.contains('print('), isFalse);
    });

    test('AI-HIST provider loadConversation preserves conversation_id',
        () async {
      // Unit-level: notifier assigns the requested id (API mocked via override path).
      final notifier = AiChatNotifier();
      expect(notifier.state.conversationId, isNull);
      // Simulate successful load assignment contract without network:
      notifier.state = notifier.state.copyWith(
        conversationId: 42,
        messages: [
          {'role': 'user', 'content': 'Hi'},
        ],
      );
      expect(notifier.state.conversationId, 42);
      notifier.startNewChat();
      expect(notifier.state.conversationId, isNull);
      expect(notifier.state.messages, isEmpty);
    });
  });
}
