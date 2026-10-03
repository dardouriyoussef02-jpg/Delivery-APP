// Visual design lock: renders the ShiftFlow dashboard to a PNG so any
// regression in the Stitch re-skin fails the suite instead of slipping through.
//
// After an intentional design change, regenerate with:
//   flutter test --update-goldens test/preview_test.dart
@Tags(['golden'])
library;

import 'dart:convert';

import 'package:delivery_driver/app.dart';
import 'package:delivery_driver/state/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

Future<SessionController> _sessionWithDemoRoute() async {
  final demo = jsonDecode(
    await rootBundle.loadString('assets/demo/deliveries.json'),
  ) as Map<String, dynamic>;

  final client = MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/auth/login')) {
      return _json({
        'token': 'test-token',
        'tokenType': 'Bearer',
        'expiresAt': '2099-01-01T00:00:00.000Z',
        'driver': {
          'id': 'DRV-77',
          'name': 'Demo Driver',
          'email': 'driver@courier.co',
          'role': 'driver',
        },
      });
    }
    if (path.endsWith('/deliveries')) return _json(demo);
    return _json(<String, dynamic>{});
  });

  return SessionController(client: client);
}

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter')
    ..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'));
  await inter.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}

void main() {
  testWidgets('preview: shift & queue dashboard', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _loadFonts();

    tester.view.physicalSize = const Size(412, 917);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(DeliveryApp(session: await _sessionWithDemoRoute()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'driver@courier.co');
    await tester.enterText(find.byType(TextFormField).last, 'secret123');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle(const Duration(milliseconds: 800));

    expect(find.text('Delivery Queue'), findsOneWidget);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/deliveries_screen.png'),
    );
  });
}
