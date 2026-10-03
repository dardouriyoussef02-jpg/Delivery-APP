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

/// In-process stand-in for the agent service so sign-in can be tested without
/// a backend. Mirrors the real contract: `POST /auth/login` validates, every
/// other endpoint requires the bearer token.
SessionController _sessionWithApi({bool acceptCredentials = true}) {
  final client = MockClient((request) async {
    final path = request.url.path;

    if (path.endsWith('/auth/login')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final ok = acceptCredentials && body['password'] == 'secret123';
      if (!ok) return _json({'error': 'invalid e-mail or password'}, status: 401);
      return _json({
        'token': 'test-token',
        'tokenType': 'Bearer',
        'expiresAt': '2099-01-01T00:00:00.000Z',
        'driver': {
          'id': 'DRV-77',
          'name': 'Demo Driver',
          'email': body['email'],
          'role': 'driver',
          // An established driver has already signed the agreement, so
          // sign-in lands in the shell rather than at the onboarding gate.
          'contractSigned': true,
        },
      });
    }

    if (request.headers['authorization'] != 'Bearer test-token') {
      return _json({'error': 'authentication required'}, status: 401);
    }

    if (path.endsWith('/auth/me')) {
      return _json({
        'driver': {
          'id': 'DRV-77',
          'name': 'Demo Driver',
          'email': 'driver@courier.co',
          'role': 'driver',
          'contractSigned': true,
        },
      });
    }
    if (path.endsWith('/deliveries')) return _json({'deliveries': <dynamic>[]});
    return _json({});
  });

  return SessionController(client: client);
}

/// Two accounts holding two disjoint routes, keyed by session token the way
/// the real service does it - the query string is never consulted.
SessionController _sessionWithTwoRoutes() {
  const tokens = {
    'token-drv-11': 'DRV-11',
    'token-drv-22': 'DRV-22',
  };
  const routes = {
    'DRV-11': [
      {
        'id': 'DLV-2001',
        'status': 'pending',
        'sequence': 1,
        'driverId': 'DRV-11',
        'address': {'line1': '18 Kanalstraat', 'city': 'Rotterdam', 'postalCode': '3011 AB'},
        'customer': {
          'id': 'CUS-1111',
          'firstName': 'Sanne',
          'lastName': 'de Vries',
          'phone': '+31 6 1111 1111',
          'preferredChannel': 'sms',
          'language': 'nl',
        },
      },
    ],
    'DRV-22': [
      {
        'id': 'DLV-2002',
        'status': 'pending',
        'sequence': 1,
        'driverId': 'DRV-22',
        'address': {'line1': '92 Schiedamseweg', 'city': 'Rotterdam', 'postalCode': '3021 AK'},
        'customer': {
          'id': 'CUS-2222',
          'firstName': 'Amina',
          'lastName': 'Bakker',
          'phone': '+31 6 2222 2222',
          'preferredChannel': 'whatsapp',
          'language': 'en',
        },
      },
    ],
  };

  final client = MockClient((request) async {
    final path = request.url.path;

    if (path.endsWith('/auth/login')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final second = body['email'] == 'second@fleet.local';
      final token = second ? 'token-drv-22' : 'token-drv-11';
      return _json({
        'token': token,
        'tokenType': 'Bearer',
        'expiresAt': '2099-01-01T00:00:00.000Z',
        'driver': {
          'id': tokens[token],
          'name': second ? 'Second Driver' : 'First Driver',
          'email': body['email'],
          'role': 'driver',
          'contractSigned': true,
        },
      });
    }

    final token = request.headers['authorization']?.replaceFirst('Bearer ', '');
    final driverId = tokens[token ?? ''];
    if (driverId == null) return _json({'error': 'authentication required'}, status: 401);

    if (path.endsWith('/auth/me')) {
      return _json({
        'driver': {
          'id': driverId,
          'name': driverId == 'DRV-22' ? 'Second Driver' : 'First Driver',
          'email': 'driver@fleet.local',
          'role': 'driver',
          'contractSigned': true,
        },
      });
    }
    if (path.endsWith('/deliveries')) {
      final route = routes[driverId]!;
      return _json({'count': route.length, 'deliveries': route});
    }
    return _json({});
  });

  return SessionController(client: client);
}

void main() {
  testWidgets('boots into the login screen', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const DeliveryApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Delivery Driver'), findsWidgets);
  });

  testWidgets('signs in through the API and shows the driver shell', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(DeliveryApp(session: _sessionWithApi()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'driver@courier.co');
    await tester.enterText(find.byType(TextFormField).last, 'secret123');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    expect(find.text('Deliveries'), findsOneWidget);
    expect(find.text('Route'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });

  testWidgets('rejects an invalid e-mail', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(DeliveryApp(session: _sessionWithApi()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'not-an-email');
    await tester.enterText(find.byType(TextFormField).last, 'secret123');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid e-mail'), findsOneWidget);
  });

  testWidgets('shows the backend rejection for bad credentials', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(DeliveryApp(session: _sessionWithApi()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'driver@courier.co');
    await tester.enterText(find.byType(TextFormField).last, 'wrong-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid e-mail or password.'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('a second driver is shown their own route, never the first driver\'s',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final session = _sessionWithTwoRoutes();

    await tester.pumpWidget(DeliveryApp(session: session));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'first@fleet.local');
    await tester.enterText(find.byType(TextFormField).last, 'secret123');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    expect(find.text('Sanne de Vries'), findsOneWidget, reason: 'the first driver sees her stop');

    await session.signOut();
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('Welcome back'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'second@fleet.local');
    await tester.enterText(find.byType(TextFormField).last, 'secret123');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    expect(find.text('Amina Bakker'), findsOneWidget, reason: 'the second driver sees hers');
    expect(
      find.text('Sanne de Vries'),
      findsNothing,
      reason: "the previous driver's route must not survive an account switch",
    );
  });
}
