import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_queries.dart';
import '../../auth/providers/auth_provider.dart';

// ── Стейт (агрегат по кальянной) ──────────────────────────────────────────────

class LoungeRatingsState {
  final double? avgRating;
  final int count;
  final bool loading;
  final String? error;

  const LoungeRatingsState({
    this.avgRating,
    this.count = 0,
    this.loading = false,
    this.error,
  });

  LoungeRatingsState copyWith({
    double? avgRating,
    int? count,
    bool? loading,
    String? error,
    bool clearError = false,
    bool clearAvg = false,
  }) =>
      LoungeRatingsState(
        avgRating: clearAvg ? null : (avgRating ?? this.avgRating),
        count: count ?? this.count,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

// ── Нотификатор ───────────────────────────────────────────────────────────────

class LoungeRatingsNotifier extends StateNotifier<LoungeRatingsState> {
  final GraphQLClient _client;
  final String _loungeId;

  LoungeRatingsNotifier(this._client, this._loungeId)
      : super(const LoungeRatingsState(loading: true)) {
    fetch();
  }

  Future<void> fetch() async {
    if (!mounted) return;
    state = state.copyWith(loading: true, clearError: true, clearAvg: true);
    try {
      final result = await _client.query(QueryOptions(
        document: gql(kRatingStatsQuery),
        variables: {
          'targetType': 'lounge',
          'targetId': _loungeId,
        },
        fetchPolicy: FetchPolicy.networkOnly,
      ));
      if (!mounted) return;
      if (result.hasException) throw result.exception!;

      final stats =
          result.data?['ratingStats'] as Map<String, dynamic>?;
      final avg = (stats?['avgRating'] as num?)?.toDouble();
      final cnt = (stats?['count'] as int?) ?? 0;

      state = state.copyWith(
        avgRating: avg,
        count: cnt,
        loading: false,
        clearAvg: avg == null,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
          loading: false, error: e.toString(), clearAvg: true);
    }
  }
}

// ── Family-провайдер: один экземпляр на loungeId ──────────────────────────────

final loungeRatingsProvider = StateNotifierProvider.autoDispose
    .family<LoungeRatingsNotifier, LoungeRatingsState, String>(
  (ref, loungeId) {
    final client = ref.watch(graphqlClientProvider);
    return LoungeRatingsNotifier(client, loungeId);
  },
);
