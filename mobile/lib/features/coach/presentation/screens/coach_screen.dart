// CoachScreen — AI growth coach chat interface.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../models/coach_message.dart';
import '../../../../features/auth/presentation/screens/login_screen.dart';
import '../../../../services/subscription_service.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final _messagesProvider =
    StateNotifierProvider.autoDispose<_MessagesNotifier, _ChatState>(
  (ref) => _MessagesNotifier(ref),
);

class _ChatState {
  final List<CoachMessage> messages;
  final bool isLoading;
  final bool isSending;

  const _ChatState({
    this.messages = const [],
    this.isLoading = true,
    this.isSending = false,
  });

  _ChatState copyWith({
    List<CoachMessage>? messages,
    bool? isLoading,
    bool? isSending,
  }) =>
      _ChatState(
        messages: messages ?? this.messages,
        isLoading: isLoading ?? this.isLoading,
        isSending: isSending ?? this.isSending,
      );
}

class _MessagesNotifier extends StateNotifier<_ChatState> {
  _MessagesNotifier(this._ref) : super(const _ChatState()) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    try {
      final api = _ref.read(apiServiceProvider);
      final resp = await api.get('/coach/messages');
      final messages = (resp.data as List)
          .map((m) => CoachMessage.fromJson(m as Map<String, dynamic>))
          .toList();
      state = state.copyWith(messages: messages, isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> send(String content) async {
    if (content.trim().isEmpty) return;
    state = state.copyWith(isSending: true);

    try {
      final api = _ref.read(apiServiceProvider);
      final resp = await api.post('/coach/message', data: {
        'content': content.trim(),
      });

      final userMsg = CoachMessage.fromJson(
          resp.data['user_message'] as Map<String, dynamic>);
      final assistantMsg = CoachMessage.fromJson(
          resp.data['assistant_message'] as Map<String, dynamic>);

      state = state.copyWith(
        messages: [...state.messages, userMsg, assistantMsg],
        isSending: false,
      );
    } catch (_) {
      state = state.copyWith(isSending: false);
    }
  }
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class CoachScreen extends ConsumerStatefulWidget {
  const CoachScreen({super.key});

  @override
  ConsumerState<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends ConsumerState<CoachScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _inputCtrl.clear();
    ref.read(_messagesProvider.notifier).send(text);
  }

  void _sendPrompt(String prompt) {
    _inputCtrl.text = prompt;
    _send();
  }

  @override
  Widget build(BuildContext context) {
    final sub = ref.watch(subscriptionProvider);

    if (!sub.isPro) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.content),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.psychology,
                    size: 48, color: AppColors.kiwi400),
                const SizedBox(height: 16),
                Text(
                  'Growth Coach',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: AppColors.content,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Get personalized coaching based on your goals, reflections, and progress.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.contentSecondary,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => context.push('/pro'),
                    child: const Text('Unlock with Pro'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final chatState = ref.watch(_messagesProvider);

    // Auto-scroll when messages change
    if (chatState.messages.isNotEmpty) {
      _scrollToBottom();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.content),
          onPressed: () => context.pop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.psychology, size: 22, color: AppColors.kiwi500),
            const SizedBox(width: 8),
            Text(
              'Growth coach',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: AppColors.content),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Messages
          Expanded(
            child: chatState.isLoading
                ? const Center(
                    child:
                        CircularProgressIndicator(color: AppColors.kiwi400))
                : chatState.messages.isEmpty
                    ? _EmptyState(onPrompt: _sendPrompt)
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        itemCount: chatState.messages.length +
                            (chatState.isSending ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i == chatState.messages.length) {
                            return const _TypingIndicator();
                          }
                          return _MessageBubble(
                              message: chatState.messages[i]);
                        },
                      ),
          ),

          // Input bar
          _InputBar(
            controller: _inputCtrl,
            isSending: chatState.isSending,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state with suggested prompts
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onPrompt});
  final ValueChanged<String> onPrompt;

  static const _prompts = [
    "I'm feeling overwhelmed this week",
    "Help me prioritize what matters",
    "Am I on track with my goals?",
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.psychology,
              size: 56,
              color: AppColors.kiwi300,
            ),
            const SizedBox(height: 16),
            Text(
              'Your growth coach',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(color: AppColors.content),
            ),
            const SizedBox(height: 8),
            Text(
              'I know your goals, weekly intent, and reflections. Ask me anything about staying focused and intentional.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.contentSecondary, height: 1.5),
            ),
            const SizedBox(height: 24),
            ...List.generate(
              _prompts.length,
              (i) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => onPrompt(_prompts[i]),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.borderSubtle),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    child: Text(
                      _prompts[i],
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.content),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Message bubble
// ---------------------------------------------------------------------------

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final CoachMessage message;

  bool get _isUser => message.role == 'user';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: _isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _isUser ? AppColors.kiwi400 : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(_isUser ? 16 : 4),
              bottomRight: Radius.circular(_isUser ? 4 : 16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            message.content,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _isUser ? Colors.white : AppColors.content,
                  height: 1.5,
                ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Typing indicator
// ---------------------------------------------------------------------------

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dot(0),
              const SizedBox(width: 4),
              _dot(1),
              const SizedBox(width: 4),
              _dot(2),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 1.0),
      duration: Duration(milliseconds: 600 + index * 200),
      builder: (context, value, _) => Opacity(
        opacity: value,
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: AppColors.contentTertiary,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Input bar
// ---------------------------------------------------------------------------

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.isSending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        8,
        8 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 4,
              minLines: 1,
              decoration: const InputDecoration(
                hintText: 'Ask your coach...',
                hintStyle: TextStyle(color: AppColors.contentTertiary),
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: isSending ? null : onSend,
            icon: isSending
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.kiwi400,
                    ),
                  )
                : const Icon(
                    Icons.send_rounded,
                    color: AppColors.kiwi500,
                  ),
          ),
        ],
      ),
    );
  }
}
