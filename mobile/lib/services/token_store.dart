import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'platform_call.dart';

/// Reads/writes the session token handed out by `POST /api/v1/auth/login`.
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> delete();
}

/// Token store backed by the platform secure enclave
/// (Android Keystore, iOS Keychain, web WebCrypto, desktop DPAPI).
///
/// The token is never written to SharedPreferences or any other plain
/// storage. When the platform implementation is unavailable (widget tests,
/// unsupported embedder) the store degrades to memory-only storage for the
/// lifetime of the process instead of falling back to insecure persistence.
class SecureTokenStore implements TokenStore {
  SecureTokenStore() : _memory = InMemoryTokenStore();

  static const _key = 'delivery_driver.auth_token';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final InMemoryTokenStore _memory;
  bool _platformAvailable = true;

  @override
  Future<String?> read() async {
    if (!_platformAvailable) return _memory.read();
    final result = await guardedPlatformCall<String?>(
      _storage.read(key: _key),
      label: 'secure-storage',
    );
    if (!result.ok) return _unavailable(_memory.read);
    return result.value;
  }

  @override
  Future<void> write(String token) async {
    if (!_platformAvailable) return _memory.write(token);
    final result = await guardedPlatformCall<void>(
      _storage.write(key: _key, value: token),
      label: 'secure-storage',
    );
    if (!result.ok) {
      _platformAvailable = false;
      debugLog('secure storage unavailable - keeping the token in memory only');
      await _memory.write(token);
    }
  }

  @override
  Future<void> delete() async {
    if (!_platformAvailable) return _memory.delete();
    final result = await guardedPlatformCall<void>(
      _storage.delete(key: _key),
      label: 'secure-storage',
    );
    if (!result.ok) {
      _platformAvailable = false;
      await _memory.delete();
    }
  }

  Future<T> _unavailable<T>(Future<T> Function() action) async {
    _platformAvailable = false;
    return action();
  }
}

/// Process-memory token storage: the fallback used in tests and whenever the
/// secure enclave is not reachable. Cleared on sign-out and on process death.
class InMemoryTokenStore implements TokenStore {
  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  @override
  Future<void> delete() async => _token = null;
}

void debugLog(String message) {
  assert(() {
    // ignore: avoid_print
    print('[auth] $message');
    return true;
  }());
}
