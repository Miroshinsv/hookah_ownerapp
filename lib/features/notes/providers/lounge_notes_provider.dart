import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_queries.dart';
import '../../../features/users/providers/user_notes_provider.dart';
import '../../auth/providers/auth_provider.dart';

// ── Стейт ─────────────────────────────────────────────────────────────────────

class LoungeNotesState {
  final List<NoteItem> items;
  final bool loading;
  final String? error;
  /// null — ещё не проверяли; true/false — результат isNotesEnabled.
  final bool? isEnabled;

  const LoungeNotesState({
    this.items = const [],
    this.loading = false,
    this.error,
    this.isEnabled,
  });

  /// Количество записок, созданных после [from] (для дашборд-статистики).
  int countFrom(DateTime from) =>
      items.where((n) => n.createdAt.isAfter(from)).length;
}

// ── Нотификатор ───────────────────────────────────────────────────────────────

class LoungeNotesNotifier extends StateNotifier<LoungeNotesState> {
  final GraphQLClient _client;
  final String _loungeId;

  LoungeNotesNotifier(this._client, this._loungeId)
      : super(const LoungeNotesState(loading: true)) {
    fetch();
  }

  Future<void> fetch() async {
    if (!mounted) return;
    state = const LoungeNotesState(loading: true);
    try {
      // Сначала проверяем, включён ли сервис записок
      final enabledResult = await _client.query(QueryOptions(
        document: gql(kIsNotesEnabledQuery),
        variables: {'loungeId': _loungeId},
        fetchPolicy: FetchPolicy.networkOnly,
      ));
      if (!mounted) return;
      if (enabledResult.hasException) throw enabledResult.exception!;

      final isEnabled =
          enabledResult.data?['isNotesEnabled'] as bool? ?? false;

      if (!isEnabled) {
        state = const LoungeNotesState(isEnabled: false);
        return;
      }

      // Сервис включён — загружаем записки
      final result = await _client.query(QueryOptions(
        document: gql(kLoungeEntityNotesQuery),
        variables: {'loungeId': _loungeId, 'limit': 200},
        fetchPolicy: FetchPolicy.networkOnly,
      ));
      if (!mounted) return;
      if (result.hasException) throw result.exception!;

      final data = result.data?['notes'] as Map<String, dynamic>?;
      final raw = data?['items'] as List<dynamic>? ?? [];
      final items = raw.map(_parseNote).toList();
      state = LoungeNotesState(items: items, isEnabled: true);
    } catch (e) {
      if (!mounted) return;
      state = LoungeNotesState(error: e.toString());
    }
  }

  Future<String?> createNote(String text) async {
    try {
      final result = await _client.mutate(MutationOptions(
        document: gql(kCreateNoteMutation),
        variables: {
          'loungeId': _loungeId,
          'entityType': 'lounge',
          'entityId': _loungeId,
          'text': text,
        },
      ));
      if (result.hasException) {
        return result.exception?.graphqlErrors.firstOrNull?.message ?? 'Ошибка';
      }
      final raw = result.data?['createNote'] as Map<String, dynamic>?;
      if (raw != null && mounted) {
        state = LoungeNotesState(
          items: [_parseNote(raw), ...state.items],
          isEnabled: true,
        );
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> deleteNote(String noteId) async {
    try {
      final result = await _client.mutate(MutationOptions(
        document: gql(kDeleteNoteMutation),
        variables: {'noteId': noteId, 'loungeId': _loungeId},
      ));
      if (result.hasException) {
        return result.exception?.graphqlErrors.firstOrNull?.message ?? 'Ошибка';
      }
      if (mounted) {
        state = LoungeNotesState(
          items: state.items.where((n) => n.noteId != noteId).toList(),
          isEnabled: true,
        );
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  static NoteItem _parseNote(dynamic e) {
    final m = e as Map<String, dynamic>;
    return NoteItem(
      noteId: m['noteId'] as String,
      authorName: m['authorName'] as String?,
      text: m['text'] as String,
      createdAt: DateTime.parse(m['createdAt'] as String),
    );
  }
}

// ── Family-провайдер: один экземпляр на loungeId ──────────────────────────────

final loungeNotesProvider = StateNotifierProvider.autoDispose
    .family<LoungeNotesNotifier, LoungeNotesState, String>(
  (ref, loungeId) {
    final client = ref.watch(graphqlClientProvider);
    return LoungeNotesNotifier(client, loungeId);
  },
);
