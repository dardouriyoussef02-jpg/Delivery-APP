import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'network_error_stub.dart'
    if (dart.library.io) 'network_error_io.dart' show isNetworkError;

/// App-wide constants and the default connection settings.
class AppConfig {
  AppConfig._();

  /// Android emulator reaches the host machine through 10.0.2.2, iOS
  /// simulators and desktop use localhost.
  ///
  /// Overridden at build time for a real deployment, so the shipped bundle
  /// never has to be edited to point at production:
  ///
  /// ```sh
  /// flutter build web --dart-define=API_BASE_URL=https://api.example.com
  /// ```
  static const defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8787',
  );

  static const connectTimeout = Duration(seconds: 15);
  static const requestTimeout = Duration(seconds: 30);

  /// Mirrors `MAX_MESSAGE_CHARS` on the agent service.
  static const maxMessageChars = 320;
  static const minMessageChars = 40;

  static const appName = 'Delivery Driver';
  static const appVersion = '1.0.0';

  /// Route origin ("pickup") drawn on the map - the depot the shift starts
  /// from. Coordinates only (never a secret); adjust to your own depot.
  static const depotName = 'Depot';
  static const depotLat = 51.9244;
  static const depotLng = 4.4777;
}

/// Raised for every failed call so the UI can show one readable message.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.offline = false});

  final String message;
  final int? statusCode;

  /// True when the backend could not be reached at all (no network / host
  /// down), which is when the app falls back to bundled demo data.
  final bool offline;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Thin HTTP wrapper around the existing API + agent endpoints.
///
/// The base URL and the driver headers are supplied by callbacks so this class
/// never has to know about auth state or persistence.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this.headers,
    http.Client? client,
    this.onUnauthorized,
  }) : _client = client ?? http.Client();

  final String Function() baseUrl;
  final Map<String, String> Function() headers;

  /// Called whenever a protected endpoint answers 401 so the session can be
  /// cleared (expired/revoked token) without every caller handling it.
  final Future<void> Function()? onUnauthorized;
  final http.Client _client;

  Future<dynamic> get(String path) => _send('GET', path);

  Future<dynamic> post(String path, {Object? body}) => _send('POST', path, body: body);

  Future<dynamic> patch(String path, {Object? body}) => _send('PATCH', path, body: body);

  Future<dynamic> _send(String method, String path, {Object? body}) async {
    final uri = Uri.parse('${baseUrl().replaceAll(RegExp(r'/+$'), '')}$path');

    final request = http.Request(method, uri)
      ..headers.addAll({
        'accept': 'application/json',
        ...headers(),
      });

    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    try {
      final streamed = await _client.send(request).timeout(AppConfig.requestTimeout);
      final response = await http.Response.fromStream(streamed);
      // `await` matters: it keeps the 401 cleanup inside this try/catch, so a
      // rejected session is settled before the error reaches the caller.
      return await _decode(response);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException('The server took too long to answer. Try again.', offline: true);
    } on http.ClientException {
      throw ApiException(_offlineMessage, offline: true);
    } catch (error) {
      // dart:io socket failures only exist on Android/iOS/desktop; the stub
      // returns false on web where package:http reports ClientException.
      if (isNetworkError(error)) {
        throw ApiException(_offlineMessage, offline: true);
      }
      rethrow;
    }
  }

  /// Wording for an unreachable host. It deliberately names no host, port or
  /// setting: connection details belong to the backend, not to a device screen.
  static const _offlineMessage = 'Cannot reach the server right now. Please try again.';

  Future<dynamic> _decode(http.Response response) async {
    dynamic payload;
    if (response.body.isNotEmpty) {
      try {
        payload = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        payload = null;
      }
    }

    if (response.statusCode >= 400) {
      // Only the service's own human-readable error is forwarded. Status codes
      // and paths stay in the client so a screen never shows an endpoint.
      final message = payload is Map && payload['error'] is String
          ? payload['error'] as String
          : 'The server could not complete the request.';
      if (response.statusCode == 401) {
        // Awaited, not fire-and-forget: the session must be cleared *before*
        // the caller handles the error, otherwise a boot sequence can reach
        // the next endpoint (deliveries, notifications) with the very token
        // the server just rejected and earn a second 401 for the same reason.
        await onUnauthorized?.call();
      }
      throw ApiException(message, statusCode: response.statusCode);
    }

    return payload;
  }
}
