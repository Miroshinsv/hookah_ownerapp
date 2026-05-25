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
const _msgChannelId = 'chat_messages';
const _msgChannelName = 'Сообщения чата';
const _foregroundNotifId = 88888;
const _bgLastMsgTsPrefix = 'bg_last_msg_ts_';
const _unreadKey = 'unread_order_ids';
const _staffRoles = {'admin', 'owner', 'hookah_master', 'hostess', 'waiter', 'staff'};

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

  final androidPlugin = plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

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

  if (service is AndroidServiceInstance) {
    service.on('stopService').listen((_) => service.stopSelf());

    await service.setAsForegroundService();
    service.setForegroundNotificationInfo(
      title: 'Hookah Admin',
      content: 'Мониторинг заказов активен',
    );
  }

  // Check immediately, then every 30 seconds.
  await _checkNewOrders(plugin, service);
  await _checkNewMessages(plugin);
  Timer.periodic(const Duration(seconds: 30), (_) async {
    await _checkNewOrders(plugin, service);
    await _checkNewMessages(plugin);
  });
}

/// iOS background fetch entry point.
@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  return true;
}

Future<void> _checkNewOrders(
    FlutterLocalNotificationsPlugin plugin, ServiceInstance service) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    // Force re-read from platform storage: the main isolate may have written
    // a new token (login/re-login) after this background isolate started.
    // Each isolate caches SharedPreferences independently, so without reload()
    // the token would never be visible here after the first boot.
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

      final shortId = id.substring(0, id.length.clamp(0, 8));
      final name = (order['firstName'] as String? ?? '').trim();
      final flavor = (order['flavor'] as String? ?? '').trim();
      final body = [
        if (name.isNotEmpty) name,
        if (flavor.isNotEmpty) flavor,
      ].join(' · ');

      await plugin.show(
        id.hashCode,
        'Новый заказ #$shortId',
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

    // Update foreground notification with last-check timestamp so the user
    // (and developer) can verify the service is actively polling.
    final now = DateTime.now();
    final ts = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    final content = newOrders.isEmpty
        ? 'Проверено в $ts · новых заказов нет'
        : 'Проверено в $ts · новых: ${newOrders.length}';
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'Hookah Admin',
        content: content,
      );
    }
  } catch (e) {
    debugPrint('BackgroundService._checkNewOrders: $e');
  }
}

Future<void> _checkNewMessages(FlutterLocalNotificationsPlugin plugin) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // keep in sync with main isolate
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
            'query': '{ orders(limit: 100) { id status } }',
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) return;
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['errors'] != null) return;

    final activeOrders = (decoded['data']?['orders'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .where((o) {
          final s = o['status'] as String?;
          return s == 'new' || s == 'in_progress';
        })
        .toList();

    for (final order in activeOrders) {
      await _checkOrderMessages(plugin, prefs, token, order['id'] as String);
    }
  } catch (e) {
    debugPrint('BackgroundService._checkNewMessages: $e');
  }
}

Future<void> _checkOrderMessages(
  FlutterLocalNotificationsPlugin plugin,
  SharedPreferences prefs,
  String token,
  String orderId,
) async {
  try {
    final response = await http
        .post(
          Uri.parse(AppConfig.graphqlUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'query':
                '{ messages(orderId: "$orderId") { id senderRole text createdAt } }',
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) return;
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['errors'] != null) return;

    final messages = (decoded['data']?['messages'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    if (messages.isEmpty) return;

    final tsKey = '$_bgLastMsgTsPrefix$orderId';
    final lastSeenStr = prefs.getString(tsKey);
    final lastSeen = lastSeenStr != null ? DateTime.tryParse(lastSeenStr) : null;

    // Sort to find latest timestamp
    final times = messages
        .map((m) => DateTime.tryParse(m['createdAt'] as String? ?? ''))
        .whereType<DateTime>()
        .toList()
      ..sort();

    // Always update last-seen to the latest message timestamp
    if (times.isNotEmpty) {
      await prefs.setString(tsKey, times.last.toIso8601String());
    }

    // On first check (no stored timestamp), just record state without notifying
    if (lastSeen == null) return;

    // Find new non-staff messages
    final newClientMessages = messages.where((m) {
      final role = m['senderRole'] as String?;
      if (role != null && _staffRoles.contains(role)) return false;
      final ts = DateTime.tryParse(m['createdAt'] as String? ?? '');
      return ts != null && ts.isAfter(lastSeen);
    }).toList();

    if (newClientMessages.isEmpty) return;

    // Mark order as unread in SharedPreferences so the foreground app
    // picks it up on resume.
    final unreadList = prefs.getStringList(_unreadKey)?.toSet() ?? {};
    unreadList.add(orderId);
    await prefs.setStringList(_unreadKey, unreadList.toList());

    // Show one notification with the latest message text
    final latest = newClientMessages.last;
    final text = latest['text'] as String? ?? '';
    final shortId = orderId.substring(0, orderId.length.clamp(0, 8));
    await plugin.show(
      orderId.hashCode ^ 0x7F000,
      'Новое сообщение #$shortId',
      text.isNotEmpty ? text : 'Сообщение от клиента',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _msgChannelId,
          _msgChannelName,
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
    debugPrint('BackgroundService._checkOrderMessages($orderId): $e');
  }
}

class BackgroundOrderService {
  static const _channel = MethodChannel('ru.hookahorder/battery');

  /// Returns true if the app is already whitelisted from battery optimisation.
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

  /// Opens the system dialog that asks the user to disable battery
  /// optimisation for this app.  Should be called after login.
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
