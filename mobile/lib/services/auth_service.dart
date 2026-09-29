import 'api_client.dart';

/// The signed-in user as the backend sees it.
class DriverProfile {
  const DriverProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
  });

  final String id;
  final String name;
  final String email;

  /// `driver` or `admin` - drives role-based screens (admin statistics).
  final String role;

  bool get isAdmin => role == 'admin';

  factory DriverProfile.fromJson(Map<String, dynamic> json) => DriverProfile(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        email: (json['email'] as String?) ?? '',
        role: (json['role'] as String?) ?? 'driver',
      );
}

class LoginResult {
  const LoginResult({required this.token, required this.driver});

  final String token;
  final DriverProfile driver;
}

/// Client for the authentication endpoints.
///
/// The password never leaves this class without going to the backend, and the
/// returned bearer token is stored by [SessionController] in secure storage.
class AuthService {
  AuthService(this._api);

  final ApiClient _api;

  Future<LoginResult> login({required String email, required String password}) async {
    final data = await _api.post(
      '/api/v1/auth/login',
      body: {'email': email, 'password': password},
    );
    return _toLoginResult(data);
  }

  /// Creates a driver account (`POST /auth/register`) and returns its fresh
  /// session. The backend enforces the rules: 422 invalid input,
  /// 409 e-mail taken, 403 sign-up disabled on this server.
  Future<LoginResult> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final data = await _api.post(
      '/api/v1/auth/register',
      body: {'name': name, 'email': email, 'password': password},
    );
    return _toLoginResult(data);
  }

  /// Login and register share the same response contract.
  LoginResult _toLoginResult(dynamic data) {
    final payload = (data as Map?)?.cast<String, dynamic>();
    final token = payload?['token'] as String?;
    final driver = (payload?['driver'] as Map?)?.cast<String, dynamic>();

    if (token == null || token.isEmpty || driver == null) {
      throw ApiException('The server returned an invalid sign-in response.');
    }
    return LoginResult(token: token, driver: DriverProfile.fromJson(driver));
  }

  /// Revokes the current session server-side (best effort).
  Future<void> logout() async {
    await _api.post('/api/v1/auth/logout');
  }

  /// Used on boot to verify a restored token is still valid.
  Future<DriverProfile> me() async {
    final data = await _api.get('/api/v1/auth/me');
    final driver = (data as Map?)?['driver'] as Map?;
    if (driver == null) throw ApiException('Unexpected response from /auth/me');
    return DriverProfile.fromJson(driver.cast<String, dynamic>());
  }
}
