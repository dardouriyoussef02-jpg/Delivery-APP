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

/// Backend stand-in for the onboarding gate.
///
/// Mirrors the real service: `/auth/login` reports whether the agreement is
/// signed, `/contract` serves the text, `/contract/sign` records the
/// signature. `failContract` simulates an unreachable document endpoint.
class _ContractServer {
  _ContractServer({this.contractSigned = false, this.failContract = false});

  /// Whether this driver has already signed; flips when the sign call lands.
  bool contractSigned;
  final bool failContract;

  final List<Map<String, dynamic>> signatures = [];

  SessionController session() => SessionController(client: MockClient(_handle));

  Future<http.Response> _handle(http.Request request) async {
    final path = request.url.path;

    if (path.endsWith('/auth/login')) {
      return _json({
        'token': 'test-token',
        'tokenType': 'Bearer',
        'expiresAt': '2099-01-01T00:00:00.000Z',
        'driver': {
          'id': 'DRV-NEW1',
          'name': 'Nina Courier',
          'email': 'nina@courier.co',
          'role': 'driver',
          'contractSigned': contractSigned,
        },
      });
    }

    if (request.headers['authorization'] != 'Bearer test-token') {
      return _json({'error': 'authentication required'}, status: 401);
    }

    if (path.endsWith('/contract/sign')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      signatures.add(body);
      contractSigned = true;
      return _json({
        'contract': {
          'id': 'CON-TEST',
          'version': '1.0',
          'signatureName': body['signatureName'],
          'signedAt': '2099-01-01T00:00:00.000Z',
        },
        'dispatch': {'assigned': 4, 'deliveryIds': ['DLV-1042']},
        'alreadySigned': false,
      }, status: 201);
    }

    if (path.endsWith('/contract')) {
      if (failContract) {
        return _json({'error': 'the service is unavailable'}, status: 500);
      }
      return _json({
        'version': '1.0',
        'title': 'Driver Partnership Agreement',
        'company': 'ShiftFlow Logistics',
        'sections': [
          {
            'heading': '1. Engagement',
            'body': 'Deliveries are assigned only after this agreement is signed.',
          },
          {
            'heading': '2. Assigning of work',
            'body': 'The driver sees only the route dispatched to them.',
          },
        ],
        'signed': contractSigned,
      });
    }

    if (path.endsWith('/deliveries')) return _json({'deliveries': <dynamic>[]});
    if (path.endsWith('/notifications')) {
      return _json({'notifications': <dynamic>[], 'unreadCount': 0});
    }
    return _json(<String, dynamic>{});
  }
}

Future<void> _boot(WidgetTester tester, _ContractServer server) async {
  // The agreement screen stacks the document, the signature card and the
  // actions, so give the tap targets room to be visible.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(DeliveryApp(session: server.session()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

Future<void> _signIn(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).first, 'nina@courier.co');
  await tester.enterText(find.byType(TextFormField).last, 'secret-1234');
  await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
  await tester.pumpAndSettle(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('an unsigned driver is held at the agreement, not the queue',
      (tester) async {
    final server = _ContractServer();
    await _boot(tester, server);
    await _signIn(tester);

    expect(find.text('Before your first route'), findsOneWidget);
    expect(find.text('Driver Partnership Agreement'), findsOneWidget);
    expect(find.text('Deliveries'), findsNothing);
    expect(find.text('Route'), findsNothing);
    expect(find.text('Sign out'), findsOneWidget,
        reason: 'there is always a way out');
  });

  testWidgets('a driver who already signed goes straight to the queue',
      (tester) async {
    final server = _ContractServer(contractSigned: true);
    await _boot(tester, server);
    await _signIn(tester);

    expect(find.text('Before your first route'), findsNothing);
    expect(find.text('Deliveries'), findsOneWidget);
  });

  testWidgets('signing needs the acknowledgement, not just a name',
      (tester) async {
    final server = _ContractServer();
    await _boot(tester, server);
    await _signIn(tester);

    // Name is prefilled from the profile; the checkbox is deliberately left.
    await tester.tap(find.widgetWithText(FilledButton, 'Sign contract'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(server.signatures, isEmpty,
        reason: 'nothing is sent without consent');
    expect(
      find.text('Confirm that you have read and accept the agreement.'),
      findsOneWidget,
    );
    expect(find.text('Before your first route'), findsOneWidget);
  });

  testWidgets('signing records the signature and opens the queue',
      (tester) async {
    final server = _ContractServer();
    await _boot(tester, server);
    await _signIn(tester);

    await tester.ensureVisible(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Sign contract'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    expect(server.signatures, hasLength(1));
    expect(server.signatures.single['acknowledged'], true);
    expect(server.signatures.single['signatureName'], 'Nina Courier');

    expect(find.text('Before your first route'), findsNothing);
    expect(find.text('Deliveries'), findsOneWidget);
    expect(find.text('Route'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });

  testWidgets('a driver may correct the prefilled signature', (tester) async {
    final server = _ContractServer();
    await _boot(tester, server);
    await _signIn(tester);

    await tester.ensureVisible(find.byType(TextFormField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Nina M. Courier');

    await tester.ensureVisible(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign contract'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    expect(server.signatures.single['signatureName'], 'Nina M. Courier');
  });

  testWidgets('an agreement that will not load offers a retry, not a blank page',
      (tester) async {
    final server = _ContractServer(failContract: true);
    await _boot(tester, server);
    await _signIn(tester);

    expect(find.text('Could not load the agreement'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
    expect(find.text('Deliveries'), findsNothing);
  });

  testWidgets('signing out from the gate returns to the login form',
      (tester) async {
    final server = _ContractServer();
    await _boot(tester, server);
    await _signIn(tester);
    expect(find.text('Before your first route'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(TextButton, 'Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Before your first route'), findsNothing);
  });
}
