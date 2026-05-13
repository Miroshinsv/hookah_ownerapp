import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

const _tokenKey = 'auth_token';
const _channelId = 'orders_v2';
const _channelName = 'Заказы';
const _foregroundNotifId = 88888;

// In-memory set of order IDs already notified within this service lifetime.
var _seenIds = <String>{};

// Notification icon resolved at init time.
String _notifIcon = '@mipmap/ic_launcher';

// ── Audio alarm state (isolate-scoped) ──────────────────────────────────────
AudioPlayer? _player;
Timer? _crescendoTimer;
double _volume = 0.0;
bool _alarmActive = false;

void _startAlarm() {
  if (_alarmActive) return;
  _alarmActive = true;
  _volume = 0.15;
  try {
    _player ??= AudioPlayer();
    _player!.setReleaseMode(ReleaseMode.loop);
    _player!.setVolume(_volume);
    _player!
        .play(UrlSource('content://settings/system/alarm_alert'))
        .catchError((_) {});
    _crescendoTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_volume >= 1.0) {
        _crescendoTimer?.cancel();
        return;
      }
      _volume = (_volume + 0.1).clamp(0.0, 1.0);
      _player?.setVolume(_volume);
    });
  } catch (e) {
    debugPrint('BackgroundService._startAlarm: $e');
  }
}

void _stopAlarm() {
  if (!_alarmActive) return;
  _alarmActive = false;
  _crescendoTimer?.cancel();
  _crescendoTimer = null;
  _volume = 0.0;
  try {
    _player?.stop();
  } catch (_) {}
}

/// Entry point for the Android background isolate.
@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final plugin = FlutterLocalNotificationsPlugin();

  // Try custom hookah icon, fall back to launcher icon
  for (final icon in ['@drawable/ic_notification', '@mipmap/ic_launcher']) {
    final ok = await plugin.initialize(
          InitializationSettings(
            android: AndroidInitializationSettings(icon),
          ),
        ) ??
        false;
    if (ok) {
      _notifIcon = icon;
      break;
    }
  }

  await plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'Уведомления о новых заказах',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );

  if (service is AndroidServiceInstance) {
    service.on('stopService').listen((_) => service.stopSelf());

    await service.setAsForegroundService();
    service.setForegroundNotificationInfo(
      title: 'Hookah Admin',
      content: 'Мониторинг заказов активен',
    );
  }

  // Check immediately, then every 30 seconds.
  await _checkNewOrders(plugin);
  Timer.periodic(
      const Duration(seconds: 30), (_) => _checkNewOrders(plugin));
}

/// iOS background fetch entry point.
@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  return true;
}

Future<void> _checkNewOrders(FlutterLocalNotificationsPlugin plugin) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token == null || token.isEmpty) return;

    final response = await http
        .post(
          Uri.parse(AppConfig.graphqlUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'query':
                '{ orders(limit: 500, status: "new") { id userId loungeId flavor comment phone firstName lastName arrivalAt status createdAt } }',
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      debugPrint(
          'BackgroundService: HTTP ${response.statusCode}');
      return;
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;

    // Surface GraphQL-level errors so they don't silently swallow results.
    if (decoded['errors'] != null) {
      debugPrint('BackgroundService: GraphQL errors: ${decoded['errors']}');
      return;
    }

    final newOrders = (decoded['data']?['orders'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();

    // Send a notification for each order we haven't seen yet.
    for (final order in newOrders) {
      final id = order['id'] as String;
      if (_seenIds.contains(id)) continue;

      _seenIds.add(id);

      final name = (order['firstName'] as String? ?? '').trim();
      final flavor = (order['flavor'] as String? ?? '').trim();
      final body = [
        if (name.isNotEmpty) name,
        if (flavor.isNotEmpty) flavor,
      ].join(' · ');

      await plugin.show(
        id.hashCode,
        'Новый заказ',
        body.isNotEmpty ? body : 'Поступил новый заказ',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
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
    }

    // Evict IDs of orders that are no longer "new" to keep set bounded.
    // Only intersect with IDs that are currently new — not all orders.
    final currentNewIds = newOrders.map((o) => o['id'] as String).toSet();
    _seenIds = _seenIds.intersection(currentNewIds);

    if (newOrders.isNotEmpty) {
      _startAlarm();
    } else {
      _stopAlarm();
    }
  } catch (e) {
    debugPrint('BackgroundService._checkNewOrders: $e');
  }
}

class BackgroundOrderService {
  static Future<void> initialize() async {
    if (!defaultTargetPlatform.toString().contains('android') &&
        !defaultTargetPlatform.toString().contains('iOS')) {
      return;
    }

    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: _channelId,
        initialNotificationTitle: 'Hookah Admin',
        initialNotificationContent: 'Запуск мониторинга заказов...',
        foregroundServiceNotificationId: _foregroundNotifId,
        foregroundServiceTypes: [AndroidForegroundType.dataSync],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );

    await service.startService();
  }

  static void stop() {
    FlutterBackgroundService().invoke('stopService');
  }
}
