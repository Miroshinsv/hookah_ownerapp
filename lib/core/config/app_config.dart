class AppConfig {
  static const baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'https://api.hookahorder.ru',
  );

  static const version = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: 'dev',
  );

  static String get graphqlUrl => '$baseUrl/graphql';

  static String get wsUrl {
    final base = baseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    return '$base/graphql/subscribe';
  }
}
