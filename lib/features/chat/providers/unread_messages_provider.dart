import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_queries.dart';
import '../../../core/graphql/ws_client.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/storage/storage_service.dart';
import '../../../shared/models/message_model.dart';
import '../../../shared/models/order_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../dashboard/providers/dashboard_provider.dart';

/// Tracks which orderId is currently open in ChatScreen.
/// Used to suppress push notifications when the user is already viewing that chat.
final activeChatOrderIdProvider = StateProvider<String?>((ref) => null);

const _staffRoles = {
  'admin', 'owner', 'hookah_master', 'hostess', 'waiter', 'staff'
};

class UnreadMessagesNotifier extends StateNotifier<Set<String>> {
  final StorageService _storage;
  final WsClient _ws;
  final String? _myUserId;
  final Ref _ref;
  StreamSubscription? _sub;
  Timer? _pollTimer;
  bool _disposed = false;
  List<String> _activeOrderIds = [];

  UnreadMessagesNotifier(this._storage, this._ws, this._myUserId, this._ref)
      : super(_storage.unreadOrderIds) {
    _subscribeWs();
    _schedulePoll();
  }

  void syncActiveOrders(List<OrderModel> orders) {
    _activeOrderIds = orders
        .where((o) =>
            o.status == OrderStatus.newOrder ||
            o.status == OrderStatus.inProgress)
        .map((o) => o.id)
        .toList();
  }

  // ── WebSocket fast path ──────────────────────────────────────────────────

  void _subscribeWs() {
    _sub = _ws.subscribe(kNewMessageSubscription).listen((payload) {
      final data = payload['data']?['newMessage'] as Map<String, dynamic>?;
      if (data == null) return;
      final orderId = data['orderId'] as String?;
      final senderId = data['senderId'] as String?;
      final senderRole = data['senderRole'] as String?;
      final text = data['text'] as String? ?? '';
      if (orderId == null) return;
      final isFromSelf = _myUserId != null && senderId == _myUserId;
      final isFromStaff = senderRole != null && _staffRoles.contains(senderRole);
      if (!isFromSelf && !isFromStaff) {
        _notify(orderId, text);
      }
    });
  }

  // ── HTTP polling fallback (every 30 s) ──────────────────────────────────

  void _schedulePoll() {
    // Short initial delay so dashboardProvider has time to populate _activeOrderIds.
    Future.delayed(const Duration(seconds: 10), () {
      if (_disposed) return;
      _pollMessages();
      _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (!_disposed) _pollMessages();
      });
    });
  }

  Future<void> _pollMessages() async {
    try {
      final active = List<String>.from(_activeOrderIds);
      if (active.isEmpty) return;

      final client = _ref.read(graphqlClientProvider);

      for (final orderId in active) {
        if (_disposed) return;
        await _pollOrder(client, orderId);
      }
    } catch (e) {
      debugPrint('UnreadMessagesNotifier._pollMessages: $e');
    }
  }

  Future<void> _pollOrder(GraphQLClient client, String orderId) async {
    try {
      final result = await client.query(QueryOptions(
        document: gql(kMessagesQuery),
        variables: {'orderId': orderId},
        fetchPolicy: FetchPolicy.networkOnly,
      ));
      if (result.hasException) return;

      final messages = (result.data?['messages'] as List<dynamic>? ?? [])
          .map((e) => MessageModel.fromJson(e as Map<String, dynamic>))
          .toList();
      if (messages.isEmpty) return;

      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      final lastNotifTs = _storage.notifMsgTs(orderId);

      // Always advance the stored timestamp to the latest message.
      await _storage.setNotifMsgTs(orderId, messages.last.createdAt);

      // First poll — just record state, no notification.
      if (lastNotifTs == null) return;

      // Find new messages from non-staff / non-self senders.
      final newMsgs = messages.where((m) {
        if (!m.createdAt.isAfter(lastNotifTs)) return false;
        if (_myUserId != null && m.senderId == _myUserId) return false;
        if (m.senderRole != null && _staffRoles.contains(m.senderRole)) {
          return false;
        }
        return true;
      }).toList();

      if (newMsgs.isEmpty) return;

      await _notify(orderId, newMsgs.last.text);
    } catch (e) {
      debugPrint('UnreadMessagesNotifier._pollOrder($orderId): $e');
    }
  }

  // ── Shared logic ─────────────────────────────────────────────────────────

  Future<void> _notify(String orderId, String text) async {
    await _storage.markOrderUnread(orderId);
    if (!_disposed) state = Set<String>.from(state)..add(orderId);

    final activeChat = _ref.read(activeChatOrderIdProvider);
    if (activeChat != orderId) {
      await NotificationService.showNewMessage(orderId, text);
    }
  }

  Future<void> markRead(String orderId) async {
    await _storage.markOrderRead(orderId);
    // Also reset the notification timestamp so the next poll doesn't
    // re-notify about messages the user just read.
    final msgs = <MessageModel>[];
    try {
      final client = _ref.read(graphqlClientProvider);
      final result = await client.query(QueryOptions(
        document: gql(kMessagesQuery),
        variables: {'orderId': orderId},
        fetchPolicy: FetchPolicy.cacheFirst,
      ));
      if (!result.hasException) {
        msgs.addAll(
          (result.data?['messages'] as List<dynamic>? ?? [])
              .map((e) => MessageModel.fromJson(e as Map<String, dynamic>)),
        );
      }
    } catch (_) {}
    if (msgs.isNotEmpty) {
      msgs.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      await _storage.setNotifMsgTs(orderId, msgs.last.createdAt);
    }
    if (!_disposed) state = Set<String>.from(state)..remove(orderId);
  }

  /// Call on app resume to pick up unread orders set by the background service.
  Future<void> refreshFromStorage() async {
    await _storage.reload();
    final ids = _storage.unreadOrderIds;
    if (ids.isNotEmpty && !_disposed) {
      state = Set<String>.from(state)..addAll(ids);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }
}

final unreadMessagesProvider =
    StateNotifierProvider<UnreadMessagesNotifier, Set<String>>((ref) {
  final storage = ref.watch(storageServiceProvider);
  final ws = ref.watch(wsClientProvider);
  final auth = ref.watch(authProvider);
  final notifier = UnreadMessagesNotifier(storage, ws, auth.userId, ref);

  // Keep dashboardProvider alive and sync active orders so _pollMessages
  // always has a fresh list regardless of which screen is open.
  ref.listen<DashboardState>(
    dashboardProvider,
    (_, next) => notifier.syncActiveOrders(next.orders),
    fireImmediately: true,
  );

  return notifier;
});
