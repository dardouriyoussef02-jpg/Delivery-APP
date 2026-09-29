import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/delivery.dart';
import '../services/ai_agent_service.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/token_store.dart';

/// Auth + connection settings for the signed-in driver.
///
/// Sign-in goes through `POST /api/v1/auth/login`: the backend validates the
/// credentials and returns a bearer token, which is kept in secure storage and
/// attached to every subsequent request. Any e-mail is no longer accepted.
class SessionController extends ChangeNotifier {
  SessionController({http.Client? client, TokenStore? tokenStore})
      : tokens = tokenStore ?? SecureTokenStore() {
    api = ApiClient(
      baseUrl: () => baseUrl,
      headers: _headers,
      client: client,
      onUnauthorized: _handleUnauthorized,
    );
  }

  late final ApiClient api;
  final TokenStore tokens;

  static const _prefsSignedIn = 'session.signed_in';
  static const _prefsEmail = 'session.email';
  static const _prefsAutoSuggest = 'settings.auto_suggest';
  static const _prefsChannel = 'settings.channel';

  /// Where the app talks to. Fixed at build time - the endpoint is a build
  /// setting, never something a device screen edits or displays.
  final String baseUrl = AppConfig.defaultBaseUrl;
  String driverId = 'DRV-77';
  String driverName = 'Demo Driver';
  String driverEmail = '';
  String driverRole = 'driver';
  bool signedIn = false;
  bool autoSuggest = true;
  MessageChannel defaultChannel = MessageChannel.sms;

  /// The bearer token from the backend (kept out of SharedPreferences).
  String? token;

  /// One-shot message shown after a forced sign-out (expired/invalid token).
  String? notice;

  /// False until persisted settings have been restored from disk.
  bool ready = false;

  bool busy = false;
  String? errorMessage;

  Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    driverEmail = prefs.getString(_prefsEmail) ?? '';
    autoSuggest = prefs.getBool(_prefsAutoSuggest) ?? true;
    defaultChannel = MessageChannel.fromWire(prefs.getString(_prefsChannel));

    token = await tokens.read();
    signedIn = token != null && (prefs.getBool(_prefsSignedIn) ?? false);
    if (signedIn) {
      driverName = _nameFromEmail(driverEmail);
      // Verify the stored token while the app boots. An invalid token drops
      // the session; an unreachable server keeps it (the app shows offline).
      unawaited(_validateSession());
    }

    ready = true;
    notifyListeners();
  }

  Future<void> _validateSession() async {
    try {
      final me = await AuthService(api).me();
      driverId = me.id;
      driverName = me.name;
      driverEmail = me.email;
      driverRole = me.role;
      notifyListeners();
    } on ApiException {
      // 401 already cleared the session through the ApiClient callback;
      // an unreachable server keeps the session (the app runs offline).
    } catch (_) {
      // Unexpected but non-fatal: keep the session.
    }
  }

  Map<String, String> _headers() => {
        if (token != null) 'authorization': 'Bearer $token',
        if (driverId.isNotEmpty) 'x-driver-id': driverId,
      };

  /// Invoked by [ApiClient] whenever a protected endpoint answers 401.
  Future<void> _handleUnauthorized() async {
    if (signedIn) {
      await _clearSession(noticeMessage: 'Your session expired. Please sign in again.');
    }
  }

  /// Talks to the backend: no local "accept anything" path.
  Future<bool> signIn({required String email, required String password}) async {
    busy = true;
    errorMessage = null;
    notifyListeners();

    final trimmedEmail = email.trim();
    if (!trimmedEmail.contains('@') || trimmedEmail.length < 5) {
      errorMessage = 'Enter a valid e-mail address.';
    } else if (password.length < 4) {
      errorMessage = 'Password must be at least 4 characters.';
    }

    if (errorMessage != null) {
      busy = false;
      notifyListeners();
      return false;
    }

    try {
      final result =
          await AuthService(api).login(email: trimmedEmail, password: password);
      await _startSession(result);
    } on ApiException catch (error) {
      errorMessage = error.statusCode == 401
          ? 'Invalid e-mail or password.'
          : error.offline
              ? 'Cannot reach the server right now. Please try again.'
              : error.message;
      busy = false;
      notifyListeners();
      return false;
    } catch (_) {
      errorMessage = 'Sign-in failed. Please try again.';
      busy = false;
      notifyListeners();
      return false;
    }

    busy = false;
    notifyListeners();
    return true;
  }

  /// Creates a driver account on the backend and signs the new driver in.
  ///
  /// Server rules (never trusted from the client): 422 invalid input,
  /// 409 e-mail already registered, 403 registration disabled.
  Future<bool> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    busy = true;
    errorMessage = null;
    notifyListeners();

    final trimmedName = name.trim();
    final trimmedEmail = email.trim();
    if (trimmedName.length < 2) {
      errorMessage = 'Enter your name (at least 2 characters).';
    } else if (!trimmedEmail.contains('@') || trimmedEmail.length < 5) {
      errorMessage = 'Enter a valid e-mail address.';
    } else if (password.length < 8) {
      errorMessage = 'Password must be at least 8 characters.';
    }

    if (errorMessage != null) {
      busy = false;
      notifyListeners();
      return false;
    }

    try {
      final result = await AuthService(api)
          .register(name: trimmedName, email: trimmedEmail, password: password);
      await _startSession(result);
    } on ApiException catch (error) {
      if (error.statusCode == 409) {
        errorMessage = 'An account with this e-mail already exists.';
      } else if (error.statusCode == 403) {
        errorMessage = 'Registration is disabled on this server.';
      } else if (error.offline) {
        errorMessage = 'Cannot reach the server right now. Please try again.';
      } else {
        errorMessage = error.message;
      }
      busy = false;
      notifyListeners();
      return false;
    } catch (_) {
      errorMessage = 'Sign-up failed. Please try again.';
      busy = false;
      notifyListeners();
      return false;
    }

    busy = false;
    notifyListeners();
    return true;
  }

  /// Applies a login/register result: stores the token securely and marks the
  /// session signed in. Shared by [signIn] and [signUp].
  Future<void> _startSession(LoginResult result) async {
    token = result.token;
    driverId = result.driver.id;
    driverName = result.driver.name;
    driverEmail = result.driver.email;
    driverRole = result.driver.role;
    signedIn = true;
    notice = null;

    await tokens.write(result.token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsSignedIn, true);
    await prefs.setString(_prefsEmail, driverEmail);
  }

  Future<void> signOut() async {
    // Best-effort server-side revocation; local sign-out always happens.
    try {
      await AuthService(api).logout();
    } catch (_) {
      // Offline or already invalid - nothing to revoke remotely.
    }
    await _clearSession();
  }

  Future<void> _clearSession({String? noticeMessage}) async {
    signedIn = false;
    token = null;
    driverEmail = '';
    driverName = 'Demo Driver';
    driverRole = 'driver';
    notice = noticeMessage;
    await tokens.delete();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsSignedIn);
    await prefs.remove(_prefsEmail);
    notifyListeners();
  }

  void clearNotice() {
    if (notice == null) return;
    notice = null;
    notifyListeners();
  }

  Future<void> setAutoSuggest(bool value) async {
    autoSuggest = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsAutoSuggest, value);
    notifyListeners();
  }

  Future<void> setDefaultChannel(MessageChannel channel) async {
    defaultChannel = channel;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsChannel, channel.wire);
    notifyListeners();
  }

  /// Cheap health probe shown to the driver as a plain connection check.
  ///
  /// The answer stays generic on purpose: which model, data source or host
  /// sits behind the service is backend information and never reaches a screen.
  Future<({bool ok, String message})> testConnection() async {
    try {
      final health = await AiAgentService(api).health();
      return (
        ok: health.ok,
        message: health.ok
            ? 'Connected to the delivery service.'
            : 'The service is not responding yet.',
      );
    } on ApiException {
      return (ok: false, message: 'Cannot reach the delivery service right now.');
    }
  }

  String get initials {
    final parts = driverName.trim().split(RegExp(r'\s+'));
    final first = parts.isEmpty ? '' : parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  static String _nameFromEmail(String email) {
    if (email.isEmpty) return 'Demo Driver';
    final raw = email.split('@').first.replaceAll(RegExp(r'[._-]+'), ' ').trim();
    if (raw.isEmpty) return 'Demo Driver';
    return raw
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }
}
