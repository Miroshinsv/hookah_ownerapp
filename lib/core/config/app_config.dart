class AppConfig {
  static const baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'https://api.hookahorder.ru',
  );

  static String get graphqlUrl => '$baseUrl/graphql';

  static String get wsUrl {
    final base = baseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    return '$base/graphql/subscribe';
  }
}
