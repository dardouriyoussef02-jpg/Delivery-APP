import 'package:delivery_driver/models/delivery.dart';
import 'package:delivery_driver/screens/map_screen.dart';
import 'package:delivery_driver/services/api_client.dart';
import 'package:delivery_driver/services/delivery_repository.dart';
import 'package:delivery_driver/services/location_service.dart';
import 'package:delivery_driver/state/deliveries_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Location stub: every permission/GPS state can be played without touching
/// a platform channel, and the settings actions are observable.
class _FakeLocationService implements LocationService {
  _FakeLocationService([this.result = const LocationResult(
        LocationState.ready,
        DriverPosition(lat: 51.921, lng: 4.475),
      )]);

  LocationResult result;
  int checks = 0;
  int appSettingsOpens = 0;
  int locationSettingsOpens = 0;

  @override
  Future<LocationResult> currentLocation() async {
    checks += 1;
    return result;
  }

  @override
  Future<void> openAppSettings() async => appSettingsOpens += 1;

  @override
  Future<void> openLocationSettings() async => locationSettingsOpens += 1;
}

Widget _app({required LocationService location, bool withDelivery = true}) {
  final deliveries = DeliveriesController(
    DeliveryRepository(
      ApiClient(baseUrl: () => 'http://unused.test', headers: () => const {}),
    ),
  );
  if (withDelivery) deliveries.items = [_delivery()];

  // tileUrlTemplate: null renders markers without network tiles, so the map
  // itself is verifiable inside a widget test.
  return MaterialApp(
    home: ChangeNotifierProvider<DeliveriesController>.value(
      value: deliveries,
      child: MapScreen(
        deliveryId: 'DLV-1042',
        locationService: location,
        tileUrlTemplate: null,
      ),
    ),
  );
}

void main() {
  testWidgets('shows pickup, destination, driver and route when ready',
      (tester) async {
    await tester.pumpWidget(_app(location: _FakeLocationService()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('marker-pickup')), findsOneWidget);
    expect(find.byKey(const ValueKey('marker-destination')), findsOneWidget);
    expect(find.byKey(const ValueKey('marker-driver')), findsOneWidget);

    // Stop card with the existing external navigation handoff.
    expect(find.text('Sanne de Vries'), findsOneWidget);
    expect(find.textContaining('18 Kanalstraat'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Navigate'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Open stop'), findsOneWidget);
  });

  testWidgets('permission denied shows an actionable card, then recovers',
      (tester) async {
    final location = _FakeLocationService(
      const LocationResult(LocationState.permissionDenied),
    );
    await tester.pumpWidget(_app(location: location));
    await tester.pumpAndSettle();

    expect(find.text('Location access needed'), findsOneWidget);
    expect(find.byKey(const ValueKey('marker-pickup')), findsNothing,
        reason: 'no map without permission');

    // "Allow location" re-runs the lookup (which triggers the OS dialog).
    location.result = const LocationResult(
      LocationState.ready,
      DriverPosition(lat: 51.921, lng: 4.475),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Allow location'));
    await tester.pumpAndSettle();

    expect(location.checks, 2);
    expect(find.byKey(const ValueKey('marker-destination')), findsOneWidget);
  });

  testWidgets('permission denied forever points to system settings',
      (tester) async {
    final location = _FakeLocationService(
      const LocationResult(LocationState.permissionDeniedForever),
    );
    await tester.pumpWidget(_app(location: location));
    await tester.pumpAndSettle();

    expect(find.text('Location is blocked'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Open settings'));
    await tester.pumpAndSettle();

    expect(location.appSettingsOpens, 1);
    expect(location.checks, 2, reason: 're-check after returning from settings');
  });

  testWidgets('GPS switched off offers the OS location settings', (tester) async {
    final location = _FakeLocationService(
      const LocationResult(LocationState.serviceDisabled),
    );
    await tester.pumpWidget(_app(location: location));
    await tester.pumpAndSettle();

    expect(find.text('GPS is switched off'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Turn on location'));
    await tester.pumpAndSettle();

    expect(location.locationSettingsOpens, 1);
  });

  testWidgets('an unavailable position still renders stops and route',
      (tester) async {
    final location = _FakeLocationService(
      const LocationResult(LocationState.unavailable),
    );
    await tester.pumpWidget(_app(location: location));
    await tester.pumpAndSettle();

    expect(find.textContaining('Your position is unavailable'), findsOneWidget);
    expect(find.byKey(const ValueKey('marker-pickup')), findsOneWidget);
    expect(find.byKey(const ValueKey('marker-destination')), findsOneWidget);
    expect(find.byKey(const ValueKey('marker-driver')), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Navigate'), findsOneWidget);
  });

  testWidgets(
      'the real geolocator degrades gracefully when the platform is missing',
      (tester) async {
    // No plugin in the test environment: the guarded platform call times out
    // and the screen must land on the friendly fallback, not hang or crash.
    await tester.pumpWidget(_app(location: const GeolocatorLocationService()));

    await tester.pump(const Duration(seconds: 2)); // let the guard time out
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Your position is unavailable'), findsOneWidget);
    expect(find.byKey(const ValueKey('marker-destination')), findsOneWidget);
  });

  testWidgets('a missing delivery shows the safe fallback', (tester) async {
    await tester.pumpWidget(
      _app(location: _FakeLocationService(), withDelivery: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('This stop is no longer available.'), findsOneWidget);
  });
}

Delivery _delivery() => Delivery.fromJson({
      'id': 'DLV-1042',
      'status': 'in_transit',
      'zone': 'Riverside',
      'sequence': 3,
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
        'accessHint': 'Buzzer is broken',
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
