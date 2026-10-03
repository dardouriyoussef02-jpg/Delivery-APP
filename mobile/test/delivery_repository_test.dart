import 'package:delivery_driver/services/api_client.dart';
import 'package:delivery_driver/services/delivery_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The bundled demo route belongs to exactly one driver. When the backend is
/// unreachable it must not be handed to whoever happens to be signed in -
/// an empty queue behind the offline banner is honest, someone else's stops
/// are not.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DeliveryRepository unreachableBackend() {
    final client = MockClient((_) async => throw http.ClientException('network down'));
    return DeliveryRepository(
      ApiClient(
        baseUrl: () => 'http://unreachable.test',
        headers: () => const {},
        client: client,
      ),
    );
  }

  test('the offline copy goes to the demo driver as his own route', () async {
    final result = await unreachableBackend().fetchDeliveries(driverId: 'DRV-77');

    expect(result.offline, isTrue);
    expect(result.deliveries, hasLength(10));
    expect(result.deliveries.every((stop) => stop.driverId == 'DRV-77'), isTrue);
  });

  test('any other driver falls back to an empty queue, not his stops', () async {
    final result = await unreachableBackend().fetchDeliveries(driverId: 'DRV-22');

    expect(result.offline, isTrue);
    expect(result.deliveries, isEmpty);
  });

  test('an unreachable stop reports that stop, never a different one', () async {
    final repository = unreachableBackend();

    await expectLater(
      repository.fetchDelivery('DLV-2002'),
      throwsA(isA<ApiException>()),
      reason: 'the demo asset has no DLV-2002, so no substitute may be shown',
    );
  });
}
