import 'package:flutter/services.dart';

abstract final class ApkInstaller {
  static const _channel = MethodChannel('ru.hookahorder.hookah_admin/apk_installer');

  static Future<void> install(String path) =>
      _channel.invokeMethod<void>('install', {'path': path});
}
