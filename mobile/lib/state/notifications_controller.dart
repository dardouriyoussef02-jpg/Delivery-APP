import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_notification.dart';
import '../services/api_client.dart';
import '../services/local_notifications.dart';
import '../services/notifications_repository.dart';
import 'deliveries_controller.dart' show LoadState;

/// Drives the bell badge, the notifications screen and the system banners.
///
/// Banner policy: the first successful load only fills the feed (no banners
/// for history the driver has effectively already seen); every later sync
/// raises a system notification for items that are new *and* unread. Taps
/// deep-link through [onOpenStop].
class NotificationsController extends ChangeNotifier {
  NotificationsController(this._repository, {LocalNotificationsService? local})
      : _local = local ?? buildLocalNotifications();

  final NotificationsRepository _repository;
  final LocalNotificationsService _local;

  LoadState state = LoadState.initial;
  List<AppNotification> items = const [];
  int unreadCount = 0;
  String? error;

  /// False when the OS/browser refused notification permission (or the
  /// platform cannot show system notifications at all).
  bool systemEnabled = true;

  bool updating = false;

  /// Set by the app shell: opens the stop a tapped banner refers to.
  void Function(String deliveryId)? onOpenStop;

  final Set<String> _knownIds = <String>{};
  bool _firstLoadDone = false;
  bool _systemReady = false;

  /// Fetches the feed. Silent refreshes keep stale items on failure.
  Future<void> load({bool silent = false}) async {
    if (updating) return;
    if (!silent) {
      state = LoadState.loading;
      error = null;
      notifyListeners();
    }

    updating = true;
    try {
      final feed = await _repository.fetch();
      _ingest(feed.notifications);
      unreadCount = feed.unreadCount;
      error = null;
      state = LoadState.ready;
    } on ApiException catch (ex) {
      error = ex.message;
      if (items.isEmpty) state = LoadState.failure;
    } catch (_) {
      error = 'Could not load notifications.';
      if (items.isEmpty) state = LoadState.failure;
    }
    updating = false;
    notifyListeners();
  }

  void _ingest(List<AppNotification> incoming) {
    final fresh = incoming.where((item) => !_knownIds.contains(item.id)).toList();
    items = incoming;

    if (_firstLoadDone) {
      // Only genuinely new, still-unread events interrupt the driver.
      for (final item in fresh) {
        if (item.isImportant && !item.isRead) {
          unawaited(_local.show(
            id: item.id,
            title: item.title,
            body: item.body,
            deliveryId: item.deliveryId,
          ));
        }
      }
    }

    _knownIds.addAll(incoming.map((item) => item.id));
    _firstLoadDone = true;
  }

  /// Optimistically marks one row as read; the server count is authoritative.
  Future<bool> markRead(String id) async {
    final index = items.indexWhere((item) => item.id == id);
    if (index < 0) return false;

    final target = items[index];
    if (target.isRead) return true;

    final previousItems = items;
    final previousCount = unreadCount;

    items = [...items]..[index] = target.copyWith(isRead: true);
    unreadCount = previousCount > 0 ? previousCount - 1 : 0;
    notifyListeners();

    try {
      unreadCount = await _repository.markRead(id);
      error = null;
      notifyListeners();
      return true;
    } on ApiException catch (ex) {
      // Roll back so the badge never lies about server state.
      items = previousItems;
      unreadCount = previousCount;
      error = ex.message;
      notifyListeners();
      return false;
    }
  }

  /// One-time system setup: channel, permission, cold-start tap payload.
  Future<void> initSystem() async {
    if (_systemReady) return;
    _systemReady = true;

    try {
      final available = await _local.init(onNotificationTap: handleTap);
      if (!available) {
        systemEnabled = false;
        notifyListeners();
        return;
      }

      final granted = await _local.requestPermission();
      systemEnabled = granted ?? true;

      // Cold start: the app was launched from a tapped notification.
      final payload = await _local.pendingLaunchPayload();
      if (payload != null) handleTap(payload);
    } catch (error) {
      // System notifications are a bonus; the in-app feed keeps working.
      debugPrint('[notifications] system setup unavailable: $error');
      systemEnabled = false;
    }

    notifyListeners();
  }

  /// Banner tap: mark as read and deep-link to the stop.
  void handleTap(String payload) {
    final parsed = decodeNotificationPayload(payload);
    if (parsed == null) return;

    final id = parsed['id'] ?? '';
    if (id.isNotEmpty) unawaited(markRead(id));

    final deliveryId = parsed['deliveryId'] ?? '';
    if (deliveryId.isNotEmpty) onOpenStop?.call(deliveryId);
  }

  AppNotification? byId(String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }
}
