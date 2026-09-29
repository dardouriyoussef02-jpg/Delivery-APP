import 'dart:convert';

import 'package:delivery_driver/app.dart';
import 'package:delivery_driver/state/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

/// Stand-in for the auth endpoints that mirrors the backend contract:
/// 422 invalid input, 409 e-mail taken, 403 sign-up disabled, 201 created.
class _SignupServer {
  final List<Map<String, dynamic>> registrations = [];

  SessionController session() => SessionController(client: MockClient(_handle));

  Future<http.Response> _handle(http.Request request) async {
    final path = request.url.path;

    if (path.endsWith('/auth/register')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      registrations.add(body);

      final name = (body['name'] as String? ?? '').trim();
      final email = (body['email'] as String? ?? '').trim().toLowerCase();
      final password = body['password'] as String? ?? '';

      if (name.length < 2) {
        return _json({'error': 'name must be at least 2 characters'}, status: 422);
      }
      if (!email.contains('@')) {
        return _json({'error': 'enter a valid e-mail address'}, status: 422);
      }
      if (password.length < 8) {
        return _json({'error': 'password must be at least 8 characters'}, status: 422);
      }
      if (email == 'taken@fleet.local') {
        return _json({'error': 'an account with this e-mail already exists'},
            status: 409);
      }
      if (email == 'blocked@fleet.local') {
        return _json({'error': 'registration is disabled on this server'},
            status: 403);
      }

      return _json({
        'token': 'signup-token',
        'tokenType': 'Bearer',
        'expiresAt': '2099-01-01T00:00:00.000Z',
        'driver': {'id': 'DRV-NEW1', 'name': name, 'email': email, 'role': 'driver'},
      }, status: 201);
    }

    if (request.headers['authorization'] != 'Bearer signup-token') {
      return _json({'error': 'authentication required'}, status: 401);
    }

    if (path.endsWith('/auth/me')) {
      return _json({
        'driver': {
          'id': 'DRV-NEW1',
          'name': 'Nina Courier',
          'email': 'nina@courier.co',
          'role': 'driver',
        },
      });
    }
    if (path.endsWith('/notifications')) {
      return _json({'notifications': <dynamic>[], 'unreadCount': 0});
    }
    if (path.endsWith('/deliveries')) return _json({'deliveries': <dynamic>[]});
    return _json({});
  }
}

Future<void> _bootApp(WidgetTester tester, _SignupServer server) async {
  // Tall viewport: the sign-up form stacks four fields plus the actions, so
  // the submit button must stay on screen for the tap to land.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(DeliveryApp(session: server.session()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

Future<void> _openSignup(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'New driver? Create an account'));
  await tester.pumpAndSettle();
}

Future<void> _fillSignupForm(
  WidgetTester tester, {
  required String name,
  required String email,
  required String password,
  required String confirm,
}) async {
  await tester.enterText(find.byType(TextFormField).at(0), name);
  await tester.enterText(find.byType(TextFormField).at(1), email);
  await tester.enterText(find.byType(TextFormField).at(2), password);
  await tester.enterText(find.byType(TextFormField).at(3), confirm);
}

void main() {
  testWidgets('a new driver registers with e-mail and signs straight in',
      (tester) async {
    final server = _SignupServer();
    await _bootApp(tester, server);
    await _openSignup(tester);

    expect(find.text('Create account'), findsWidgets);
    expect(find.text('Full name'), findsOneWidget);

    await _fillSignupForm(
      tester,
      name: 'Nina Courier',
      email: 'nina@courier.co',
      password: 'secret-1234',
      confirm: 'secret-1234',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    // Signed in: the driver shell replaced the form.
    expect(find.text('Deliveries'), findsOneWidget);
    expect(find.text('Route'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);

    expect(server.registrations, hasLength(1));
    expect(server.registrations.single['name'], 'Nina Courier');
    expect(server.registrations.single['email'], 'nina@courier.co');
  });

  testWidgets('a mismatched password is caught before any request',
      (tester) async {
    final server = _SignupServer();
    await _bootApp(tester, server);
    await _openSignup(tester);

    await _fillSignupForm(
      tester,
      name: 'Nina Courier',
      email: 'nina@courier.co',
      password: 'secret-1234',
      confirm: 'secret-1235',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();

    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(server.registrations, isEmpty, reason: 'no request was sent');
  });

  testWidgets('a short password is caught before any request', (tester) async {
    final server = _SignupServer();
    await _bootApp(tester, server);
    await _openSignup(tester);

    await _fillSignupForm(
      tester,
      name: 'Nina Courier',
      email: 'nina@courier.co',
      password: 'short1',
      confirm: 'short1',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();

    expect(find.text('At least 8 characters'), findsOneWidget);
    expect(server.registrations, isEmpty);
  });

  testWidgets('shows the backend rejection when the e-mail is taken',
      (tester) async {
    final server = _SignupServer();
    await _bootApp(tester, server);
    await _openSignup(tester);

    await _fillSignupForm(
      tester,
      name: 'Other Driver',
      email: 'taken@fleet.local',
      password: 'secret-1234',
      confirm: 'secret-1234',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();

    expect(find.text('An account with this e-mail already exists.'), findsOneWidget);
    expect(find.text('Create account'), findsWidgets, reason: 'stays on the form');
  });

  testWidgets('shows when the server disabled registration', (tester) async {
    final server = _SignupServer();
    await _bootApp(tester, server);
    await _openSignup(tester);

    await _fillSignupForm(
      tester,
      name: 'Blocked Driver',
      email: 'blocked@fleet.local',
      password: 'secret-1234',
      confirm: 'secret-1234',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();

    expect(find.text('Registration is disabled on this server.'), findsOneWidget);
  });

  testWidgets('switching back to sign-in restores the original form',
      (tester) async {
    final server = _SignupServer();
    await _bootApp(tester, server);

    await _openSignup(tester);
    expect(find.text('Create account'), findsWidgets);

    await tester
        .tap(find.widgetWithText(TextButton, 'Already have an account? Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    expect(find.text('Full name'), findsNothing);
    // 2 fields again: e-mail + password.
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.textContaining('demo credentials are configured'), findsOneWidget);
  });
}
