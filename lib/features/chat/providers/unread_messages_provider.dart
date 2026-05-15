import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/graphql/graphql_queries.dart';
import '../../../core/graphql/ws_client.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/storage/storage_service.dart';
import '../../auth/providers/auth_provider.dart';

/// Tracks which orderId is currently open in ChatScreen.
/// Used to suppress push notifications when the user is already viewing that chat.
final activeChatOrderIdProvider = StateProvider<String?>((ref) => null);

class UnreadMessagesNotifier extends StateNotifier<Set<String>> {
  final StorageService _storage;
  final WsClient _ws;
  final String? _myUserId;
  final Ref _ref;
  StreamSubscription? _sub;

  UnreadMessagesNotifier(this._storage, this._ws, this._myUserId, this._ref)
      : super(_storage.unreadOrderIds) {
    _subscribe();
  }

  void _subscribe() {
    _sub = _ws.subscribe(kNewMessageSubscription).listen((payload) {
      final data = payload['data']?['newMessage'] as Map<String, dynamic>?;
      if (data == null) return;
      final orderId = data['orderId'] as String?;
      final senderId = data['senderId'] as String?;
      final text = data['text'] as String? ?? '';
      if (orderId == null) return;
      final isFromSelf = _myUserId != null && senderId == _myUserId;
      if (!isFromSelf) {
        _markUnread(orderId, text);
      }
    });
  }

  Future<void> _markUnread(String orderId, String text) async {
    await _storage.markOrderUnread(orderId);
    state = Set<String>.from(state)..add(orderId);

    // Show push only if user is NOT currently viewing this chat.
    final activeChat = _ref.read(activeChatOrderIdProvider);
    if (activeChat != orderId) {
      await NotificationService.showNewMessage(orderId, text);
    }
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
  return UnreadMessagesNotifier(storage, ws, auth.userId, ref);
});
