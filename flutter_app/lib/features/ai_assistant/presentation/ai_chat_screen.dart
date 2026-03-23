import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/theme/app_theme.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen>
    with TickerProviderStateMixin {
  final List<_ChatMessage> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  String? _conversationId;

  late AnimationController _dotAnimationController;

  static const List<String> _suggestions = [
    'What are side effects of paracetamol?',
    'Can I take ibuprofen with blood thinners?',
    'What foods to avoid with warfarin?',
    'Emergency: Call 000',
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

    _inputController.clear();
    setState(() {
      _messages.insert(0, _ChatMessage(text: trimmed, isUser: true));
      _isLoading = true;
    });

    try {
      final response = await ApiClient.post('/ai/chat', data: {
        'message': trimmed,
        if (_conversationId != null) 'conversation_id': _conversationId,
      });

      final data = response.data as Map<String, dynamic>;
      _conversationId = data['conversation_id']?.toString();
      final reply = data['reply']?.toString() ??
          data['message']?.toString() ??
          'Sorry, I could not process that.';

      if (mounted) {
        setState(() {
          _isLoading = false;
          _messages.insert(0, _ChatMessage(text: reply, isUser: false));
        });
      }
    } on DioException catch (e) {
      if (mounted) {
        final errorMsg = e.response?.data?['detail']?.toString() ??
            'Something went wrong. Please try again.';
        setState(() {
          _isLoading = false;
          _messages.insert(
              0, _ChatMessage(text: errorMsg, isUser: false, isError: true));
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
                isError: true),
          );
        });
      }
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: const Color(0x1E00897B),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.psychology_outlined,
                size: 48, color: AppTheme.primary),
          ),
          const SizedBox(height: 16),
          const Text(
            "Hello! I'm VitaPulse AI.",
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Ask me anything about your health, medications, or wellness.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 14, color: AppTheme.textSecondary),
            ),
          ),
          const SizedBox(height: 28),
          const Text('Quick questions:',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: _suggestions.map((s) => _SuggestionChip(
                  label: s,
                  onTap: () => _sendMessage(s),
                )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
          ),
          boxShadow: [
            BoxShadow(
                color: const Color(0x12000000),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return AnimatedBuilder(
              animation: _dotAnimationController,
              builder: (_, __) {
                final offset =
                    ((_dotAnimationController.value * 3 - i) % 1.0).clamp(0.0, 1.0);
                final bounce = offset < 0.5 ? offset * 2 : (1.0 - offset) * 2;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 8,
                  height: 8,
                  transform: Matrix4.translationValues(0, -bounce * 6, 0),
                  decoration: BoxDecoration(
                    color: const Color(0xB300897B),
                    shape: BoxShape.circle,
                  ),
                );
              },
            );
          }),
        ),
      ),
    );
  }

  Widget _buildMessage(_ChatMessage msg) {
    final isUser = msg.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          left: isUser ? 64 : 16,
          right: isUser ? 16 : 64,
          top: 4,
          bottom: 4,
        ),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser
              ? AppTheme.primary
              : (msg.isError
                  ? const Color(0x14E53935)
                  : Colors.white),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0x12000000),
              blurRadius: 6,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Text(
          msg.text,
          style: TextStyle(
            color: isUser
                ? Colors.white
                : (msg.isError
                    ? AppTheme.emergencyRed
                    : AppTheme.textPrimary),
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Ask a health question...',
                  hintStyle:
                      const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                  filled: true,
                  fillColor: AppTheme.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onSubmitted: _sendMessage,
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: AppTheme.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _isLoading
                    ? null
                    : () => _sendMessage(_inputController.text),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child:
                      Icon(Icons.send_rounded, color: Colors.white, size: 22),
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
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Column(
          children: [
            Text(
              'AI Health Assistant',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700),
            ),
            Text(
              'Powered by Claude AI',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
        centerTitle: true,
        leading: BackButton(color: Colors.white, onPressed: () => Navigator.of(context).maybePop()),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white),
            tooltip: 'Clear conversation',
            onPressed: () {
              setState(() {
                _messages.clear();
                _conversationId = null;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
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
          const Divider(height: 1),
          _buildInput(),
        ],
      ),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;
  final bool isError;

  const _ChatMessage({
    required this.text,
    required this.isUser,
    this.isError = false,
  });
}

class _SuggestionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SuggestionChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(
        label,
        style: const TextStyle(fontSize: 12, color: AppTheme.primary),
      ),
      backgroundColor: const Color(0x1700897B),
      side: BorderSide(color: const Color(0x4D00897B)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: onTap,
    );
  }
}
