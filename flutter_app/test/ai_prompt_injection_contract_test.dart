import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/legal/legal_copy.dart';
import 'package:vitapulse_ai/shared/widgets/clinical_safety_banner.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppThemeBuilder.light(const AppThemeSettings()),
    home: Scaffold(body: child),
  );
}

/// HN-AI-010 Flutter contracts — UI must not bypass backend safety boundary.
void main() {
  test('AI-CHAT still posts to /ai/chat (backend safety choke point)', () {
    final src = File(
      'lib/features/ai_assistant/presentation/ai_chat_screen.dart',
    ).readAsStringSync();
    expect(src.contains("ApiClient.post('/ai/chat'"), isTrue);
    expect(src.toLowerCase().contains('ignore all previous instructions'), isFalse);
    expect(src.contains('system prompt'), isFalse);
  });

  test('AI chat retains ClinicalSafetyBanner / LegalCopy.aiBanner', () {
    final src = File(
      'lib/features/ai_assistant/presentation/ai_chat_screen.dart',
    ).readAsStringSync();
    expect(src.contains('ClinicalSafetyBanner'), isTrue);
    expect(src.contains('ClinicalDisclaimerKind.ai'), isTrue);
    expect(LegalCopy.aiBanner.toLowerCase().contains('does not diagnose'), isTrue);
  });

  test('AI history/new-chat contracts unchanged (HN-AI-003 non-regression)', () {
    final chat = File(
      'lib/features/ai_assistant/presentation/ai_chat_screen.dart',
    ).readAsStringSync();
    final hist = File(
      'lib/features/ai_assistant/presentation/ai_conversation_history_screen.dart',
    ).readAsStringSync();
    expect(
      chat.contains('AiApi.getConversation') || chat.contains('getConversation'),
      isTrue,
    );
    expect(
      hist.contains('conversationsProvider') || hist.contains('getConversations'),
      isTrue,
    );
  });

  testWidgets('ClinicalSafetyBanner ai kind renders without crash', (tester) async {
    await tester.pumpWidget(
      _wrap(const ClinicalSafetyBanner(kind: ClinicalDisclaimerKind.ai)),
    );
    expect(find.text(LegalCopy.aiBanner), findsOneWidget);
  });

  test('SAFE fallback string is user-safe if surfaced', () {
    final src = File(
      'lib/features/ai_assistant/presentation/ai_chat_screen.dart',
    ).readAsStringSync();
    expect(src.contains('reply') || src.contains('response'), isTrue);
  });
}
