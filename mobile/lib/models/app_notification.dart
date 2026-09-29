import 'package:flutter/foundation.dart';

/// One row of the driver's notification feed (backend `NTF-` ids).
@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.deliveryId,
    required this.source,
    required this.isRead,
    required this.createdAt,
  });

  final String id;

  /// `delivery_assigned` | `assignment_changed` | `customer_update` |
  /// `customer_reply` | `status_changed`.
  final String type;

  final String title;
  final String body;

  /// When set, tapping the notification opens this stop (deep link).
  final String? deliveryId;

  /// `service` for real runtime events, `demo` for the seeded demo dataset.
  final String source;

  final bool isRead;
  final DateTime createdAt;

  /// Types that are worth interrupting the driver for with a system banner.
  static const importantTypes = <String>{
    'delivery_assigned',
    'assignment_changed',
    'customer_update',
    'customer_reply',
    'status_changed',
  };

  bool get isImportant => importantTypes.contains(type);

  /// True when the feed row came from the demo dataset standing in for the
  /// customer/dispatch systems (shown as a small tag so nothing masquerades
  /// as a live event).
  bool get isDemo => source == 'demo';

  bool get opensStop => deliveryId != null && deliveryId!.isNotEmpty;

  AppNotification copyWith({bool? isRead}) => AppNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        deliveryId: deliveryId,
        source: source,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt,
      );

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      deliveryId: (json['deliveryId'] as String?)?.isNotEmpty == true
          ? json['deliveryId'] as String
          : null,
      source: json['source'] as String? ?? 'service',
      isRead: json['isRead'] == true,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  @override
  bool operator ==(Object other) => other is AppNotification && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
