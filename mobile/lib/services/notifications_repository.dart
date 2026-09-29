import '../models/app_notification.dart';
import 'api_client.dart';

/// One page of the driver's notification feed.
class NotificationsFeed {
  const NotificationsFeed({required this.notifications, required this.unreadCount});

  final List<AppNotification> notifications;
  final int unreadCount;
}

/// Thin REST wrapper for GET/POST `/api/v1/notifications` (auth via the
/// session's ApiClient callbacks - this class never sees the token).
class NotificationsRepository {
  NotificationsRepository(this._api);

  final ApiClient _api;

  Future<NotificationsFeed> fetch({bool unreadOnly = false}) async {
    final data = await _api.get(
      '/api/v1/notifications${unreadOnly ? '?unread=1' : ''}',
    );

    final notifications = <AppNotification>[];
    if (data is Map && data['notifications'] is List) {
      for (final row in data['notifications'] as List) {
        if (row is Map) {
          notifications.add(AppNotification.fromJson(row.cast<String, dynamic>()));
        }
      }
    }

    final unread = data is Map && data['unreadCount'] is num
        ? (data['unreadCount'] as num).toInt()
        : notifications.where((item) => !item.isRead).length;

    return NotificationsFeed(notifications: notifications, unreadCount: unread);
  }

  /// Marks one row as read; returns the server's fresh unread count.
  Future<int> markRead(String id) async {
    final data = await _api.post('/api/v1/notifications/$id/read');
    if (data is Map && data['unreadCount'] is num) {
      return (data['unreadCount'] as num).toInt();
    }
    return 0;
  }
}
