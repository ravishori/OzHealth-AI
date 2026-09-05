import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:vitapulse_ai/features/ai_assistant/providers/ai_provider.dart';
import 'package:vitapulse_ai/shared/widgets/empty_state.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';

/// Result popped to [AiChatScreen]: open an owned conversation, or start new.
class AiHistorySelection {
  final int? conversationId;
  final bool startNew;

  const AiHistorySelection.open(this.conversationId) : startNew = false;
  const AiHistorySelection.newChat()
      : conversationId = null,
        startNew = true;
}

/// Browse past AI conversations (metadata only — no message bodies in the list).
class AiConversationHistoryScreen extends ConsumerWidget {
  const AiConversationHistoryScreen({super.key});

  static final _dateFmt = DateFormat('dd MMM yyyy · HH:mm');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(conversationsProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conversation history'),
        actions: [
          TextButton(
            onPressed: () =>
                context.pop(const AiHistorySelection.newChat()),
            child: const Text('New chat'),
          ),
        ],
      ),
      body: asyncList.when(
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (err, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Could not load history',
          subtitle: ErrorHandler.getMessage(err),
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(conversationsProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.chat_bubble_outline,
              title: 'No conversations yet',
              subtitle:
                  'Start a chat with the AI assistant. Past conversations '
                  'will appear here. Saved replies are informational only — '
                  'not a diagnosis or prescription.',
              actionLabel: 'New chat',
              onAction: () =>
                  context.pop(const AiHistorySelection.newChat()),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(conversationsProvider);
              await ref.read(conversationsProvider.future);
            },
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final raw = items[index];
                final item = raw is Map
                    ? Map<String, dynamic>.from(raw)
                    : <String, dynamic>{};
                final id = item['id'];
                final title = (item['title']?.toString().trim().isNotEmpty ==
                        true)
                    ? item['title'].toString().trim()
                    : 'Untitled conversation';
                final count = item['message_count'];
                final updated = _formatWhen(
                  item['updated_at'] ?? item['created_at'],
                );

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: cs.primaryContainer,
                    child: Icon(Icons.forum_outlined,
                        color: cs.onPrimaryContainer, size: 20),
                  ),
                  title: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    [
                      if (updated != null) updated,
                      if (count != null) '$count messages',
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppRadius.brMd,
                  ),
                  onTap: () {
                    final parsed = id is int
                        ? id
                        : int.tryParse(id?.toString() ?? '');
                    if (parsed == null) return;
                    context.pop(AiHistorySelection.open(parsed));
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }

  static String? _formatWhen(dynamic value) {
    if (value == null) return null;
    DateTime? dt;
    if (value is DateTime) {
      dt = value.toLocal();
    } else {
      dt = DateTime.tryParse(value.toString())?.toLocal();
    }
    if (dt == null) return null;
    return _dateFmt.format(dt);
  }
}
