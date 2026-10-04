import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/delivery.dart';
import '../services/ai_agent_service.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/contract_service.dart';
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
  static const _prefsContractSigned = 'session.contract_signed';
  static const _prefsAutoSuggest = 'settings.auto_suggest';
  static const _prefsChannel = 'settings.channel';

  /// The rule the backend applies at sign-up (`auth/routes/auth.routes.js`),
  /// mirrored here rather than invented.
  ///
  /// The app used to accept anything containing `@`, so a driver could pass the
  /// form and still be answered 422 with a bare "enter a valid e-mail address"
  /// - which is exactly what "it always says e-mail invalid" was.
  static final RegExp _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  /// Canonical form of an address: no whitespace (never legal in an e-mail, and
  /// keyboards and paste routinely leave a stray space behind) and lower case,
  /// so what the driver types is what the server stores.
  static String normalizeEmail(String email) =>
      email.replaceAll(RegExp(r'\s+'), '').toLowerCase();

  /// `null` when the address is one the server will accept, otherwise the
  /// message to show. Always states the expected shape - a bare "invalid" tells
  /// the driver nothing about what to fix.
  static String? validateEmail(String email) =>
      _emailRe.hasMatch(normalizeEmail(email))
          ? null
          : 'Enter a valid e-mail, e.g. name@example.com';

  /// Where the app talks to. Fixed at build time - the endpoint is a build
  /// setting, never something a device screen edits or displays.
  final String baseUrl = AppConfig.defaultBaseUrl;
  String driverId = 'DRV-77';
  String driverName = 'Demo Driver';
  String driverEmail = '';
  String driverRole = 'driver';
  bool signedIn = false;

  /// Whether the driver partnership agreement has been signed.
  ///
  /// Persisted alongside the session so a returning driver does not flash the
  /// agreement screen while `/auth/me` is still in flight; the server reply
  /// overwrites it either way, so a stale local value cannot unlock anything.
  bool contractSigned = false;

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
    contractSigned = signedIn && (prefs.getBool(_prefsContractSigned) ?? false);
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
      contractSigned = me.contractSigned;
      // Converge the cached flag with the server, so the next cold start does
      // not replay a disagreement between what we believed and what is true.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsContractSigned, contractSigned);
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

    final trimmedEmail = normalizeEmail(email);
    final emailProblem = validateEmail(trimmedEmail);
    if (emailProblem != null) {
      errorMessage = emailProblem;
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
    final trimmedEmail = normalizeEmail(email);
    final emailProblem = validateEmail(trimmedEmail);
    if (trimmedName.length < 2) {
      errorMessage = 'Enter your name (at least 2 characters).';
    } else if (emailProblem != null) {
      errorMessage = emailProblem;
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

  /// Signs the partnership agreement on behalf of the signed-in driver.
  ///
  /// On success the backend also dispatches every open delivery to this driver,
  /// so [contractSigned] flipping to true is exactly the moment work appears in
  /// the queue - there is no separate "refresh my jobs" step to forget.
  Future<bool> signContract({required String signatureName}) async {
    busy = true;
    errorMessage = null;
    notifyListeners();

    final trimmed = signatureName.trim();
    if (trimmed.length < 2) {
      errorMessage = 'Type your full name to sign.';
      busy = false;
      notifyListeners();
      return false;
    }

    try {
      await ContractService(api)
          .sign(signatureName: trimmed, acknowledged: true);
      contractSigned = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsContractSigned, true);
    } on ApiException catch (error) {
      errorMessage = error.offline
          ? 'Cannot reach the server right now. Please try again.'
          : error.message;
      busy = false;
      notifyListeners();
      return false;
    } catch (_) {
      errorMessage = 'Signing failed. Please try again.';
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
    contractSigned = result.driver.contractSigned;
    signedIn = true;
    notice = null;

    await tokens.write(result.token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsSignedIn, true);
    await prefs.setBool(_prefsContractSigned, contractSigned);
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
    contractSigned = false;
    token = null;
    driverEmail = '';
    // Reset the identity too: leaving the last driver's id behind would let the
    // next screen act on behalf of an account nobody is signed in as.
    driverId = 'DRV-77';
    driverName = 'Demo Driver';
    driverRole = 'driver';
    notice = noticeMessage;
    await tokens.delete();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsSignedIn);
    await prefs.remove(_prefsContractSigned);
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
