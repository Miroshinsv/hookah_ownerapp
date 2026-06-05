import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static final _chatOpenController = StreamController<String>.broadcast();
  static Stream<String> get chatOpenStream => _chatOpenController.stream;

  static final _loungeChatOpenController = StreamController<String>.broadcast();
  static Stream<String> get loungeChatOpenStream =>
      _loungeChatOpenController.stream;

  static void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.startsWith('chat:')) {
      _chatOpenController.add(payload.substring(5));
    } else if (payload != null && payload.startsWith('lounge-chat:')) {
      _loungeChatOpenController.add(payload.substring(12));
    }
  }

  static Future<String?> getPendingChatOpen() async {
    if (!_initialized) return null;
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp == true) {
        final payload = details?.notificationResponse?.payload;
        if (payload != null && payload.startsWith('chat:')) {
          return payload.substring(5);
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> getPendingLoungeChatOpen() async {
    if (!_initialized) return null;
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp == true) {
        final payload = details?.notificationResponse?.payload;
        if (payload != null && payload.startsWith('lounge-chat:')) {
          return payload.substring(12);
        }
      }
    } catch (_) {}
    return null;
  }

  // Custom icon if available, fallback to launcher icon.
  static const _customIcon   = '@drawable/ic_notification';
  static const _fallbackIcon = '@mipmap/ic_launcher';
  static String _notifIcon   = _customIcon;

  static const _channelId     = 'orders_v2';
  static const _channelName   = 'Заказы';
  static const _msgChannelId  = 'chat_messages';
  static const _msgChannelName = 'Сообщения чата';
  static const _alertNotifId  = 9999;

  static Timer? _alertTimer;
  static bool   _alertActive = false;

  static Future<void> init() async {
    if (_initialized) return;
    // Try with custom hookah icon first; fall back to launcher icon if missing.
    for (final icon in [_customIcon, _fallbackIcon]) {
      try {
        await _tryInit(icon);
        _notifIcon = icon;
        _initialized = true;
        return;
      } catch (e) {
        debugPrint('NotificationService: init with $icon failed: $e');
      }
    }
    // Notifications unavailable — app still works without them.
    debugPrint('NotificationService: notifications disabled (init failed)');
  }

  static Future<void> _tryInit(String icon) async {
    final androidSettings = AndroidInitializationSettings(icon);
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      settings: InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Уведомления о новых заказах',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _msgChannelId,
        _msgChannelName,
        description: 'Уведомления о новых сообщениях в чате',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );
  }

  static Future<void> showNewMessage(String orderId, String text) async {
    if (!_initialized) return;
    try {
      final shortId = orderId.substring(0, orderId.length.clamp(0, 8));
      await _plugin.show(
        id: orderId.hashCode ^ 0x8000,
        title: 'Новое сообщение #$shortId',
        body: text.isNotEmpty ? text : 'Сообщение от клиента',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _msgChannelId, _msgChannelName,
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            icon: _notifIcon,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            presentBadge: true,
          ),
        ),
        payload: 'chat:$orderId',
      );
    } catch (e) {
      debugPrint('NotificationService.showNewMessage: $e');
    }
  }

  static Future<void> showNewLoungeChatMessage(
      String loungeId, String loungeName, String text) async {
    if (!_initialized) return;
    try {
      await _plugin.show(
        id: loungeId.hashCode ^ 0xC000,
        title: 'Чат — $loungeName',
        body: text.isNotEmpty ? text : 'Новое сообщение',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _msgChannelId, _msgChannelName,
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            icon: _notifIcon,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            presentBadge: true,
          ),
        ),
        payload: 'lounge-chat:$loungeId',
      );
    } catch (e) {
      debugPrint('NotificationService.showNewLoungeChatMessage: $e');
    }
  }

  static Future<void> showNewOrder(String orderId) async {
    if (!_initialized) return;
    try {
      final shortId = orderId.substring(0, orderId.length.clamp(0, 8));
      await _plugin.show(
        id: orderId.hashCode,
        title: 'Новый заказ #$shortId',
        body: 'Поступил новый заказ',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId, _channelName,
            channelDescription: 'Уведомления о новых заказах',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            icon: _notifIcon,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            presentBadge: true,
          ),
        ),
      );
    } catch (e) {
      debugPrint('NotificationService.showNewOrder: $e');
    }
  }

  static Future<void> startAlert() async {
    if (_alertActive || !_initialized) return;
    _alertActive = true;
    await _playAlertOnce();
    _alertTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _playAlertOnce();
    });
  }

  static Future<void> stopAlert() async {
    if (!_alertActive) return;
    _alertActive = false;
    _alertTimer?.cancel();
    _alertTimer = null;
    try { Vibration.cancel(); } catch (_) {}
    if (_initialized) await _plugin.cancel(id: _alertNotifId);
  }

  static Future<void> _playAlertOnce() async {
    if (!_initialized) return;
    try {
      await _plugin.show(
        id: _alertNotifId,
        title: 'Новый заказ ожидает!',
        body: 'Есть необработанные заказы',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId, _channelName,
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            icon: _notifIcon,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: false,
            presentSound: true,
            presentBadge: false,
          ),
        ),
      );
    } catch (e) {
      debugPrint('NotificationService._playAlertOnce: $e');
    }
    await _vibrate();
  }

  static Future<void> _vibrate() async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        Vibration.vibrate(pattern: [0, 300, 200, 300, 200, 300]);
      } else {
        HapticFeedback.heavyImpact();
      }
    } catch (_) {
      HapticFeedback.heavyImpact();
    }
  }
}
