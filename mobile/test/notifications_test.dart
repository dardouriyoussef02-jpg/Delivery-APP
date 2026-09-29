import 'dart:convert';

import 'package:delivery_driver/models/delivery.dart';
import 'package:delivery_driver/screens/notifications_screen.dart';
import 'package:delivery_driver/services/api_client.dart';
import 'package:delivery_driver/services/delivery_repository.dart';
import 'package:delivery_driver/services/local_notifications.dart';
import 'package:delivery_driver/services/notifications_repository.dart';
import 'package:delivery_driver/state/deliveries_controller.dart';
import 'package:delivery_driver/state/notifications_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

/// In-process stand-in for `GET/POST /api/v1/notifications` with switchable
/// failures, so the controller and screen can be tested end-to-end.
class _FeedServer {
  List<Map<String, dynamic>> notifications = [];
  int unread = 0;
  bool failGet = false;
  bool failPost = false;
  final List<String> requests = [];

  http.Client client() => MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.method == 'GET') {
          if (failGet) return _json({'error': 'boom'}, status: 500);
          return _json({'notifications': notifications, 'unreadCount': unread});
        }
        if (request.method == 'POST') {
          if (failPost) return _json({'error': 'boom'}, status: 500);
          if (unread > 0) unread -= 1;
          return _json({'unreadCount': unread});
        }
        return _json({'error': 'not found'}, status: 404);
      });
}

/// Records banners instead of touching a platform channel.
class _FakeLocal implements LocalNotificationsService {
  bool initResult = true;
  bool? permission = true;
  int initCalls = 0;
  final List<Map<String, String?>> shown = [];
  void Function(String payload)? tapHandler;

  @override
  Future<bool> init({required void Function(String payload) onNotificationTap}) async {
    initCalls += 1;
    tapHandler = onNotificationTap;
    return initResult;
  }

  @override
  Future<bool?> requestPermission() async => permission;

  @override
  Future<void> show({
    required String id,
    required String title,
    required String body,
    String? deliveryId,
  }) async {
    shown.add({'id': id, 'title': title, 'body': body, 'deliveryId': deliveryId});
  }

  @override
  Future<String?> pendingLaunchPayload() async => null;
}

Map<String, dynamic> _row({
  String id = 'NTF-0001',
  String type = 'delivery_assigned',
  String title = 'Stop assigned to you',
  String body = 'Sanne de Vries \u00b7 stop 1',
  String? deliveryId = 'DLV-1042',
  bool isRead = false,
  String source = 'demo',
  int minutesAgo = 5,
}) =>
    {
      'id': id,
      'type': type,
      'title': title,
      'body': body,
      'deliveryId': deliveryId,
      'source': source,
      'isRead': isRead,
      'createdAt': DateTime.now().subtract(Duration(minutes: minutesAgo)).toIso8601String(),
    };

({NotificationsController controller, _FeedServer server, _FakeLocal local}) _controller({
  List<Map<String, dynamic>> rows = const [],
  int unread = 0,
}) {
  final server = _FeedServer()
    ..notifications = [...rows]
    ..unread = unread;
  final local = _FakeLocal();
  final controller = NotificationsController(
    NotificationsRepository(
      ApiClient(
        baseUrl: () => 'http://api.test',
        headers: () => const {},
        client: server.client(),
      ),
    ),
    local: local,
  );
  return (controller: controller, server: server, local: local);
}

Delivery _delivery() => Delivery.fromJson({
      'id': 'DLV-1042',
      'status': 'in_transit',
      'zone': 'Riverside',
      'sequence': 1,
      'driverId': 'DRV-77',
      'windowStart': '2026-09-28T15:30:00.000Z',
      'windowEnd': '2026-09-28T16:30:00.000Z',
      'eta': '2026-09-28T15:52:00.000Z',
      'distanceKm': 4.2,
      'parcels': 2,
      'codAmount': 0,
      'currency': 'EUR',
      'address': {
        'line1': '18 Kanalstraat',
        'line2': '',
        'city': 'Rotterdam',
        'postalCode': '3011 AB',
        'lat': 51.9161,
        'lng': 4.4795,
      },
      'customer': {
        'id': 'CUS-8821',
        'firstName': 'Sanne',
        'lastName': 'de Vries',
        'phone': '+31 6 1234 5678',
        'preferredChannel': 'sms',
        'language': 'nl',
      },
      'notes': <Map<String, dynamic>>[],
      'events': <Map<String, dynamic>>[],
      'history': <Map<String, dynamic>>[],
    });

void main() {
  group('NotificationsController', () {
    test('the first load fills the feed without interrupting the driver', () async {
      final harness = _controller(
        rows: [
          _row(id: 'NTF-0001', minutesAgo: 30),
          _row(id: 'NTF-0002', minutesAgo: 10, deliveryId: 'DLV-1043'),
        ],
        unread: 2,
      );

      await harness.controller.load();

      expect(harness.controller.state, LoadState.ready);
      expect(harness.controller.items.length, 2);
      expect(harness.controller.unreadCount, 2);
      expect(
        harness.local.shown,
        isEmpty,
        reason: 'history must not fire system banners on first sync',
      );
    });

    test('an event arriving later raises exactly one system banner', () async {
      final harness = _controller(rows: [_row(id: 'NTF-0001')], unread: 1);
      await harness.controller.load();

      // A new customer reply lands while the app is open.
      harness.server.notifications = [
        _row(
          id: 'NTF-0002',
          type: 'customer_reply',
          title: 'Sanne replied',
          minutesAgo: 0,
        ),
        _row(id: 'NTF-0001'),
      ];
      harness.server.unread = 2;
      await harness.controller.load(silent: true);

      expect(harness.local.shown.length, 1);
      expect(harness.local.shown.single['id'], 'NTF-0002');
      expect(harness.local.shown.single['deliveryId'], 'DLV-1042');
      expect(harness.controller.unreadCount, 2);

      // Syncing the same page again must not repeat the banner.
      await harness.controller.load(silent: true);
      expect(harness.local.shown.length, 1);
    });

    test('an arrival that is already read does not interrupt', () async {
      final harness = _controller(rows: [_row(id: 'NTF-0001')], unread: 1);
      await harness.controller.load();

      harness.server.notifications = [
        _row(id: 'NTF-0003', isRead: true, type: 'customer_update', minutesAgo: 0),
        _row(id: 'NTF-0001'),
      ];
      await harness.controller.load(silent: true);

      expect(harness.local.shown, isEmpty);
    });

    test('markRead updates the badge from the server count', () async {
      final harness = _controller(rows: [_row(id: 'NTF-0001')], unread: 1);
      await harness.controller.load();

      final ok = await harness.controller.markRead('NTF-0001');

      expect(ok, isTrue);
      expect(harness.controller.unreadCount, 0);
      expect(harness.controller.items.single.isRead, isTrue);
      expect(
        harness.server.requests.where((r) => r.startsWith('POST')),
        hasLength(1),
      );
    });

    test('a failed markRead rolls back the optimistic update', () async {
      final harness = _controller(rows: [_row(id: 'NTF-0001')], unread: 1);
      await harness.controller.load();
      harness.server.failPost = true;

      final ok = await harness.controller.markRead('NTF-0001');

      expect(ok, isFalse);
      expect(harness.controller.unreadCount, 1, reason: 'badge must not lie');
      expect(harness.controller.items.single.isRead, isFalse);
      expect(harness.controller.error, isNotNull);
    });

    test('a failing refresh keeps the existing feed', () async {
      final harness = _controller(rows: [_row(id: 'NTF-0001')], unread: 1);
      await harness.controller.load();

      harness.server.failGet = true;
      await harness.controller.load(silent: true);

      expect(harness.controller.items, hasLength(1));
      expect(harness.controller.state, LoadState.ready);
      expect(harness.controller.error, isNotNull);
    });

    test('a failing first load lands in the failure state', () async {
      final harness = _controller()..server.failGet = true;

      await harness.controller.load();

      expect(harness.controller.state, LoadState.failure);
      expect(harness.controller.error, isNotNull);
      expect(harness.controller.items, isEmpty);
    });

    test('a banner tap marks the row read and deep-links to the stop', () async {
      final harness = _controller(rows: [_row(id: 'NTF-0001')], unread: 1);
      await harness.controller.load();

      String? opened;
      harness.controller.onOpenStop = (deliveryId) => opened = deliveryId;

      harness.controller
          .handleTap(encodeNotificationPayload(id: 'NTF-0001', deliveryId: 'DLV-1042'));
      await pumpEventQueue();

      expect(opened, 'DLV-1042');
      expect(harness.controller.unreadCount, 0);
      expect(
        harness.server.requests.where((r) => r.startsWith('POST')),
        hasLength(1),
      );
    });

    test('initSystem reports when the platform cannot show banners', () async {
      final harness = _controller();
      harness.local.initResult = false;

      await harness.controller.initSystem();
      await harness.controller.initSystem();

      expect(harness.controller.systemEnabled, isFalse);
      expect(harness.local.initCalls, 1, reason: 'system setup runs once');
    });
  });

  group('NotificationsScreen', () {
    Future<void> pumpScreen(
      WidgetTester tester, {
      required NotificationsController controller,
      Delivery? delivery,
    }) async {
      final deliveries = DeliveriesController(
        DeliveryRepository(
          ApiClient(baseUrl: () => 'http://unused.test', headers: () => const {}),
        ),
      );
      if (delivery != null) deliveries.items = [delivery];

      // Providers above MaterialApp so pushed routes (DeliveryDetailScreen)
      // can read them - same structure as the real app.
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<NotificationsController>.value(value: controller),
            ChangeNotifierProvider<DeliveriesController>.value(value: deliveries),
          ],
          child: MaterialApp(home: const NotificationsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders the feed, tags demo rows and opens the stop',
        (tester) async {
      final harness = _controller(
        rows: [
          _row(id: 'NTF-0001', minutesAgo: 5),
          _row(
            id: 'NTF-0002',
            type: 'status_changed',
            title: 'Stop needs attention',
            body: 'DLV-1045 was marked failed.',
            deliveryId: 'DLV-1045',
            source: 'service',
            isRead: true,
            minutesAgo: 40,
          ),
        ],
        unread: 1,
      );
      await harness.controller.load();

      await pumpScreen(tester, controller: harness.controller, delivery: _delivery());

      expect(find.text('Stop assigned to you'), findsOneWidget);
      expect(find.text('Stop needs attention'), findsOneWidget);
      expect(find.text('demo'), findsOneWidget);
      expect(find.text('service'), findsNothing,
          reason: 'live rows need no tag');

      await tester.tap(find.text('Stop assigned to you'));
      await tester.pumpAndSettle();

      // Deep link to the delivery detail screen.
      expect(find.text('DLV-1042'), findsOneWidget);
      expect(
        harness.server.requests.where((r) => r.startsWith('POST')),
        hasLength(1),
        reason: 'opening a row marks it read',
      );
    });

    testWidgets('shows the friendly empty state when everything is read',
        (tester) async {
      final harness = _controller();
      await harness.controller.load();

      await pumpScreen(tester, controller: harness.controller);

      expect(find.text('New stops, route changes, customer replies and status updates will show up here.'), findsOneWidget);
      expect(find.text('You are up to date'), findsWidgets);
    });

    testWidgets('warns when system notifications are switched off',
        (tester) async {
      final harness = _controller(rows: [_row(id: 'NTF-0001')], unread: 1);
      await harness.controller.load();
      harness.controller.systemEnabled = false;

      await pumpScreen(tester, controller: harness.controller);

      expect(
        find.text('System notifications are off - updates still appear in this list.'),
        findsOneWidget,
      );
    });

    testWidgets('turns a failed first load into a retry state', (tester) async {
      final harness = _controller()..server.failGet = true;
      await harness.controller.load();

      await pumpScreen(tester, controller: harness.controller);

      expect(find.text('Could not load notifications'), findsOneWidget);

      harness.server.failGet = false;
      harness.server.notifications = [_row(id: 'NTF-0001')];
      harness.server.unread = 1;

      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Stop assigned to you'), findsOneWidget);
      expect(find.text('Could not load notifications'), findsNothing);
    });
  });
}
