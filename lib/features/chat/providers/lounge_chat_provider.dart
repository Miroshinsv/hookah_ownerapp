import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_queries.dart';
import '../../../shared/models/lounge_chat_message_model.dart';
import '../../auth/providers/auth_provider.dart';

class LoungeChatState {
  final List<LoungeChatMessageModel> messages;
  final bool loading;
  final String? error;

  const LoungeChatState({
    this.messages = const [],
    this.loading = false,
    this.error,
  });

  LoungeChatState copyWith({
    List<LoungeChatMessageModel>? messages,
    bool? loading,
    String? error,
    bool clearError = false,
  }) =>
      LoungeChatState(
        messages: messages ?? this.messages,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

class LoungeChatNotifier extends StateNotifier<LoungeChatState> {
  final GraphQLClient _client;
  final String loungeId;

  LoungeChatNotifier(this._client, this.loungeId)
      : super(const LoungeChatState());

  Future<void> fetch() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final result = await _client.query(QueryOptions(
        document: gql(kLoungeChatMessagesQuery),
        variables: {'loungeId': loungeId, 'limit': 100},
      ));
      if (result.hasException) throw result.exception!;

      final list =
          (result.data?['loungeChatMessages'] as List<dynamic>? ?? [])
              .map((e) =>
                  LoungeChatMessageModel.fromJson(e as Map<String, dynamic>))
              .toList();

      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      state = state.copyWith(messages: list, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  void addMessage(LoungeChatMessageModel msg) {
    final existing = state.messages.any((m) => m.messageId == msg.messageId);
    if (existing) return;
    final msgs = [...state.messages, msg];
    msgs.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    state = state.copyWith(messages: msgs);
  }

  Future<String?> send(String text) async {
    try {
      final result = await _client.mutate(MutationOptions(
        document: gql(kSendLoungeChatMessageMutation),
        variables: {'loungeId': loungeId, 'text': text},
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

final loungeChatProvider = StateNotifierProvider.autoDispose
    .family<LoungeChatNotifier, LoungeChatState, String>((ref, loungeId) {
  final client = ref.watch(graphqlClientProvider);
  final notifier = LoungeChatNotifier(client, loungeId);
  notifier.fetch();
  return notifier;
});
