import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/delivery.dart';
import 'api_client.dart';

/// Reads and updates deliveries through the existing API, with an automatic
/// fall-back to the bundled demo dataset when the backend is unreachable, so a
/// demo never ends on a blank screen.
class DeliveryRepository {
  DeliveryRepository(this._api);

  final ApiClient _api;

  static const _demoAsset = 'assets/demo/deliveries.json';

  /// Returns the driver's stops plus whether they came from the live API.
  Future<({List<Delivery> deliveries, bool offline})> fetchDeliveries({String? driverId}) async {
    try {
      final query = driverId == null ? '' : '?driverId=${Uri.encodeQueryComponent(driverId)}';
      final data = await _api.get('/api/v1/deliveries$query');
      final rows = (data is Map ? data['deliveries'] : null) as List? ?? const [];
      final deliveries = rows
          .map((row) => Delivery.fromJson((row as Map).cast<String, dynamic>()))
          .toList();
      return (deliveries: deliveries, offline: false);
    } on ApiException catch (error) {
      if (!error.offline) rethrow;
      return (deliveries: await _loadDemoDeliveries(driverId), offline: true);
    }
  }

  Future<Delivery> fetchDelivery(String id) async {
    try {
      final data = await _api.get('/api/v1/deliveries/$id');
      return Delivery.fromJson((data as Map).cast<String, dynamic>());
    } on ApiException catch (error) {
      if (!error.offline) rethrow;
      final all = await _loadDemoDeliveries();
      // Only ever this stop. Falling back to "some other delivery" would show
      // a driver a stop that was never theirs.
      return all.firstWhere(
        (delivery) => delivery.id == id,
        orElse: () => throw ApiException('Delivery $id is not available right now.'),
      );
    }
  }

  Future<Delivery> updateStatus(
    String id,
    DeliveryStatus status, {
    String? label,
  }) async {
    final data = await _api.patch('/api/v1/deliveries/$id/status', body: {
      'status': status.wire,
      if (label != null) 'label': label,
    });
    return Delivery.fromJson((data as Map).cast<String, dynamic>());
  }

  /// The bundled demo route, scoped to [driverId].
  ///
  /// The asset is one demo driver's route. Any other account must get an empty
  /// list rather than a queue of stops that belong to somebody else - an empty
  /// queue with the offline banner is honest, someone else's work is not.
  Future<List<Delivery>> _loadDemoDeliveries([String? driverId]) async {
    final raw = await rootBundle.loadString(_demoAsset);
    final payload = jsonDecode(raw) as Map<String, dynamic>;
    final rows = payload['deliveries'] as List? ?? const [];
    return rows
        .map((row) => Delivery.fromJson((row as Map).cast<String, dynamic>()))
        .where((delivery) => driverId == null || delivery.driverId == driverId)
        .toList();
  }
}
