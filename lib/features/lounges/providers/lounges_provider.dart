import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_queries.dart';
import '../../../shared/models/lounge_model.dart';
import '../../auth/providers/auth_provider.dart';

class LoungesState {
  final List<LoungeModel> lounges;
  final bool loading;
  final String? error;

  const LoungesState({
    this.lounges = const [],
    this.loading = false,
    this.error,
  });

  LoungesState copyWith({
    List<LoungeModel>? lounges,
    bool? loading,
    String? error,
    bool clearError = false,
  }) =>
      LoungesState(
        lounges: lounges ?? this.lounges,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

class LoungesNotifier extends StateNotifier<LoungesState> {
  final GraphQLClient _client;

  LoungesNotifier(this._client) : super(const LoungesState());

  Future<void> fetch() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final result = await _client.query(QueryOptions(
        document: gql(kLoungesQuery),
      ));
      if (result.hasException) throw result.exception!;

      final list = (result.data?['lounges'] as List<dynamic>? ?? [])
          .map((e) => LoungeModel.fromJson(e as Map<String, dynamic>))
          .toList();

      list.sort((a, b) => a.name.compareTo(b.name));
      state = state.copyWith(lounges: list, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<String?> createLounge(Map<String, dynamic> vars) async {
    try {
      final result = await _client.mutate(MutationOptions(
        document: gql(kCreateLoungeMutation),
        variables: vars,
      ));
      if (result.hasException) {
        return result.exception?.graphqlErrors.firstOrNull?.message ??
            'Ошибка создания';
      }
      await fetch();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> updateLounge(Map<String, dynamic> vars) async {
    try {
      final result = await _client.mutate(MutationOptions(
        document: gql(kUpdateLoungeMutation),
        variables: vars,
      ));
      if (result.hasException) {
        return result.exception?.graphqlErrors.firstOrNull?.message ??
            'Ошибка обновления';
      }
      await fetch();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> deleteLounge(String loungeId) async {
    try {
      final result = await _client.mutate(MutationOptions(
        document: gql(kDeleteLoungeMutation),
        variables: {'loungeId': loungeId},
      ));
      if (result.hasException) {
        return result.exception?.graphqlErrors.firstOrNull?.message ??
            'Ошибка удаления';
      }
      state = state.copyWith(
        lounges: state.lounges.where((l) => l.id != loungeId).toList(),
      );
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> setOwner(String loungeId, String ownerUserId) async {
    try {
      final result = await _client.mutate(MutationOptions(
        document: gql(kSetLoungeOwnerMutation),
        variables: {'loungeId': loungeId, 'ownerUserId': ownerUserId},
      ));
      if (result.hasException) {
        return result.exception?.graphqlErrors.firstOrNull?.message ??
            'Ошибка назначения';
      }
      await fetch();
      return null;
    } catch (e) {
      return e.toString();
    }
  }
}

final loungesProvider =
    StateNotifierProvider.autoDispose<LoungesNotifier, LoungesState>((ref) {
  final client = ref.watch(graphqlClientProvider);
  final notifier = LoungesNotifier(client);
  notifier.fetch();
  return notifier;
});
