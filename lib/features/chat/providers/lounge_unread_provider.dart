import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/graphql/graphql_queries.dart';
import '../../../core/graphql/ws_client.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/storage/storage_service.dart';
import '../../../shared/models/lounge_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../lounges/providers/lounges_provider.dart';

/// The loungeId currently open in LoungeChatScreen — suppress notifications.
final activeLoungeChatIdProvider = StateProvider<String?>((ref) => null);

class LoungeUnreadNotifier extends StateNotifier<Set<String>> {
  final StorageService _storage;
  final WsClient _ws;
  final String? _myUserId;
  final Ref _ref;
  final _subs = <String, StreamSubscription>{};
  final _loungeNames = <String, String>{};
  bool _disposed = false;

  LoungeUnreadNotifier(this._storage, this._ws, this._myUserId, this._ref)
      : super(_storage.unreadLoungeChatIds);

  void updateLounges(List<LoungeModel> lounges) {
    if (_disposed) return;

    final active = <String>{};
    for (final l in lounges) {
      if (!l.chatEnabled) continue;
      active.add(l.id);
      _loungeNames[l.id] = l.name;
      if (!_subs.containsKey(l.id)) {
        _subscribeLounge(l.id, l.name);
      }
    }

    // Cancel subscriptions for lounges no longer chat-enabled.
    for (final id in _subs.keys.toList()) {
      if (!active.contains(id)) {
        _subs[id]?.cancel();
        _subs.remove(id);
      }
    }
  }

  void _subscribeLounge(String loungeId, String loungeName) {
    final sub = _ws
        .subscribe(kNewLoungeChatMessageSubscription,
            variables: {'loungeId': loungeId})
        .listen((payload) {
      if (_disposed) return;
      final data =
          payload['data']?['newLoungeChatMessage'] as Map<String, dynamic>?;
      if (data == null) return;
      final senderId = data['senderId'] as String?;
      final text = data['text'] as String? ?? '';
      // Ignore own messages.
      if (_myUserId != null && senderId == _myUserId) return;
      _notify(loungeId, loungeName, text);
    });
    _subs[loungeId] = sub;
  }

  Future<void> _notify(
      String loungeId, String loungeName, String text) async {
    await _storage.markLoungeChatUnread(loungeId);
    if (!_disposed) state = Set<String>.from(state)..add(loungeId);
    final active = _ref.read(activeLoungeChatIdProvider);
    if (active != loungeId) {
      await NotificationService.showNewLoungeChatMessage(
          loungeId, loungeName, text);
    }
  }

  Future<void> markRead(String loungeId) async {
    await _storage.markLoungeChatRead(loungeId);
    if (!_disposed) state = Set<String>.from(state)..remove(loungeId);
  }

  Future<void> refreshFromStorage() async {
    await _storage.reload();
    final ids = _storage.unreadLoungeChatIds;
    if (ids.isNotEmpty && !_disposed) {
      state = Set<String>.from(state)..addAll(ids);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final sub in _subs.values) {
      sub.cancel();
    }
    debugPrint('LoungeUnreadNotifier disposed');
    super.dispose();
  }
}

final loungeUnreadProvider =
    StateNotifierProvider<LoungeUnreadNotifier, Set<String>>((ref) {
  final storage = ref.watch(storageServiceProvider);
  final ws = ref.watch(wsClientProvider);
  final auth = ref.watch(authProvider);
  final notifier = LoungeUnreadNotifier(storage, ws, auth.userId, ref);

  ref.listen<LoungesState>(
    loungesProvider,
    (_, next) => notifier.updateLounges(next.lounges),
    fireImmediately: true,
  );

  return notifier;
});
