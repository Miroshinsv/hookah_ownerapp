import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/app_config.dart';

enum WsStatus { disconnected, connecting, connected, reconnecting }

class WsClient {
  final String token;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  final _subscriptions = <String, StreamController<Map<String, dynamic>>>{};
  final _pendingSubs = <String, Map<String, dynamic>>{};
  int _idCounter = 0;
  WsStatus _status = WsStatus.disconnected;
  int _reconnectAttempts = 0;
  bool _disposed = false;

  final _statusController = StreamController<WsStatus>.broadcast();
  Stream<WsStatus> get statusStream => _statusController.stream;
  WsStatus get status => _status;

  WsClient(this.token);

  Future<void> connect() async {
    if (_disposed) return;
    _setStatus(WsStatus.connecting);
    try {
      _channel = WebSocketChannel.connect(
        Uri.parse(AppConfig.wsUrl),
        protocols: const ['graphql-transport-ws'],
      );
      _sub = _channel!.stream.listen(
        _onMessage,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
      );
      _send({'type': 'connection_init', 'payload': {'Authorization': 'Bearer $token'}});
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _setStatus(WsStatus s) {
    _status = s;
    if (!_statusController.isClosed) _statusController.add(s);
  }

  void _send(Map<String, dynamic> data) {
    try {
      _channel?.sink.add(jsonEncode(data));
    } catch (_) {}
  }

  void _onMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = msg['type'] as String?;

      switch (type) {
        case 'connection_ack':
          _reconnectAttempts = 0;
          _setStatus(WsStatus.connected);
          // Re-subscribe pending
          for (final entry in _pendingSubs.entries) {
            _send({'type': 'subscribe', 'id': entry.key, 'payload': entry.value});
          }
        case 'ping':
          _send({'type': 'pong'});
        case 'next':
          final id = msg['id'] as String?;
          final payload = msg['payload'] as Map<String, dynamic>?;
          if (id != null && payload != null && !(_subscriptions[id]?.isClosed ?? true)) {
            _subscriptions[id]!.add(payload);
          }
        case 'error':
          final id = msg['id'] as String?;
          if (id != null) {
            _subscriptions[id]?.addError(msg['payload'] ?? 'Unknown error');
          }
        case 'complete':
          final id = msg['id'] as String?;
          if (id != null) {
            _subscriptions[id]?.close();
            _subscriptions.remove(id);
            _pendingSubs.remove(id);
          }
      }
    } catch (e) {
      debugPrint('WsClient parse error: $e');
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _setStatus(WsStatus.reconnecting);
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;

    final delay = Duration(
      milliseconds: min(1000 * pow(2, _reconnectAttempts).toInt(), 30000),
    );
    _reconnectAttempts++;
    Future.delayed(delay, () {
      if (!_disposed) connect();
    });
  }

  Stream<Map<String, dynamic>> subscribe(
    String query, {
    Map<String, dynamic>? variables,
  }) {
    final id = '${++_idCounter}';
    final controller = StreamController<Map<String, dynamic>>.broadcast();
    _subscriptions[id] = controller;

    final payload = <String, dynamic>{'query': query};
    if (variables != null) payload['variables'] = variables;
    _pendingSubs[id] = payload;

    if (_status == WsStatus.connected) {
      _send({'type': 'subscribe', 'id': id, 'payload': payload});
    }

    controller.onCancel = () {
      _send({'type': 'complete', 'id': id});
      _subscriptions.remove(id);
      _pendingSubs.remove(id);
    };

    return controller.stream;
  }

  void dispose() {
    _disposed = true;
    _statusController.close();
    for (final ctrl in _subscriptions.values) {
      ctrl.close();
    }
    _subscriptions.clear();
    _pendingSubs.clear();
    _sub?.cancel();
    _channel?.sink.close();
  }
}
