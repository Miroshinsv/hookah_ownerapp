import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/graphql/graphql_queries.dart';
import '../../../core/graphql/ws_client.dart';
import '../../../core/storage/storage_service.dart';
import '../../auth/providers/auth_provider.dart';

class UnreadMessagesNotifier extends StateNotifier<Set<String>> {
  final StorageService _storage;
  final WsClient _ws;
  final String? _myUserId;
  StreamSubscription? _sub;

  UnreadMessagesNotifier(this._storage, this._ws, this._myUserId)
      : super(_storage.unreadOrderIds) {
    _subscribe();
  }

  void _subscribe() {
    _sub = _ws.subscribe(kNewMessageSubscription).listen((payload) {
      final data = payload['data']?['newMessage'] as Map<String, dynamic>?;
      if (data == null) return;
      final orderId = data['orderId'] as String?;
      final senderId = data['senderId'] as String?;
      if (orderId == null) return;
      final isFromSelf = _myUserId != null && senderId == _myUserId;
      if (!isFromSelf) {
        _markUnread(orderId);
      }
    });
  }

  Future<void> _markUnread(String orderId) async {
    await _storage.markOrderUnread(orderId);
    state = Set<String>.from(state)..add(orderId);
  }

  Future<void> markRead(String orderId) async {
    await _storage.markOrderRead(orderId);
    state = Set<String>.from(state)..remove(orderId);
  }

  /// Call on app resume to pick up unread orders set by the background service.
  Future<void> refreshFromStorage() async {
    await _storage.reload();
    final ids = _storage.unreadOrderIds;
    if (ids.isNotEmpty) {
      state = Set<String>.from(state)..addAll(ids);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final unreadMessagesProvider =
    StateNotifierProvider<UnreadMessagesNotifier, Set<String>>((ref) {
  final storage = ref.watch(storageServiceProvider);
  final ws = ref.watch(wsClientProvider);
  final auth = ref.watch(authProvider);
  return UnreadMessagesNotifier(storage, ws, auth.userId);
});
