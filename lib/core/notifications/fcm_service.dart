import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../graphql/graphql_queries.dart';
import 'notification_service.dart';

/// Top-level handler required by firebase_messaging for background messages.
/// Cannot do navigation here — only light processing.
@pragma('vm:entry-point')
Future<void> fcmBackgroundHandler(RemoteMessage message) async {
  debugPrint('FCM background: ${message.messageId}');
}

/// Manages FCM token lifecycle and routes incoming push messages.
class FcmService {
  static String? _currentToken;
  static StreamSubscription? _tokenRefreshSub;

  /// Broadcast stream emitting [RemoteMessage.data] maps when a user taps
  /// a FCM notification from background or foreground state.
  static final _navController =
      StreamController<Map<String, String?>>.broadcast();
  static Stream<Map<String, String?>> get navigationStream =>
      _navController.stream;

  /// Call once from [main] after Firebase is initialised, before [runApp].
  static Future<void> init() async {
    FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Foreground messages: show local notification via NotificationService.
    FirebaseMessaging.onMessage.listen(_handleForeground);

    // User tapped a notification while the app was in background.
    FirebaseMessaging.onMessageOpenedApp.listen(_emitNavigation);
  }

  /// Call after a successful login to register the device token.
  /// Pass a [GraphQLClient] built with the newly acquired JWT.
  static Future<void> onLogin(GraphQLClient client) async {
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;

    try {
      _currentToken = await FirebaseMessaging.instance.getToken();
      if (_currentToken != null) {
        await _registerDevice(client, _currentToken!);
      }

      _tokenRefreshSub =
          FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
        _currentToken = token;
        await _registerDevice(client, token);
      });
    } catch (e) {
      debugPrint('FcmService.onLogin: $e');
    }
  }

  /// Call before clearing the JWT on explicit logout.
  static Future<void> onLogout(GraphQLClient client) async {
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;

    try {
      final token =
          _currentToken ?? await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _unregisterDevice(client, token);
      }
      _currentToken = null;
    } catch (e) {
      debugPrint('FcmService.onLogout: $e');
    }
  }

  /// Call on session expiry: cancels refresh listener without a backend call
  /// (the JWT is already invalid so unregister would fail anyway).
  static Future<void> cancelRefreshListener() async {
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    _currentToken = null;
  }

  /// Returns FCM data payload if the app was launched by tapping a notification
  /// while it was terminated. Must be called after [init].
  static Future<Map<String, String?>?> getInitialNavigationData() async {
    try {
      final msg = await FirebaseMessaging.instance.getInitialMessage();
      if (msg != null) return msg.data.cast<String, String?>();
    } catch (e) {
      debugPrint('FcmService.getInitialNavigationData: $e');
    }
    return null;
  }

  // ── Internal ────────────────────────────────────────────────────────────────

  static void _handleForeground(RemoteMessage message) {
    final data = message.data;
    final notification = message.notification;
    final eventType = data['eventType'] as String?;
    final orderId = data['orderId'] as String?;
    final loungeId = data['loungeId'] as String?;
    final title = notification?.title ?? '';
    final body = notification?.body ?? '';

    switch (eventType) {
      case 'new_order':
        if (orderId != null) {
          NotificationService.showNewOrder(orderId);
        }
      case 'new_message':
        if (orderId != null) {
          NotificationService.showNewMessage(orderId, body);
        }
      case 'lounge_chat_message':
        if (loungeId != null) {
          NotificationService.showNewLoungeChatMessage(loungeId, title, body);
        }
      default:
        // order_status, feedback_request — show generic notification.
        if (title.isNotEmpty || body.isNotEmpty) {
          NotificationService.showGeneric(title: title, body: body);
        }
    }
  }

  static void _emitNavigation(RemoteMessage message) {
    _navController.add(message.data.cast<String, String?>());
  }

  static Future<void> _registerDevice(
      GraphQLClient client, String fcmToken) async {
    try {
      final result = await client.mutate(MutationOptions(
        document: gql(kRegisterDeviceMutation),
        variables: {'fcmToken': fcmToken},
      ));
      if (result.hasException) {
        debugPrint('FcmService._registerDevice: ${result.exception}');
      } else {
        debugPrint('FcmService: device registered');
      }
    } catch (e) {
      debugPrint('FcmService._registerDevice: $e');
    }
  }

  static Future<void> _unregisterDevice(
      GraphQLClient client, String fcmToken) async {
    try {
      final result = await client.mutate(MutationOptions(
        document: gql(kUnregisterDeviceMutation),
        variables: {'fcmToken': fcmToken},
      ));
      if (result.hasException) {
        debugPrint('FcmService._unregisterDevice: ${result.exception}');
      } else {
        debugPrint('FcmService: device unregistered');
      }
    } catch (e) {
      debugPrint('FcmService._unregisterDevice: $e');
    }
  }
}
