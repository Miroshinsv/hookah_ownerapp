import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const _channelId = 'orders_v2';
  static const _channelName = 'Заказы';
  static const _alertNotifId = 9999;

  // Repeats the alert sound every 30 s while new orders exist.
  static Timer? _alertTimer;
  static bool _alertActive = false;

  static Future<void> init() async {
    if (_initialized) return;
    const androidSettings =
        AndroidInitializationSettings('@drawable/ic_notification');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
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

    _initialized = true;
  }

  // Called when a new order arrives (first time detected by polling).
  static Future<void> showNewOrder(String orderId) async {
    final shortId = orderId.substring(0, orderId.length.clamp(0, 8));
    await _plugin.show(
      orderId.hashCode,
      'Новый заказ',
      'Поступил новый заказ #$shortId',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId, _channelName,
          channelDescription: 'Уведомления о новых заказах',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@drawable/ic_notification',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
        ),
      ),
    );
  }

  // Start repeating in-app alert while new orders exist.
  static Future<void> startAlert() async {
    if (_alertActive) return;
    _alertActive = true;
    await _playAlertOnce();
    _alertTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _playAlertOnce();
    });
  }

  // Stop repeating alert when no new orders remain.
  static Future<void> stopAlert() async {
    if (!_alertActive) return;
    _alertActive = false;
    _alertTimer?.cancel();
    _alertTimer = null;
    try {
      Vibration.cancel();
    } catch (_) {}
    await _plugin.cancel(_alertNotifId);
  }

  static Future<void> _playAlertOnce() async {
    await _plugin.show(
      _alertNotifId,
      'Новый заказ ожидает!',
      'Есть необработанные заказы',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId, _channelName,
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@drawable/ic_notification',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: false,
          presentSound: true,
          presentBadge: false,
        ),
      ),
    );
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
