// CoachScreen — AI growth coach chat interface.
//
// Opens with a once-per-day Daily Briefing card that synthesizes the user's
// current goal/intent/tasks. Free-tier users see the briefing headline only
// as a teaser; body, follow-up chips, and chat input require Pro.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/ai_consent_dialog.dart';
import '../../../../models/coach_briefing.dart';
import '../../../../models/coach_message.dart';
import '../../../../services/providers.dart';
import '../../../../services/review_service.dart';
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
  final CoachBriefing? briefing;
  final bool isLoading;
  final bool isSending;

  const _ChatState({
    this.messages = const [],
    this.briefing,
    this.isLoading = true,
    this.isSending = false,
  });

  _ChatState copyWith({
    List<CoachMessage>? messages,
    CoachBriefing? briefing,
    bool clearBriefing = false,
    bool? isLoading,
    bool? isSending,
  }) =>
      _ChatState(
        messages: messages ?? this.messages,
        briefing: clearBriefing ? null : (briefing ?? this.briefing),
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
    final api = _ref.read(apiServiceProvider);

    // Fetch messages + briefing in parallel so the first paint includes both
    // without stacking latencies.
    final results = await Future.wait([
      api.get('/coach/messages').then<Object?>((r) => r.data).catchError((_) => null),
      api.get('/coach/briefing').then<Object?>((r) => r.data).catchError((_) => null),
    ]);

    final rawMessages = results[0];
    final rawBriefing = results[1];

    final messages = rawMessages is List
        ? rawMessages
            .map((m) => CoachMessage.fromJson(m as Map<String, dynamic>))
            .toList()
        : <CoachMessage>[];

    CoachBriefing? briefing;
    if (rawBriefing is Map<String, dynamic>) {
      try {
        briefing = CoachBriefing.fromJson(rawBriefing);
      } catch (_) {
        briefing = null;
      }
    }

    if (!mounted) return;
    state = state.copyWith(
      messages: messages,
      briefing: briefing,
      isLoading: false,
    );
  }

  Future<void> send(String content) async {
    if (content.trim().isEmpty) return;
    if (!mounted) return;
    state = state.copyWith(isSending: true);

    try {
      final api = _ref.read(apiServiceProvider);
      final resp = await api.post('/coach/message', data: {
        'content': content.trim(),
      });

      if (!mounted) return;
      state = state.copyWith(
        messages: [...state.messages,
          CoachMessage.fromJson(resp.data['user_message'] as Map<String, dynamic>),
          CoachMessage.fromJson(resp.data['assistant_message'] as Map<String, dynamic>),
        ],
        isSending: false,
      );
      ReviewService.recordMinorAction();
    } catch (_) {
      if (!mounted) return;
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
  bool _consentChecked = false;
  bool _consentGranted = false;

  @override
  void initState() {
    super.initState();
    _checkAiConsent();
  }

  Future<void> _checkAiConsent() async {
    final auth = ref.read(authServiceProvider);
    final hasConsent = await auth.hasAiConsent();
    if (hasConsent) {
      if (mounted) setState(() {
        _consentChecked = true;
        _consentGranted = true;
      });
      return;
    }
    // Show consent dialog
    if (!mounted) return;
    final agreed = await showAiConsentDialog(context);
    if (agreed) {
      await auth.setAiConsent();
    }
    if (mounted) setState(() {
      _consentChecked = true;
      _consentGranted = agreed;
    });
  }

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

  List<String> _dynamicPrompts() {
    // Lightweight, rules-based starters so the empty state still feels
    // aware-ish even when the briefing fails to load.
    final weekday = DateTime.now().weekday;
    final prompts = <String>[];
    if (weekday == DateTime.monday) {
      prompts.add('Help me plan this week');
    } else if (weekday == DateTime.sunday) {
      prompts.add('Debrief last week with me');
    } else {
      prompts.add('What should I focus on today?');
    }
    prompts.add('Am I on track with my goals?');
    prompts.add("I'm feeling overwhelmed");
    return prompts;
  }

  @override
  Widget build(BuildContext context) {
    final sub = ref.watch(subscriptionProvider);
    final chatState = ref.watch(_messagesProvider);

    if (chatState.messages.isNotEmpty) {
      _scrollToBottom();
    }

    // Show nothing while checking consent
    if (!_consentChecked) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.kiwi400),
        ),
      );
    }

    // If user declined AI consent, show explanation
    if (!_consentGranted) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome,
                      size: 48, color: AppColors.contentTertiary),
                  const SizedBox(height: 16),
                  Text(
                    'AI features require data consent',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.content,
                          fontWeight: FontWeight.w600,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'To use the AI Coach, Kinwii needs your permission to send goal and task data to our AI provider.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.contentSecondary,
                          height: 1.5,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _checkAiConsent,
                    child: const Text('Review & Agree'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Column(
        children: [
          // Header — matches Today/Goals style
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome,
                    size: 22, color: AppColors.kiwi500),
                const SizedBox(width: 8),
                Text(
                  'AI Coach',
                  style: Theme.of(context)
                      .textTheme
                      .headlineLarge
                      ?.copyWith(color: AppColors.content),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
        children: [
          Expanded(
            child: chatState.isLoading
                ? const Center(
                    child:
                        CircularProgressIndicator(color: AppColors.kiwi400))
                : _buildBody(context, chatState, sub.isPro),
          ),
          if (sub.isPro)
            _InputBar(
              controller: _inputCtrl,
              isSending: chatState.isSending,
              onSend: _send,
            )
          else
            _LockedInputBar(onTap: () => context.push('/pro')),
        ],
      ),
          ),
        ],
      ),
      ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, _ChatState chatState, bool isPro) {
    final briefing = chatState.briefing;
    final hasMessages = chatState.messages.isNotEmpty;

    // Case 1: no messages yet and no briefing → show the fallback empty state.
    if (!hasMessages && briefing == null) {
      return _EmptyState(
        onPrompt: isPro ? _sendPrompt : null,
        prompts: _dynamicPrompts(),
        isPro: isPro,
      );
    }

    // Case 2: briefing present — show it as the first item in the scroll,
    // followed by any chat history + typing indicator.
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: (briefing != null ? 1 : 0) +
          chatState.messages.length +
          (chatState.isSending ? 1 : 0),
      itemBuilder: (context, i) {
        var index = i;
        if (briefing != null) {
          if (index == 0) {
            return _BriefingCard(
              briefing: briefing,
              // Use server-provided briefing.isPro so day-1 free users see the
              // full briefing as a value teaser.
              isPro: briefing.isPro,
              onChipTap: _sendPrompt,
            );
          }
          index -= 1;
        }
        if (index == chatState.messages.length) {
          return const _TypingIndicator();
        }
        return _MessageBubble(message: chatState.messages[index]);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Daily briefing card — sits at the top of the chat scroll
// ---------------------------------------------------------------------------

class _BriefingCard extends StatelessWidget {
  const _BriefingCard({
    required this.briefing,
    required this.isPro,
    required this.onChipTap,
  });

  final CoachBriefing briefing;
  final bool isPro;
  final ValueChanged<String> onChipTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.kiwi50, Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.kiwi100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 16, color: AppColors.kiwi500),
              const SizedBox(width: 6),
              Text(
                "Today's briefing",
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.kiwi600,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            briefing.headline,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.content,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 10),
          if (isPro && briefing.body != null) ...[
            Text(
              briefing.body!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.contentSecondary,
                    height: 1.5,
                  ),
            ),
            if (briefing.followups.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final chip in briefing.followups)
                    _FollowupChip(
                      label: chip,
                      onTap: () => onChipTap(chip),
                    ),
                ],
              ),
            ],
          ] else ...[
            // Free-tier teaser
            const SizedBox(height: 4),
            Text(
              'Unlock the full briefing and chat with your coach to go deeper.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.contentSecondary,
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => GoRouter.of(context).push('/pro'),
                child: const Text('Unlock with Pro'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FollowupChip extends StatelessWidget {
  const _FollowupChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.kiwi200),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.kiwi700,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state with suggested prompts
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.onPrompt,
    required this.prompts,
    required this.isPro,
  });

  final ValueChanged<String>? onPrompt;
  final List<String> prompts;
  final bool isPro;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.auto_awesome,
              size: 56,
              color: AppColors.kiwi300,
            ),
            const SizedBox(height: 16),
            Text(
              'Your AI coach',
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
            if (!isPro)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => GoRouter.of(context).push('/pro'),
                  child: const Text('Unlock with Pro'),
                ),
              )
            else
              ...List.generate(
                prompts.length,
                (i) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed:
                          onPrompt == null ? null : () => onPrompt!(prompts[i]),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.borderSubtle),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                      child: Text(
                        prompts[i],
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
                color: Colors.black.withValues(alpha: 0.04),
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

class _LockedInputBar extends StatelessWidget {
  const _LockedInputBar({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          24, 12, 24, 12 + MediaQuery.of(context).padding.bottom,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.lock_outline,
                size: 16, color: AppColors.contentTertiary),
            const SizedBox(width: 8),
            Text(
              'Upgrade to Pro to chat with your coach',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.contentTertiary,
                  ),
            ),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.kiwi400,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Upgrade',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
