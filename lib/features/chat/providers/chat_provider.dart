import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_queries.dart';
import '../../../shared/models/message_model.dart';
import '../../auth/providers/auth_provider.dart';

class ChatState {
  final List<MessageModel> messages;
  final bool loading;
  final String? error;

  const ChatState({
    this.messages = const [],
    this.loading = false,
    this.error,
  });

  ChatState copyWith({
    List<MessageModel>? messages,
    bool? loading,
    String? error,
    bool clearError = false,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

class ChatNotifier extends Notifier<ChatState> {
  final String _orderId;
  late GraphQLClient _client;

  ChatNotifier(this._orderId);

  @override
  ChatState build() {
    _client = ref.watch(graphqlClientProvider);
    Future.microtask(fetch);
    return const ChatState();
  }

  Future<void> fetch() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final result = await _client.query(QueryOptions(
        document: gql(kMessagesQuery),
        variables: {'orderId': _orderId},
      ));
      if (result.hasException) throw result.exception!;

      final list = (result.data?['messages'] as List<dynamic>? ?? [])
          .map((e) => MessageModel.fromJson(e as Map<String, dynamic>))
          .toList();

      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      state = state.copyWith(messages: list, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  void addMessage(MessageModel msg) {
    final existing = state.messages.any((m) => m.id == msg.id);
    if (existing) return;
    final msgs = [...state.messages, msg];
    msgs.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    state = state.copyWith(messages: msgs);
  }

  Future<String?> send(String text) async {
    try {
      final result = await _client.mutate(MutationOptions(
        document: gql(kSendMessageMutation),
        variables: {'orderId': _orderId, 'text': text},
      ));
      if (result.hasException) {
        return result.exception?.graphqlErrors.firstOrNull?.message ??
            'Ошибка отправки';
      }
      await fetch();
      return null;
    } catch (e) {
      return e.toString();
    }
  }
}

final chatProviderFamily = NotifierProvider.autoDispose
    .family<ChatNotifier, ChatState, String>(
  (orderId) => ChatNotifier(orderId),
);
