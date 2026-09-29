import 'dart:convert';

import 'package:delivery_driver/models/fleet_stats.dart';
import 'package:delivery_driver/screens/admin_stats_screen.dart';
import 'package:delivery_driver/screens/profile_screen.dart';
import 'package:delivery_driver/services/api_client.dart';
import 'package:delivery_driver/services/delivery_repository.dart';
import 'package:delivery_driver/services/stats_repository.dart';
import 'package:delivery_driver/state/deliveries_controller.dart';
import 'package:delivery_driver/state/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

Map<String, dynamic> _payload() => {
      'generatedAt': DateTime.now().toIso8601String(),
      'source': 'database',
      'totals': {
        'deliveries': 12,
        'customers': 9,
        'drivers': 2,
        'messagesSent': 5,
        'notifications': 7,
        'unreadNotifications': 3,
      },
      'byStatus': {'pending': 4, 'in_transit': 3, 'failed': 1, 'delivered': 4},
      'completion': {'finished': 5, 'completionRate': 0.3333},
      'deliveryTime': {
        'sampleSize': 4,
        'averageMinutes': 42.5,
        'fastestMinutes': 21.0,
        'slowestMinutes': 71.0,
      },
      'perDriver': [
        {
          'driverId': 'DRV-77',
          'name': 'Demo Driver',
          'assigned': 8,
          'delivered': 3,
          'failed': 1,
          'averageMinutes': 40.2,
        },
        {
          'driverId': 'DRV-88',
          'name': 'Second Driver',
          'assigned': 4,
          'delivered': 1,
          'failed': 0,
          'averageMinutes': null,
        },
      ],
      'recentActivity': [
        {
          'deliveryId': 'DLV-1045',
          'fromStatus': 'in_transit',
          'toStatus': 'delivered',
          'label': 'Handed over in person',
          'changedBy': 'DRV-77',
          'changedAt': DateTime.now()
              .subtract(const Duration(minutes: 12))
              .toIso8601String(),
        },
      ],
    };

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  group('FleetStats model', () {
    test('parses the backend payload including null averages', () {
      final stats = FleetStats.fromJson(_payload());

      expect(stats.totals['deliveries'], 12);
      expect(stats.byStatus['delivered'], 4);
      expect(stats.delivered, 4);
      expect(stats.failed, 1);
      expect(stats.open, 7, reason: 'pending + in_transit');
      expect(stats.completionRate, 0.3333);
      expect(stats.finished, 5);
      expect(stats.sampleSize, 4);
      expect(stats.averageMinutes, 42.5);
      expect(stats.fastestMinutes, 21.0);
      expect(stats.slowestMinutes, 71.0);
      expect(stats.perDriver, hasLength(2));
      expect(stats.perDriver[0].averageMinutes, 40.2);
      expect(stats.perDriver[1].averageMinutes, isNull);
      expect(stats.recentActivity.single['deliveryId'], 'DLV-1045');
    });

    test('tolerates a payload without optional sections', () {
      final stats = FleetStats.fromJson(const {
        'generatedAt': '2026-09-28T10:00:00.000Z',
        'totals': <String, dynamic>{},
        'byStatus': <String, dynamic>{},
        'completion': <String, dynamic>{'completionRate': 0, 'finished': 0},
        'deliveryTime': <String, dynamic>{},
      });

      expect(stats.sampleSize, 0);
      expect(stats.averageMinutes, isNull);
      expect(stats.perDriver, isEmpty);
      expect(stats.recentActivity, isEmpty);
      expect(stats.completionRate, 0);
    });
  });

  group('AdminStatsScreen', () {
    StatsRepository repositoryWith(MockClientHandler handler) =>
        StatsRepository(
          ApiClient(
            baseUrl: () => 'http://admin.test',
            headers: () => const {},
            client: MockClient(handler),
          ),
        );

    testWidgets('renders the numbers aggregated by the backend', (tester) async {
      // Tall viewport so every card in the dashboard builds (ListView is
      // lazy - below-the-fold cards would otherwise not exist yet).
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final screen = AdminStatsScreen(
        repository: repositoryWith((request) async => _json(_payload())),
      );

      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();

      expect(find.text('Fleet statistics'), findsOneWidget);
      expect(find.text('33% done'), findsOneWidget);
      expect(find.text('42.5 min'), findsOneWidget);
      expect(find.textContaining('Based on 4 completed deliveries'), findsOneWidget);
      expect(find.text('Demo Driver'), findsOneWidget);
      expect(find.textContaining('avg 40.2 min'), findsOneWidget);
      expect(find.text('Second Driver'), findsOneWidget);
      expect(find.textContaining('DRV-88 \u00b7 4 stops'), findsOneWidget);
      expect(
        find.textContaining('DLV-1045 \u00b7 in_transit \u2192 delivered'),
        findsOneWidget,
      );
      expect(find.text('Messages sent'), findsOneWidget);
    });

    testWidgets('shows the server error and can retry', (tester) async {
      var failing = true;
      final screen = AdminStatsScreen(
        repository: repositoryWith((request) async {
          if (failing) return _json({'error': 'admin role required'}, status: 403);
          return _json(_payload());
        }),
      );

      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();

      expect(find.text('Could not load statistics'), findsOneWidget);
      expect(find.textContaining('admin role required'), findsOneWidget);

      failing = false;
      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      await tester.pumpAndSettle();

      expect(find.text('33% done'), findsOneWidget);
      expect(find.text('Could not load statistics'), findsNothing);
    });
  });

  group('Profile role gate', () {
    Future<void> pumpProfile(WidgetTester tester, {required String role}) async {
      // Tall viewport so the whole settings list builds (no scrolling needed).
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final session = SessionController()..driverRole = role;
      final deliveries = DeliveriesController(
        DeliveryRepository(
          ApiClient(baseUrl: () => 'http://unused.test', headers: () => const {}),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<SessionController>.value(value: session),
              ChangeNotifierProvider<DeliveriesController>.value(value: deliveries),
            ],
            child: const ProfileScreen(),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('admins see the fleet statistics entry', (tester) async {
      await pumpProfile(tester, role: 'admin');

      expect(find.text('Fleet statistics'), findsOneWidget);
      expect(find.text('Administration'), findsOneWidget);
    });

    testWidgets('regular drivers do not', (tester) async {
      await pumpProfile(tester, role: 'driver');

      expect(find.text('Fleet statistics'), findsNothing);
      expect(find.text('Administration'), findsNothing);
    });
  });
}
