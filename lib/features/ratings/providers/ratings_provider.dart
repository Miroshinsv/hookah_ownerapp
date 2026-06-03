import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_queries.dart';
import '../../auth/providers/auth_provider.dart';

// ── Запись с оценкой и датой ───────────────────────────────────────────────────

class RatingEntry {
  final double score;
  final DateTime createdAt;
  const RatingEntry({required this.score, required this.createdAt});
}

// ── Стейт ─────────────────────────────────────────────────────────────────────

class LoungeRatingsState {
  final List<RatingEntry> items;
  final bool loading;
  final String? error;

  const LoungeRatingsState({
    this.items = const [],
    this.loading = false,
    this.error,
  });

  /// Avg + count filtered to entries after [from].
  ({double? avg, int count}) statsFrom(DateTime from) {
    final filtered =
        items.where((r) => r.createdAt.isAfter(from)).toList();
    final count = filtered.length;
    final avg = count > 0
        ? filtered.map((r) => r.score).reduce((a, b) => a + b) / count
        : null;
    return (avg: avg, count: count);
  }
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
    state = const LoungeRatingsState(loading: true);
    try {
      final result = await _client.query(QueryOptions(
        document: gql(kFilteredRatingsQuery),
        variables: {
          'targetType': 'lounge',
          'targetId': _loungeId,
          'limit': 500,
        },
        fetchPolicy: FetchPolicy.networkOnly,
      ));
      if (!ref.mounted) return;
      if (result.hasException) throw result.exception!;

      final raw =
          result.data?['allRatings'] as List<dynamic>? ?? [];
      final items = raw.map((e) {
        final map = e as Map<String, dynamic>;
        return RatingEntry(
          score: (map['score'] as num).toDouble(),
          createdAt: DateTime.parse(map['createdAt'] as String),
        );
      }).toList();

      state = LoungeRatingsState(items: items);
    } catch (e) {
      if (!ref.mounted) return;
      state = LoungeRatingsState(error: e.toString());
    }
  }
}

// ── Family-провайдер: один экземпляр на loungeId ──────────────────────────────

final loungeRatingsProvider = NotifierProvider.autoDispose
    .family<LoungeRatingsNotifier, LoungeRatingsState, String>(
  (loungeId) => LoungeRatingsNotifier(loungeId),
);
