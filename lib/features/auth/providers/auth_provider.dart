import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_client.dart';
import '../../../core/graphql/graphql_queries.dart';
import '../../../core/graphql/ws_client.dart';
import '../../../core/storage/storage_service.dart';

class AuthState {
  final String? token;
  final String? role;
  final String? loungeId;
  final String? userId;

  const AuthState({this.token, this.role, this.loungeId, this.userId});

  bool get isAuthenticated => token != null && token!.isNotEmpty;
  bool get isAdmin => role == 'admin';
  bool get isOwner => role == 'owner';
  bool get isStaff => role == 'staff';
  bool get canManageLounges => isAdmin || isOwner;
  bool get canManageStaff => isAdmin || isOwner;
  bool get canDeleteOrders => isAdmin;

  AuthState copyWith({
    String? token,
    String? role,
    String? loungeId,
    String? userId,
  }) =>
      AuthState(
        token: token ?? this.token,
        role: role ?? this.role,
        loungeId: loungeId ?? this.loungeId,
        userId: userId ?? this.userId,
      );
}

class AuthNotifier extends Notifier<AuthState> {
  late StorageService _storage;

  @override
  AuthState build() {
    _storage = ref.read(storageServiceProvider);
    return _loadFromStorage();
  }

  AuthState _loadFromStorage() {
    final token = _storage.token;
    if (token != null && token.isNotEmpty) {
      return AuthState(
        token: token,
        role: _storage.role,
        loungeId: _storage.loungeId,
        userId: _storage.userId,
      );
    }
    return const AuthState();
  }

  Future<String?> login(String userId, String password) async {
    final client = buildGraphQLClient('');
    final result = await client.mutate(MutationOptions(
      document: gql(kLoginMutation),
      variables: {'userId': userId, 'password': password},
    ));

    if (result.hasException) {
      final msg = result.exception?.graphqlErrors.firstOrNull?.message ??
          result.exception?.linkException?.toString() ??
          'Ошибка входа';
      return msg;
    }

    final data = result.data?['login'] as Map<String, dynamic>?;
    if (data == null) return 'Нет данных от сервера';

    final token = data['token'] as String?;
    final role = data['role'] as String?;
    final loungeId = data['loungeId'] as String?;

    if (token == null) return 'Токен не получен';

    await _storage.saveAuth(
      token: token,
      role: role ?? 'staff',
      loungeId: loungeId,
      userId: userId,
    );

    state = AuthState(
      token: token,
      role: role ?? 'staff',
      loungeId: loungeId,
      userId: userId,
    );
    return null;
  }

  Future<void> logout() async {
    await _storage.clearAuth();
    state = const AuthState();
  }
}

final storageServiceProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('Initialize with override in main');
});

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

final graphqlClientProvider = Provider<GraphQLClient>((ref) {
  final auth = ref.watch(authProvider);
  return buildGraphQLClient(auth.token ?? '');
});

final wsClientProvider = Provider<WsClient>((ref) {
  final auth = ref.watch(authProvider);
  final client = WsClient(auth.token ?? '');
  if (auth.isAuthenticated) {
    client.connect();
  }
  ref.onDispose(client.dispose);
  return client;
});
