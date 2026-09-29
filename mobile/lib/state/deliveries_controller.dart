import 'package:flutter/foundation.dart';

import '../models/delivery.dart';
import '../services/api_client.dart';
import '../services/delivery_repository.dart';

enum DeliveryFilter { all, todo, attention }

enum LoadState { initial, loading, ready, failure }

/// Holds the driver's stops: loading, filtering, search and status updates.
class DeliveriesController extends ChangeNotifier {
  DeliveriesController(this._repository);

  final DeliveryRepository _repository;

  LoadState state = LoadState.initial;
  List<Delivery> items = const [];
  bool offline = false;
  String? error;
  DeliveryFilter filter = DeliveryFilter.all;
  String query = '';
  bool updating = false;

  Future<void> load({String? driverId, bool silent = false}) async {
    if (!silent) {
      state = LoadState.loading;
      error = null;
      notifyListeners();
    }

    try {
      final result = await _repository.fetchDeliveries(driverId: driverId);
      items = result.deliveries
        ..sort((a, b) => a.sequence.compareTo(b.sequence));
      offline = result.offline;
      error = null;
      state = LoadState.ready;
    } on ApiException catch (ex) {
      error = ex.message;
      state = LoadState.failure;
    } catch (_) {
      error = 'Unexpected error while loading the route.';
      state = LoadState.failure;
    }

    notifyListeners();
  }

  void setFilter(DeliveryFilter value) {
    if (filter == value) return;
    filter = value;
    notifyListeners();
  }

  void setQuery(String value) {
    if (query == value) return;
    query = value;
    notifyListeners();
  }

  List<Delivery> get visible {
    final needle = query.trim().toLowerCase();

    return items.where((delivery) {
      final matchesFilter = switch (filter) {
        DeliveryFilter.all => true,
        DeliveryFilter.todo =>
          delivery.status == DeliveryStatus.pending || delivery.status == DeliveryStatus.inTransit,
        DeliveryFilter.attention => delivery.needsAttention,
      };
      if (!matchesFilter) return false;
      if (needle.isEmpty) return true;

      return delivery.id.toLowerCase().contains(needle) ||
          delivery.customer.fullName.toLowerCase().contains(needle) ||
          delivery.address.singleLine.toLowerCase().contains(needle) ||
          delivery.zone.toLowerCase().contains(needle) ||
          (delivery.item?.name.toLowerCase().contains(needle) ?? false) ||
          (delivery.item?.category.toLowerCase().contains(needle) ?? false) ||
          delivery.notes.any((note) => note.text.toLowerCase().contains(needle));
    }).toList();
  }

  int get doneCount => items.where((delivery) => delivery.status.isFinished).length;

  int get todoCount =>
      items.where((delivery) => delivery.status == DeliveryStatus.pending || delivery.status == DeliveryStatus.inTransit).length;

  int get attentionCount => items.where((delivery) => delivery.needsAttention).length;

  double get remainingKm => items
      .where((delivery) => !delivery.status.isFinished)
      .fold(0.0, (sum, delivery) => sum + delivery.distanceKm);

  Delivery? byId(String id) {
    for (final delivery in items) {
      if (delivery.id == id) return delivery;
    }
    return null;
  }

  /// Optimistically flips the status, rolling back when the API refuses.
  Future<bool> updateStatus(String id, DeliveryStatus status, {String? label}) async {
    final original = byId(id);
    if (original == null) return false;

    updating = true;
    items = [
      for (final delivery in items)
        delivery.id == id ? delivery.copyWith(status: status) : delivery,
    ];
    notifyListeners();

    try {
      final updated = await _repository.updateStatus(id, status, label: label);
      items = [
        for (final delivery in items) delivery.id == id ? updated : delivery,
      ];
      updating = false;
      notifyListeners();
      return true;
    } on ApiException catch (ex) {
      items = [
        for (final delivery in items) delivery.id == id ? original : delivery,
      ];
      error = ex.message;
      updating = false;
      notifyListeners();
      return false;
    }
  }
}
