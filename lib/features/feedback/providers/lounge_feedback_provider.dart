import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_queries.dart';
import '../../auth/providers/auth_provider.dart';

// ── Запись отзыва ─────────────────────────────────────────────────────────────

class FeedbackEntry {
  final double score;
  final DateTime createdAt;
  const FeedbackEntry({required this.score, required this.createdAt});
}

// ── Стейт ─────────────────────────────────────────────────────────────────────

class LoungeFeedbackState {
  final List<FeedbackEntry> items;
  final bool loading;
  final String? error;

  const LoungeFeedbackState({
    this.items = const [],
    this.loading = false,
    this.error,
  });

  /// Avg + count filtered to entries after [from].
  ({double? avg, int count}) statsFrom(DateTime from) {
    final filtered =
        items.where((f) => f.createdAt.isAfter(from)).toList();
    final count = filtered.length;
    final avg = count > 0
        ? filtered.map((f) => f.score).reduce((a, b) => a + b) / count
        : null;
    return (avg: avg, count: count);
  }
}

// ── Нотификатор ───────────────────────────────────────────────────────────────

class LoungeFeedbackNotifier extends Notifier<LoungeFeedbackState> {
  final String _loungeId;
  late GraphQLClient _client;

  LoungeFeedbackNotifier(this._loungeId);

  @override
  LoungeFeedbackState build() {
    _client = ref.watch(graphqlClientProvider);
    Future.microtask(fetch);
    return const LoungeFeedbackState(loading: true);
  }

  Future<void> fetch() async {
    if (!ref.mounted) return;
    state = const LoungeFeedbackState(loading: true);
    try {
      final result = await _client.query(QueryOptions(
        document: gql(kLoungeFeedbacksQuery),
        variables: {'loungeId': _loungeId, 'limit': 200},
        fetchPolicy: FetchPolicy.networkOnly,
      ));
      if (!ref.mounted) return;
      if (result.hasException) throw result.exception!;

      final raw =
          result.data?['loungeFeedbacks'] as List<dynamic>? ?? [];
      final items = raw.map((e) {
        final map = e as Map<String, dynamic>;
        return FeedbackEntry(
          score: (map['score'] as num).toDouble(),
          createdAt: DateTime.parse(map['createdAt'] as String),
        );
      }).toList();

      state = LoungeFeedbackState(items: items);
    } catch (e) {
      if (!ref.mounted) return;
      state = LoungeFeedbackState(error: e.toString());
    }
  }
}

// ── Family-провайдер: один экземпляр на loungeId ──────────────────────────────

final loungeFeedbackProvider = NotifierProvider.autoDispose
    .family<LoungeFeedbackNotifier, LoungeFeedbackState, String>(
  (loungeId) => LoungeFeedbackNotifier(loungeId),
);
