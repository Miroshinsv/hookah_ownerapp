import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_queries.dart';
import '../../../shared/models/rating_model.dart';
import '../../auth/providers/auth_provider.dart';

class RatingsState {
  final List<RatingModel> ratings;
  final bool loading;
  final String? error;

  const RatingsState({
    this.ratings = const [],
    this.loading = false,
    this.error,
  });

  List<RatingModel> _forPeriod(DateTime from) =>
      ratings.where((r) => r.createdAt.isAfter(from)).toList();

  List<RatingModel> get todayRatings {
    final now = DateTime.now();
    return _forPeriod(DateTime(now.year, now.month, now.day));
  }

  List<RatingModel> get weekRatings {
    final now = DateTime.now();
    final s = now.subtract(Duration(days: now.weekday - 1));
    return _forPeriod(DateTime(s.year, s.month, s.day));
  }

  List<RatingModel> get monthRatings {
    final now = DateTime.now();
    return _forPeriod(DateTime(now.year, now.month, 1));
  }

  double? _avg(List<RatingModel> list) {
    if (list.isEmpty) return null;
    return list.fold(0.0, (s, r) => s + r.score) / list.length;
  }

  double? get todayAvg => _avg(todayRatings);
  double? get weekAvg => _avg(weekRatings);
  double? get monthAvg => _avg(monthRatings);

  RatingsState copyWith({
    List<RatingModel>? ratings,
    bool? loading,
    String? error,
    bool clearError = false,
  }) =>
      RatingsState(
        ratings: ratings ?? this.ratings,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

class RatingsNotifier extends StateNotifier<RatingsState> {
  final GraphQLClient _client;

  RatingsNotifier(this._client) : super(const RatingsState()) {
    fetch();
  }

  Future<void> fetch() async {
    if (!mounted) return;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final result = await _client.query(QueryOptions(
        document: gql(kAllRatingsQuery),
        variables: const {'limit': 1000},
        fetchPolicy: FetchPolicy.networkOnly,
      ));
      if (!mounted) return;
      if (result.hasException) throw result.exception!;

      final list = (result.data?['allRatings'] as List<dynamic>? ?? [])
          .map((e) => RatingModel.fromJson(e as Map<String, dynamic>))
          .toList();

      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      state = state.copyWith(ratings: list, loading: false);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: e.toString());
    }
  }
}

final ratingsProvider =
    StateNotifierProvider.autoDispose<RatingsNotifier, RatingsState>((ref) {
  final client = ref.watch(graphqlClientProvider);
  return RatingsNotifier(client);
});
