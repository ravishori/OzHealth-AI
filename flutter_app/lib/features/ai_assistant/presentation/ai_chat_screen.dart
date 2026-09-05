import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:vitapulse_ai/features/ai_assistant/data/ai_api.dart';
import 'package:vitapulse_ai/features/ai_assistant/presentation/ai_conversation_history_screen.dart';
import 'package:vitapulse_ai/shared/widgets/clinical_safety_banner.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen>
    with SingleTickerProviderStateMixin {
  final List<_ChatMessage> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _providerDegraded = false;
  String? _conversationId;
  String _language = 'english';

  late AnimationController _dotAnimationController;

  static const List<_Suggestion> _suggestions = [
    _Suggestion(
      label: 'Paracetamol side effects',
      icon: Icons.medication_outlined,
      query: 'What are side effects of paracetamol?',
    ),
    _Suggestion(
      label: 'Ibuprofen + blood thinners',
      icon: Icons.warning_amber_outlined,
      query: 'Can I take ibuprofen with blood thinners?',
    ),
    _Suggestion(
      label: 'Foods to avoid with warfarin',
      icon: Icons.no_food_outlined,
      query: 'What foods to avoid with warfarin?',
    ),
    _Suggestion(
      label: 'Emergency — Call 000',
      icon: Icons.local_hospital_outlined,
      query: 'Emergency: Call 000',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _dotAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _dotAnimationController.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (_isLoading) return;

    _inputController.clear();
    setState(() {
      _messages.insert(0, _ChatMessage(text: trimmed, isUser: true));
      _isLoading = true;
    });

    try {
      final response = await ApiClient.post('/ai/chat', data: {
        'message': trimmed,
        if (_conversationId != null) 'conversation_id': _conversationId,
        if (_language != 'english') 'language': _language,
      });

      final data = response.data as Map<String, dynamic>;
      _conversationId = data['conversation_id']?.toString();
      var reply = data['reply']?.toString() ??
          data['message']?.toString() ??
          '';
      if (reply.trim().isEmpty) {
        reply =
            'No response received. Please try again. This is not medical advice.';
      }
      final degraded = data['degraded'] == true ||
          reply.startsWith('[DEGRADED]') ||
          reply.toLowerCase().contains('trouble connecting to the ai service');

      if (mounted) {
        setState(() {
          _isLoading = false;
          _providerDegraded = degraded || _providerDegraded;
          _messages.insert(
            0,
            _ChatMessage(text: reply, isUser: false, isDegraded: degraded),
          );
        });
      }
    } on DioException catch (e) {
      if (mounted) {
        final errorMsg = e.response?.data?['detail']?.toString() ??
            (e.type == DioExceptionType.receiveTimeout ||
                    e.type == DioExceptionType.connectionTimeout
                ? 'The request timed out. Please try again.'
                : 'Something went wrong. Please try again.');
        setState(() {
          _isLoading = false;
          _messages.insert(
            0,
            _ChatMessage(
              text: errorMsg,
              isUser: false,
              isError: true,
              retryText: trimmed,
            ),
          );
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _messages.insert(
            0,
            _ChatMessage(
              text: 'Unexpected error. Please try again.',
              isUser: false,
              isError: true,
              retryText: trimmed,
            ),
          );
        });
      }
    }
  }

  Future<void> _openHistory() async {
    final result = await context.push<AiHistorySelection>('/home/ai-chat/history');
    if (!mounted || result == null) return;
    if (result.startNew) {
      _startNewChat();
      return;
    }
    final id = result.conversationId;
    if (id == null) return;
    await _resumeConversation(id);
  }

  void _startNewChat() {
    setState(() {
      _messages.clear();
      _conversationId = null;
      _isLoading = false;
      _providerDegraded = false;
    });
  }

  /// Load an owned conversation via authenticated API (server enforces ownership).
  Future<void> _resumeConversation(int id) async {
    setState(() => _isLoading = true);
    try {
      final conv = await AiApi.getConversation(id);
      final raw = (conv['messages'] as List<dynamic>?) ?? const [];
      // Chat ListView is reverse: newest first.
      final loaded = <_ChatMessage>[];
      for (final m in raw.reversed) {
        if (m is! Map) continue;
        final role = m['role']?.toString() ?? '';
        final content = m['content']?.toString() ?? '';
        if (content.isEmpty) continue;
        loaded.add(_ChatMessage(text: content, isUser: role == 'user'));
      }
      if (!mounted) return;
      setState(() {
        _conversationId =
            (conv['id'] ?? id).toString();
        _messages
          ..clear()
          ..addAll(loaded);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorHandler.getMessage(e))),
      );
    }
  }

  Future<void> _reportAiContent() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Report AI content'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'offensive_or_unsafe'),
            child: const Text('Offensive or unsafe'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'medical_misinformation'),
            child: const Text('Medical misinformation'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'other'),
            child: const Text('Other'),
          ),
        ],
      ),
    );
    if (reason == null || !mounted) return;
    try {
      await ApiClient.post('/ai/report', data: {
        'reason': reason,
        if (_conversationId != null)
          'conversation_id': int.tryParse(_conversationId!),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report received. Thank you.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send report. Try again.')),
      );
    }
  }

  Widget _buildEmptyState() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hc = HealthcareColors.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          // AI avatar with glow rings
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      hc.aiAccent.withValues(alpha: 0.12),
                      hc.aiAccent.withValues(alpha: 0.0),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      hc.aiAccent.withValues(alpha: 0.25),
                      cs.primaryContainer.withValues(alpha: 0.4),
                    ],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: hc.aiAccent.withValues(alpha: 0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.psychology_rounded,
                  size: 44,
                  color: hc.aiAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            "Hello! I'm HealthNest",
            style: tt.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ask me anything about your health,\nmedications, or wellness.',
            textAlign: TextAlign.center,
            style: tt.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: hc.aiAccent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, size: 12, color: hc.aiAccent),
                const SizedBox(width: 5),
                Text(
                  'Powered by Claude AI',
                  style: TextStyle(
                    fontSize: 11,
                    color: hc.aiAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Quick questions',
              style: tt.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _suggestions
                .map((s) => _SuggestionChip(
                      suggestion: s,
                      onTap: () => _sendMessage(s.query),
                    ))
                .toList(),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    final cs = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 64, top: 4, bottom: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _AiAvatar(),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                  bottomLeft: Radius.circular(4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  return AnimatedBuilder(
                    animation: _dotAnimationController,
                    builder: (_, __) {
                      final offset =
                          ((_dotAnimationController.value * 3 - i) % 1.0)
                              .clamp(0.0, 1.0);
                      final bounce =
                          offset < 0.5 ? offset * 2 : (1.0 - offset) * 2;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: 7,
                        height: 7,
                        transform:
                            Matrix4.translationValues(0, -bounce * 5, 0),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                      );
                    },
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessage(_ChatMessage msg) {
    final cs = Theme.of(context).colorScheme;

    if (msg.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(left: 64, right: 16, top: 4, bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cs.primary, cs.primary.withValues(alpha: 0.85)],
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(5),
            ),
            boxShadow: [
              BoxShadow(
                color: cs.primary.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            msg.text,
            style: TextStyle(
              color: cs.onPrimary,
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 48, top: 4, bottom: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _AiAvatar(),
            const SizedBox(width: 8),
            Flexible(
              child: Container(
                decoration: BoxDecoration(
                  color: msg.isError
                      ? cs.errorContainer.withValues(alpha: 0.7)
                      : cs.surfaceContainerLow,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                    bottomLeft: Radius.circular(5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: cs.shadow.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                    bottomLeft: Radius.circular(5),
                  ),
                  child: msg.isError
                      ? Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 11),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.error_outline_rounded,
                                      color: cs.error, size: 16),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      msg.text,
                                      style: TextStyle(
                                          color: cs.error,
                                          fontSize: 13,
                                          height: 1.45),
                                    ),
                                  ),
                                ],
                              ),
                              if (msg.retryText != null &&
                                  msg.retryText!.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                TextButton.icon(
                                  onPressed: _isLoading
                                      ? null
                                      : () {
                                          setState(() {
                                            _messages.remove(msg);
                                          });
                                          _sendMessage(msg.retryText!);
                                        },
                                  icon: const Icon(Icons.refresh, size: 16),
                                  label: const Text('Retry'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: cs.error,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        )
                      : _AiMarkdownBubble(text: msg.text),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInput() {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: TextField(
                  controller: _inputController,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Ask a health question…',
                    hintStyle: TextStyle(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        fontSize: 14),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 11),
                  ),
                  onSubmitted: _sendMessage,
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 44,
              child: Material(
                color: _isLoading
                    ? cs.primary.withValues(alpha: 0.4)
                    : cs.primary,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _isLoading
                      ? null
                      : () => _sendMessage(_inputController.text),
                  child: Center(
                    child: _isLoading
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.onPrimary,
                            ),
                          )
                        : Icon(Icons.send_rounded,
                            color: cs.onPrimary, size: 20),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: hc.aiAccent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.psychology_rounded,
                  size: 18, color: hc.aiAccent),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI Health Assistant',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: hc.vitaGood,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Text(
                      _providerDegraded
                          ? 'Limited · AI unavailable'
                          : 'Online · Claude AI',
                      style: TextStyle(
                        fontSize: 10,
                        color: _providerDegraded
                            ? cs.error
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        centerTitle: false,
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.history, color: cs.onSurfaceVariant),
            tooltip: 'Conversation history',
            onPressed: _isLoading ? null : _openHistory,
          ),
          IconButton(
            icon: Icon(Icons.flag_outlined, color: cs.onSurfaceVariant),
            tooltip: 'Report AI content',
            onPressed: _reportAiContent,
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.translate_rounded,
                size: 20, color: cs.onSurfaceVariant),
            tooltip: 'Response language',
            onSelected: (lang) => setState(() => _language = lang),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'english', child: Text('English')),
              PopupMenuItem(value: 'hindi', child: Text('Hindi')),
              PopupMenuItem(value: 'marathi', child: Text('Marathi')),
            ],
          ),
          IconButton(
            icon: Icon(Icons.add_comment_outlined,
                size: 20, color: cs.onSurfaceVariant),
            tooltip: 'New chat',
            onPressed: _isLoading ? null : _startNewChat,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          const ClinicalSafetyBanner(kind: ClinicalDisclaimerKind.ai),
          Expanded(
            child: _messages.isEmpty && !_isLoading
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: _messages.length + (_isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_isLoading && index == 0) {
                        return _buildTypingIndicator();
                      }
                      final msgIndex = _isLoading ? index - 1 : index;
                      return _buildMessage(_messages[msgIndex]);
                    },
                  ),
          ),
          _buildInput(),
        ],
      ),
    );
  }
}

// ─────────────────────────── AI avatar ───────────────────────────

class _AiAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final hc = HealthcareColors.of(context);
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: hc.aiAccent.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.psychology_rounded, size: 16, color: hc.aiAccent),
    );
  }
}

// ─────────────────────────── Suggestion chip ───────────────────────────

class _SuggestionChip extends StatelessWidget {
  final _Suggestion suggestion;
  final VoidCallback onTap;

  const _SuggestionChip({required this.suggestion, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ActionChip(
      avatar: Icon(suggestion.icon, size: 14, color: cs.primary),
      label: Text(
        suggestion.label,
        style: TextStyle(
          fontSize: 12,
          color: cs.onSurface,
          fontWeight: FontWeight.w500,
        ),
      ),
      backgroundColor: cs.surfaceContainerLow,
      side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      onPressed: onTap,
    );
  }
}

// ─────────────────────────── AI markdown bubble ───────────────────────────

class _AiMarkdownBubble extends StatelessWidget {
  final String text;
  const _AiMarkdownBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: MarkdownBody(
        data: text,
        selectable: true,
        styleSheet: _buildStyleSheet(cs, hc),
      ),
    );
  }

  MarkdownStyleSheet _buildStyleSheet(
      ColorScheme cs, HealthcareColors hc) {
    return MarkdownStyleSheet(
      h1: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: cs.onSurface,
        height: 1.3,
      ),
      h2: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: cs.primary,
        height: 1.3,
      ),
      h3: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: cs.onSurface,
        height: 1.3,
      ),
      p: TextStyle(
        fontSize: 14,
        color: cs.onSurface,
        height: 1.5,
      ),
      strong: TextStyle(
        fontWeight: FontWeight.w700,
        color: cs.onSurface,
      ),
      em: TextStyle(
        fontStyle: FontStyle.italic,
        color: cs.onSurfaceVariant,
      ),
      code: TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        color: hc.aiAccent,
        backgroundColor: cs.primaryContainer.withValues(alpha: 0.25),
      ),
      codeblockDecoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      blockquote: TextStyle(
        fontSize: 13,
        color: cs.onSurfaceVariant,
        fontStyle: FontStyle.italic,
        height: 1.5,
      ),
      blockquoteDecoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: cs.primary, width: 4),
        ),
      ),
      blockquotePadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant, width: 1),
        ),
      ),
      listBullet: TextStyle(
        fontSize: 14,
        color: cs.primary,
        height: 1.5,
      ),
      listIndent: 16,
      tableBody: TextStyle(fontSize: 13, color: cs.onSurface),
      tableHead: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: cs.onSurface,
      ),
      tableHeadAlign: TextAlign.left,
      tableBorder: TableBorder.all(color: cs.outline, width: 1),
      tableColumnWidth: const FlexColumnWidth(),
      tableCellsPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      blockSpacing: 10,
      h1Padding: const EdgeInsets.only(bottom: 4),
      h2Padding: const EdgeInsets.only(top: 4, bottom: 2),
    );
  }
}

// ─────────────────────────── Supporting types ───────────────────────────

class _ChatMessage {
  final String text;
  final bool isUser;
  final bool isError;
  final bool isDegraded;
  final String? retryText;

  const _ChatMessage({
    required this.text,
    required this.isUser,
    this.isError = false,
    this.isDegraded = false,
    this.retryText,
  });
}

class _Suggestion {
  final String label;
  final IconData icon;
  final String query;

  const _Suggestion({
    required this.label,
    required this.icon,
    required this.query,
  });
}
