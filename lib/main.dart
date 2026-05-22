import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/background/background_service.dart';
import 'firebase_options.dart';
import 'core/navigation/app_router.dart';
import 'core/notifications/notification_service.dart';
import 'core/storage/storage_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/providers/auth_provider.dart';

const _kGeocoderKeyEnv = String.fromEnvironment('YANDEX_GEOCODER_API_KEY');
const _kGeocoderApiKey =
    _kGeocoderKeyEnv == '' ? '74eba148-1881-4fb8-b4a2-1e158e3fbc2f' : _kGeocoderKeyEnv;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ignore: avoid_print
  print('[Config] YANDEX_GEOCODER_API_KEY = $_kGeocoderApiKey');
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.init();
  await BackgroundOrderService.initialize();
  final storage = await StorageService.create();
  runApp(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
      ],
      child: const HookahAdminApp(),
    ),
  );
}

class HookahAdminApp extends ConsumerWidget {
  const HookahAdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Hookah Admin',
      theme: AppTheme.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
