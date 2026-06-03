import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_queries.dart';
import '../../auth/providers/auth_provider.dart';

// ── Модель записки ────────────────────────────────────────────────────────────

class NoteItem {
  final String noteId;
  final String? authorName;
  final String text;
  final DateTime createdAt;

  const NoteItem({
    required this.noteId,
    this.authorName,
    required this.text,
    required this.createdAt,
  });
}

// ── Стейт ─────────────────────────────────────────────────────────────────────

class UserNotesState {
  final List<NoteItem> items;
  final bool loading;
  final String? error;
  /// null — ещё не проверяли; true/false — результат isNotesEnabled.
  final bool? isEnabled;

  const UserNotesState({
    this.items = const [],
    this.loading = false,
    this.error,
    this.isEnabled,
  });
}

// ── Ключ family-провайдера ─────────────────────────────────────────────────────

typedef UserNotesKey = ({String loungeId, String userId});

// ── Нотификатор ───────────────────────────────────────────────────────────────

class UserNotesNotifier extends Notifier<UserNotesState> {
  final UserNotesKey _key;
  late GraphQLClient _client;

  UserNotesNotifier(this._key);

  @override
  UserNotesState build() {
    _client = ref.watch(graphqlClientProvider);
    Future.microtask(fetch);
    return const UserNotesState(loading: true);
  }

  Future<void> fetch() async {
    if (!ref.mounted) return;
    state = const UserNotesState(loading: true);
    try {
      // Сначала проверяем, включён ли сервис записок
      final enabledResult = await _client.query(QueryOptions(
        document: gql(kIsNotesEnabledQuery),
        variables: {'loungeId': _key.loungeId},
        fetchPolicy: FetchPolicy.networkOnly,
      ));
      if (!ref.mounted) return;
      if (enabledResult.hasException) throw enabledResult.exception!;

      final isEnabled =
          enabledResult.data?['isNotesEnabled'] as bool? ?? false;

      if (!isEnabled) {
        state = const UserNotesState(isEnabled: false);
        return;
      }

      // Сервис включён — загружаем записки
      final result = await _client.query(QueryOptions(
        document: gql(kUserNotesQuery),
        variables: {
          'loungeId': _key.loungeId,
          'userId': _key.userId,
          'limit': 50,
        },
        fetchPolicy: FetchPolicy.networkOnly,
      ));
      if (!ref.mounted) return;
      if (result.hasException) throw result.exception!;

      final data = result.data?['notes'] as Map<String, dynamic>?;
      final raw = data?['items'] as List<dynamic>? ?? [];
      final items = raw.map(_parseNote).toList();
      state = UserNotesState(items: items, isEnabled: true);
    } catch (e) {
      if (!ref.mounted) return;
      state = UserNotesState(error: e.toString());
    }
  }

  Future<String?> createNote(String text) async {
    try {
      final result = await _client.mutate(MutationOptions(
        document: gql(kCreateNoteMutation),
        variables: {
          'loungeId': _key.loungeId,
          'entityType': 'user',
          'entityId': _key.userId,
          'text': text,
        },
      ));
      if (result.hasException) {
        return result.exception?.graphqlErrors.firstOrNull?.message ?? 'Ошибка';
      }
      final raw = result.data?['createNote'] as Map<String, dynamic>?;
      if (raw != null && ref.mounted) {
        state = UserNotesState(
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
        variables: {'noteId': noteId, 'loungeId': _key.loungeId},
      ));
      if (result.hasException) {
        return result.exception?.graphqlErrors.firstOrNull?.message ?? 'Ошибка';
      }
      if (ref.mounted) {
        state = UserNotesState(
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
      createdAt: m['createdAt'] != null
          ? DateTime.parse(m['createdAt'] as String)
          : DateTime.now(),
    );
  }
}

// ── Family-провайдер: один экземпляр на (loungeId, userId) ────────────────────

final userNotesProvider = NotifierProvider.autoDispose
    .family<UserNotesNotifier, UserNotesState, UserNotesKey>(
  (key) => UserNotesNotifier(key),
);
