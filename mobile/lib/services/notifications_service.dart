import 'dart:convert';

/// Abstraction over the device's local notification system.
///
/// The platform implementation is selected at compile time (see
/// `local_notifications.dart`): Android/iOS get `flutter_local_notifications`,
/// platforms without a plugin (web) get a no-op - the in-app feed keeps
/// working either way, so nothing ever throws because a plugin is missing.
abstract class LocalNotificationsService {
  /// Prepares the plugin/channel and wires tap callbacks.
  ///
  /// Returns false when the platform has no notification support.
  Future<bool> init({required void Function(String payload) onNotificationTap});

  /// Asks for notification permission (Android 13+/iOS).
  ///
  /// Returns true when granted, false when denied, null when unknown
  /// (older OS versions grant automatically / plugin unavailable).
  Future<bool?> requestPermission();

  /// Shows one notification; silently degrades when unsupported.
  Future<void> show({
    required String id,
    required String title,
    required String body,
    String? deliveryId,
  });

  /// True when a launch or a tap delivered a notification payload.
  Future<String?> pendingLaunchPayload();
}

/// Payload format: a small JSON object so taps can deep-link and mark-read.
String encodeNotificationPayload({required String id, String? deliveryId}) {
  return jsonEncode({'id': id, 'deliveryId': deliveryId});
}

Map<String, String>? decodeNotificationPayload(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    return <String, String>{
      'id': decoded['id']?.toString() ?? '',
      'deliveryId': decoded['deliveryId']?.toString() ?? '',
    };
  } catch (_) {
    return null;
  }
}

/// Fallback used when the platform cannot show system notifications.
class NoopNotifications implements LocalNotificationsService {
  @override
  Future<bool> init({required void Function(String payload) onNotificationTap}) async => false;

  @override
  Future<bool?> requestPermission() async => null;

  @override
  Future<void> show({
    required String id,
    required String title,
    required String body,
    String? deliveryId,
  }) async {}

  @override
  Future<String?> pendingLaunchPayload() async => null;
}
