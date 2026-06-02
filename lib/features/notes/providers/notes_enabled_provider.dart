import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_queries.dart';
import '../../auth/providers/auth_provider.dart';

/// Лёгкий провайдер: только проверяет isNotesEnabled без загрузки самих записок.
final isNotesEnabledProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, loungeId) async {
  final client = ref.watch(graphqlClientProvider);
  final result = await client.query(QueryOptions(
    document: gql(kIsNotesEnabledQuery),
    variables: {'loungeId': loungeId},
    fetchPolicy: FetchPolicy.networkOnly,
  ));
  if (result.hasException) return false;
  return result.data?['isNotesEnabled'] as bool? ?? false;
});
