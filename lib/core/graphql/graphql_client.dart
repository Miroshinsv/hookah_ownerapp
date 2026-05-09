import 'dart:convert';
import 'dart:developer' as dev;

import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

// Server doesn't support GraphQL variables — it only accepts inline values
// (same as the web client). This client strips variable declarations from the
// operation header and substitutes $name references with literal values.
class _GraphQLHttpClient extends http.BaseClient {
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest baseRequest) async {
    http.BaseRequest request = baseRequest;

    if (baseRequest is http.Request && baseRequest.method == 'POST') {
      try {
        final json = jsonDecode(baseRequest.body) as Map<String, dynamic>;
        final variables = json['variables'];
        if (variables is Map<String, dynamic> && variables.isNotEmpty) {
          final query = _inline(json['query'] as String, variables);
          final newBody = jsonEncode({'query': query});
          request = http.Request(baseRequest.method, baseRequest.url)
            ..headers.addAll(baseRequest.headers)
            ..body = newBody;
        }
      } catch (_) {}
    }

    final body = request is http.Request ? request.body : '';
    dev.log('→ ${request.method} ${request.url}\nBody: $body', name: 'HTTP');

    final response = await _inner.send(request);
    final bytes = await response.stream.toBytes();
    dev.log('← ${response.statusCode}\nBody: ${String.fromCharCodes(bytes)}',
        name: 'HTTP');

    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      contentLength: bytes.length,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      request: response.request,
    );
  }

  // Removes ($var: Type!, ...) declarations and replaces $var references
  // with literal GraphQL values, matching the format the web client uses.
  static String _inline(String query, Map<String, dynamic> variables) {
    final firstBrace = query.indexOf('{');
    if (firstBrace > 0) {
      final header = query.substring(0, firstBrace);
      final body = query.substring(firstBrace);
      // [^)]* matches newlines too, handles multi-line param lists
      final cleanHeader = header.replaceAll(RegExp(r'\([^)]*\)'), '');
      query = cleanHeader + body;
    }
    for (final entry in variables.entries) {
      query = query.replaceAll('\$${entry.key}', _fmt(entry.value));
    }
    return query;
  }

  static String _fmt(dynamic v) {
    if (v == null) return 'null';
    if (v is String) {
      final escaped = v.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
      return '"$escaped"';
    }
    if (v is num || v is bool) return '$v';
    if (v is List) return '[${v.map(_fmt).join(', ')}]';
    return '"$v"';
  }
}

GraphQLClient buildGraphQLClient(String token) {
  final httpLink = HttpLink(
    AppConfig.graphqlUrl,
    defaultHeaders: {
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    },
    httpClient: _GraphQLHttpClient(),
  );

  return GraphQLClient(
    link: httpLink,
    cache: GraphQLCache(store: InMemoryStore()),
    defaultPolicies: DefaultPolicies(
      query: Policies(fetch: FetchPolicy.networkOnly),
      mutate: Policies(fetch: FetchPolicy.networkOnly),
    ),
  );
}