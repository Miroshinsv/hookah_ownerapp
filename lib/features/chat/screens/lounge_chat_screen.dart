import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/graphql/graphql_queries.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/lounge_chat_message_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/lounge_chat_provider.dart';
import '../providers/lounge_unread_provider.dart';

class LoungeChatScreen extends ConsumerStatefulWidget {
  final String loungeId;
  final String loungeName;

  const LoungeChatScreen({
    super.key,
    required this.loungeId,
    required this.loungeName,
  });

  @override
  ConsumerState<LoungeChatScreen> createState() => _LoungeChatScreenState();
}

class _LoungeChatScreenState extends ConsumerState<LoungeChatScreen> {
  final _scrollCtrl = ScrollController();
  final _textCtrl = TextEditingController();
  StreamSubscription? _sub;
  Timer? _pollTimer;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(activeLoungeChatIdProvider.notifier).set(widget.loungeId);
      ref.read(loungeUnreadProvider.notifier).markRead(widget.loungeId);
      _startSubscription();
      _startPolling();
    });
  }

  void _startSubscription() {
    final wsClient = ref.read(wsClientProvider);
    _sub = wsClient
        .subscribe(kNewLoungeChatMessageSubscription,
            variables: {'loungeId': widget.loungeId})
        .listen((payload) {
      final data =
          payload['data']?['newLoungeChatMessage'] as Map<String, dynamic>?;
      if (data == null || !mounted) return;
      final msg = LoungeChatMessageModel(
        messageId: '${DateTime.now().millisecondsSinceEpoch}',
        senderId: data['senderId'] as String?,
        senderRole: data['senderRole'] as String?,
        text: data['text'] as String? ?? '',
        createdAt: DateTime.now(),
      );
      ref.read(loungeChatProvider(widget.loungeId).notifier).addMessage(msg);
    });
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        ref.read(loungeChatProvider(widget.loungeId).notifier).fetch();
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    _textCtrl.clear();

    final err = await ref
        .read(loungeChatProvider(widget.loungeId).notifier)
        .send(text);

    if (mounted) {
      setState(() => _sending = false);
      if (err != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err)));
        _textCtrl.text = text;
      } else {
        _scrollToBottom();
      }
    }
  }

  @override
  void dispose() {
    ref.read(activeLoungeChatIdProvider.notifier).set(null);
    _sub?.cancel();
    _pollTimer?.cancel();
    _scrollCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(loungeChatProvider(widget.loungeId));
    final auth = ref.watch(authProvider);
    final myUserId = auth.userId;

    ref.listen(loungeChatProvider(widget.loungeId), (prev, next) {
      final prevLast = prev?.messages.lastOrNull?.messageId;
      final nextLast = next.messages.lastOrNull?.messageId;
      if (nextLast != null && nextLast != prevLast) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text('Чат — ${widget.loungeName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(loungeChatProvider(widget.loungeId).notifier).fetch(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (state.loading && state.messages.isEmpty)
            const Expanded(
              child: Center(
                  child: CircularProgressIndicator(color: AppColors.gold)),
            )
          else if (state.error != null && state.messages.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.red, size: 40),
                      const SizedBox(height: 12),
                      Text(
                        state.error!,
                        style: const TextStyle(
                            color: AppColors.red, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => ref
                            .read(loungeChatProvider(widget.loungeId).notifier)
                            .fetch(),
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                color: AppColors.gold,
                onRefresh: () => ref
                    .read(loungeChatProvider(widget.loungeId).notifier)
                    .fetch(),
                child: state.messages.isEmpty
                    ? const Center(
                        child: Text(
                          'Сообщений нет',
                          style: TextStyle(color: AppColors.muted),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(12),
                        itemCount: state.messages.length,
                        itemBuilder: (ctx, i) {
                          final msg = state.messages[i];
                          final isMine = msg.senderId == myUserId;
                          return _MessageBubble(
                            message: msg,
                            isMine: isMine,
                          );
                        },
                      ),
              ),
            ),
          _InputBar(
            controller: _textCtrl,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final LoungeChatMessageModel message;
  final bool isMine;

  const _MessageBubble({required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('HH:mm');
    final roleLabel = _roleLabel(message.senderRole);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMine
              ? AppColors.gold.withValues(alpha: 0.2)
              : AppColors.surface2,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isMine ? 14 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 14),
          ),
          border: Border.all(
            color: isMine
                ? AppColors.gold.withValues(alpha: 0.3)
                : AppColors.border,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (roleLabel != null)
              Text(
                roleLabel,
                style: TextStyle(
                  color: isMine ? AppColors.gold : AppColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            const SizedBox(height: 2),
            Text(
              message.text,
              style: const TextStyle(color: AppColors.text, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              df.format(message.createdAt.toLocal()),
              style: const TextStyle(color: AppColors.muted, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  String? _roleLabel(String? role) => switch (role) {
        'admin' => 'Администратор',
        'owner' => 'Владелец',
        'hookah_master' => 'Кальянный мастер',
        'hostess' => 'Хостес',
        'waiter' => 'Официант',
        'staff' => 'Сотрудник',
        'user' => 'Посетитель',
        _ => role,
      };
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 8,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Введите сообщение...',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
              ),
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.newline,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onSend,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.gold,
                borderRadius: BorderRadius.circular(21),
              ),
              child: sending
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Icon(Icons.send, color: Colors.black, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
