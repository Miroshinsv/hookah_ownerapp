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

class LoungeRatingsNotifier extends Notifier<LoungeRatingsState> {
  final String _loungeId;
  late GraphQLClient _client;

  LoungeRatingsNotifier(this._loungeId);

  @override
  LoungeRatingsState build() {
    _client = ref.watch(graphqlClientProvider);
    Future.microtask(fetch);
    return const LoungeRatingsState(loading: true);
  }

  Future<void> fetch() async {
    if (!ref.mounted) return;
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
      if (!ref.mounted) return;
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
      if (!ref.mounted) return;
      state = state.copyWith(
          loading: false, error: e.toString(), clearAvg: true);
    }
  }
}

// ── Family-провайдер: один экземпляр на loungeId ──────────────────────────────

final loungeRatingsProvider = NotifierProvider.autoDispose
    .family<LoungeRatingsNotifier, LoungeRatingsState, String>(
  (loungeId) => LoungeRatingsNotifier(loungeId),
);
