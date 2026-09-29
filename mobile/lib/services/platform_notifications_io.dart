import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notifications_service.dart';
import 'platform_call.dart';

/// `flutter_local_notifications` wrapper - Android, iOS and (with the
/// package's web implementation) the browser as well.
///
/// Every plugin call goes through [guardedPlatformCall]: on platforms where
/// the plugin is missing or slow the future may never complete, and the
/// notification feed must keep working regardless.
class PluginNotifications implements LocalNotificationsService {
  static const _channel = AndroidNotificationChannel(
    'delivery_updates',
    'Delivery updates',
    description: 'New stops, route changes, customer replies and status changes.',
    importance: Importance.high,
  );

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  void Function(String payload)? _onTap;
  bool _channelCreated = false;

  @override
  Future<bool> init({required void Function(String payload) onNotificationTap}) async {
    _onTap = onNotificationTap;

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );

    final result = await guardedPlatformCall<bool?>(
      _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null) _onTap?.call(payload);
        },
      ),
      label: 'notifications-init',
    );
    if (!result.ok || result.value != true) return false;

    // Android needs the channel before the first show() (idempotent).
    if (!_channelCreated) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        final channel = await guardedPlatformCall<void>(
          android.createNotificationChannel(_channel),
          label: 'notifications-channel',
        );
        _channelCreated = channel.ok;
      }
    }
    return true;
  }

  @override
  Future<bool?> requestPermission() async {
    // Android 13+: runtime permission for POST_NOTIFICATIONS.
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await guardedPlatformCall<bool?>(
        android.requestNotificationsPermission(),
        label: 'notifications-permission-android',
      );
      if (granted.ok && granted.value != null) return granted.value;
    }

    // iOS: alert/badge/sound permission.
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final granted = await guardedPlatformCall<bool?>(
        ios.requestPermissions(alert: true, badge: true, sound: true),
        label: 'notifications-permission-ios',
      );
      if (granted.ok && granted.value != null) return granted.value;
    }

    return null; // unknown: old OS grants automatically / web asks on show()
  }

  @override
  Future<void> show({
    required String id,
    required String title,
    required String body,
    String? deliveryId,
  }) async {
    // Literals (not _channel.x): const expressions cannot read properties.
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'delivery_updates',
        'Delivery updates',
        channelDescription:
            'New stops, route changes, customer replies and status changes.',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    await guardedPlatformCall<void>(
      _plugin.show(
        id: id.hashCode & 0x7fffffff, // keep the id in the positive int range
        title: title,
        body: body,
        notificationDetails: details,
        payload: encodeNotificationPayload(id: id, deliveryId: deliveryId),
      ),
      label: 'notifications-show',
    );
  }

  @override
  Future<String?> pendingLaunchPayload() async {
    final details = await guardedPlatformCall<NotificationAppLaunchDetails?>(
      _plugin.getNotificationAppLaunchDetails(),
      label: 'notifications-launch-details',
    );
    if (!details.ok) return null;
    return details.value?.didNotificationLaunchApp == true
        ? details.value?.notificationResponse?.payload
        : null;
  }
}

/// Creates the platform's local-notification service.
LocalNotificationsService buildLocalNotifications() => PluginNotifications();
