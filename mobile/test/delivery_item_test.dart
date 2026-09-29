import 'package:delivery_driver/models/delivery.dart';
import 'package:delivery_driver/widgets/delivery_card.dart';
import 'package:delivery_driver/widgets/item_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Delivery _delivery({String imageUrl = ''}) => Delivery.fromJson({
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
      'codAmount': 24.9,
      'currency': 'EUR',
      'item': {
        'name': 'Espresso machine',
        'category': 'Small appliances',
        'sku': 'SKU-ESP-2201',
        'imageUrl': imageUrl,
      },
      'address': {'line1': '18 Kanalstraat', 'city': 'Rotterdam', 'postalCode': '3011 AB'},
      'customer': {'id': 'CUS-8821', 'firstName': 'Sanne', 'lastName': 'de Vries'},
      'notes': <dynamic>[],
      'events': <dynamic>[],
      'history': <dynamic>[],
    });

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('the stop card shows the item name next to the customer', (tester) async {
    await tester.pumpWidget(_wrap(DeliveryCard(delivery: _delivery(), index: 0)));

    expect(find.text('Sanne de Vries'), findsOneWidget);
    expect(find.text('DELIVERING'), findsOneWidget);
    expect(find.text('Espresso machine'), findsOneWidget);
    expect(find.text('Small appliances'), findsOneWidget);
  });

  testWidgets('the stop card falls back to a placeholder when the photo fails',
      (tester) async {
    await tester.pumpWidget(
      _wrap(DeliveryCard(
        delivery: _delivery(imageUrl: 'https://example.invalid/item.jpg'),
        index: 0,
      )),
    );

    // Frames for the request to fail - the errorBuilder must swallow it.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byIcon(Icons.inventory_2_outlined), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an item without a photo never issues a network request', (tester) async {
    await tester.pumpWidget(_wrap(const ItemImage(item: null)));

    await tester.pump();

    expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  test('an item only counts as picture when the URL is remote', () {
    expect(const DeliveryItem(name: 'TV', imageUrl: 'https://cdn/x.jpg').hasImage, isTrue);
    expect(const DeliveryItem(name: 'TV').hasImage, isFalse);
    expect(const DeliveryItem(name: 'TV', imageUrl: '/local/x.jpg').hasImage, isFalse);
  });
}
