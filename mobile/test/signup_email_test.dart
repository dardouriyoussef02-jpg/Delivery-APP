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

/// Guards the sign-up e-mail path end to end: what the driver types is what is
/// stored, and an e-mail is never rejected twice - once by the form and again,
/// differently, by the server.
final RegExp _serverEmailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// An in-process stand-in that rejects exactly what the real backend rejects.
SessionController _sessionWithServerRules({List<String>? sentEmails}) {
  final client = MockClient((request) async {
    final path = request.url.path;

    if (path.endsWith('/auth/register')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final name = (body['name'] as String? ?? '').trim();
      final email = (body['email'] as String? ?? '').trim().toLowerCase();
      final password = body['password'] as String? ?? '';
      sentEmails?.add(email);

      if (name.length < 2) {
        return _json({'error': 'name must be at least 2 characters'}, status: 422);
      }
      if (!_serverEmailRe.hasMatch(email)) {
        return _json({'error': 'enter a valid e-mail address'}, status: 422);
      }
      if (password.length < 8) {
        return _json({'error': 'password must be at least 8 characters'}, status: 422);
      }
      return _json({
        'token': 'new-token',
        'tokenType': 'Bearer',
        'expiresAt': '2099-01-01T00:00:00.000Z',
        'driver': {
          'id': 'DRV-9001',
          'name': name,
          'email': email,
          'role': 'driver',
          'contractSigned': false,
        },
      }, status: 201);
    }

    if (request.headers['authorization'] != 'Bearer new-token') {
      return _json({'error': 'authentication required'}, status: 401);
    }
    if (path.endsWith('/auth/me')) {
      return _json({
        'driver': {
          'id': 'DRV-9001',
          'name': 'Youssef',
          'email': 'youssef@gmail.com',
          'role': 'driver',
          'contractSigned': false,
        },
      });
    }
    if (path.endsWith('/deliveries')) return _json({'deliveries': <dynamic>[]});
    return _json({});
  });

  return SessionController(client: client);
}

Future<void> _boot(WidgetTester tester, SessionController session) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(DeliveryApp(session: session));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

/// Switches sign-in -> sign-up and fills the form. Pass [retypeEmail] to
/// leave the e-mail field untouched after the mode switch.
Future<void> _fillSignUp(
  WidgetTester tester, {
  required String name,
  required String email,
  required String password,
  bool retypeEmail = true,
}) async {
  await tester.tap(find.text('New driver? Create an account'));
  await tester.pumpAndSettle();

  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), name);
  if (retypeEmail) await tester.enterText(fields.at(1), email);
  await tester.enterText(fields.at(2), password);
  await tester.enterText(fields.at(3), password);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sign-up keeps the e-mail the driver typed - never a demo one',
      (tester) async {
    final sent = <String>[];
    final session = _sessionWithServerRules(sentEmails: sent);
    await _boot(tester, session);

    await _fillSignUp(
      tester,
      name: 'Youssef Dardouri',
      email: 'youssef@gmail.com',
      password: 'supersecret',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    expect(find.textContaining('valid e-mail'), findsNothing,
        reason: 'a well-formed e-mail must never be called invalid');
    expect(session.signedIn, isTrue, reason: 'the account must actually be created');
    expect(session.driverEmail, 'youssef@gmail.com',
        reason: 'the session must carry the driver\'s own e-mail');
    expect(session.driverName, 'Youssef Dardouri');
    expect(session.driverId, isNot('DRV-77'),
        reason: 'a new account must never fall back to the demo driver');
    expect(sent, ['youssef@gmail.com']);
  });

  testWidgets('an e-mail left untouched after the mode switch still validates',
      (tester) async {
    final session = _sessionWithServerRules();
    await _boot(tester, session);

    // Type the e-mail while still in sign-in mode...
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'youssef@gmail.com');
    await tester.enterText(fields.at(1), 'supersecret');
    await tester.pumpAndSettle();

    // ...switch to sign-up, which resets the form's validation state...
    await tester.tap(find.text('New driver? Create an account'));
    await tester.pumpAndSettle();

    // ...then fill only the fields the new mode actually shows.
    final signUpFields = find.byType(TextFormField);
    await tester.enterText(signUpFields.at(0), 'Youssef Dardouri');
    await tester.enterText(signUpFields.at(2), 'supersecret');
    await tester.enterText(signUpFields.at(3), 'supersecret');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    expect(find.textContaining('valid e-mail'), findsNothing,
        reason: 'the field visibly holds a valid e-mail, so it must pass');
    expect(session.signedIn, isTrue);
    expect(session.driverEmail, 'youssef@gmail.com');
  });

  testWidgets('a stray space in the e-mail cannot fail sign-up', (tester) async {
    final sent = <String>[];
    final session = _sessionWithServerRules(sentEmails: sent);
    await _boot(tester, session);

    await _fillSignUp(
      tester,
      name: 'Youssef Dardouri',
      email: ' youssef @gmail.com ',
      password: 'supersecret',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    expect(find.textContaining('valid e-mail'), findsNothing);
    expect(find.textContaining('enter a valid e-mail address'), findsNothing,
        reason: 'the server 422 must never be the first thing to see the typo');
    expect(session.signedIn, isTrue,
        reason: 'whitespace is never legal in an e-mail - clean it up, do not reject');
    expect(sent, ['youssef@gmail.com']);
  });

  testWidgets('an e-mail the server would reject is caught by the app, clearly',
      (tester) async {
    final sent = <String>[];
    final session = _sessionWithServerRules(sentEmails: sent);
    await _boot(tester, session);

    await _fillSignUp(
      tester,
      name: 'Youssef Dardouri',
      email: 'youssef@gmail', // no dot after @ -> server answers 422
      password: 'supersecret',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    expect(session.signedIn, isFalse);
    expect(sent, isEmpty, reason: 'never send something the server will reject');
    expect(
      find.textContaining('name@example.com'),
      findsOneWidget,
      reason: 'the message must show the expected shape, not just "invalid"',
    );
  });
}
