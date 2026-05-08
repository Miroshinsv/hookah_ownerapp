import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const _tokenKey = 'auth_token';
  static const _roleKey = 'auth_role';
  static const _loungeIdKey = 'auth_lounge_id';
  static const _userIdKey = 'auth_user_id';
  static const _unreadKey = 'unread_order_ids';
  static const _lastReadPrefix = 'last_read_';

  final SharedPreferences _prefs;

  StorageService(this._prefs);

  static Future<StorageService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  String? get token => _prefs.getString(_tokenKey);
  String? get role => _prefs.getString(_roleKey);
  String? get loungeId => _prefs.getString(_loungeIdKey);
  String? get userId => _prefs.getString(_userIdKey);

  Future<void> saveAuth({
    required String token,
    required String role,
    String? loungeId,
    String? userId,
  }) async {
    await _prefs.setString(_tokenKey, token);
    await _prefs.setString(_roleKey, role);
    if (loungeId != null) {
      await _prefs.setString(_loungeIdKey, loungeId);
    } else {
      await _prefs.remove(_loungeIdKey);
    }
    if (userId != null) await _prefs.setString(_userIdKey, userId);
  }

  Future<void> clearAuth() async {
    await _prefs.remove(_tokenKey);
    await _prefs.remove(_roleKey);
    await _prefs.remove(_loungeIdKey);
    await _prefs.remove(_userIdKey);
  }

  Set<String> get unreadOrderIds =>
      _prefs.getStringList(_unreadKey)?.toSet() ?? {};

  Future<void> markOrderUnread(String orderId) async {
    final ids = unreadOrderIds..add(orderId);
    await _prefs.setStringList(_unreadKey, ids.toList());
  }

  Future<void> markOrderRead(String orderId) async {
    final ids = unreadOrderIds..remove(orderId);
    await _prefs.setStringList(_unreadKey, ids.toList());
    await _prefs.setString(
        '$_lastReadPrefix$orderId', DateTime.now().toIso8601String());
  }

  DateTime? lastReadAt(String orderId) {
    final s = _prefs.getString('$_lastReadPrefix$orderId');
    return s != null ? DateTime.tryParse(s) : null;
  }
}
