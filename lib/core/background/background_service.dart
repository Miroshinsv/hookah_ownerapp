import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

const _tokenKey = 'auth_token';
const _channelId = 'orders_v2';
const _channelName = 'Заказы';
const _foregroundNotifId = 88888;

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

  // Channel must exist before the foreground service notification is shown.
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
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

  await _checkNewOrders();
  Timer.periodic(const Duration(seconds: 30), (_) => _checkNewOrders());
}

/// iOS background fetch entry point.
@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  return true;
}

/// Polls for new orders and drives the audio alarm.
/// FCM handles push notifications; this only manages the alarm lifecycle.
Future<void> _checkNewOrders() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
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
            'query': '{ orders(limit: 500, status: "new") { id } }',
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) return;
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['errors'] != null) return;

    final count =
        (decoded['data']?['orders'] as List<dynamic>?)?.length ?? 0;

    if (count > 0) {
      _startAlarm();
    } else {
      _stopAlarm();
    }
  } catch (e) {
    debugPrint('BackgroundService._checkNewOrders: $e');
  }
}

class BackgroundOrderService {
  static const _channel = MethodChannel('ru.hookahorder/battery');

  static Future<bool> isBatteryOptimizationIgnored() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      final result =
          await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestIgnoreBatteryOptimizations() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (e) {
      debugPrint('BackgroundOrderService.requestBatteryOpt: $e');
    }
  }

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
