import 'package:flutter/foundation.dart';

/// One driver's row of the admin breakdown.
@immutable
class DriverStat {
  const DriverStat({
    required this.driverId,
    required this.name,
    required this.assigned,
    required this.delivered,
    required this.failed,
    this.averageMinutes,
  });

  final String driverId;
  final String name;
  final int assigned;
  final int delivered;
  final int failed;
  final double? averageMinutes;

  factory DriverStat.fromJson(Map<String, dynamic> json) => DriverStat(
        driverId: json['driverId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        assigned: (json['assigned'] as num?)?.toInt() ?? 0,
        delivered: (json['delivered'] as num?)?.toInt() ?? 0,
        failed: (json['failed'] as num?)?.toInt() ?? 0,
        averageMinutes: (json['averageMinutes'] as num?)?.toDouble(),
      );
}

/// Aggregated fleet statistics - mirrors `GET /api/v1/stats` exactly.
/// Every value is computed by the backend from its database.
@immutable
class FleetStats {
  const FleetStats({
    required this.generatedAt,
    required this.totals,
    required this.byStatus,
    required this.completionRate,
    required this.finished,
    required this.deliveryTime,
    required this.perDriver,
    required this.recentActivity,
  });

  final DateTime generatedAt;

  /// totals keys: deliveries, customers, drivers, messagesSent,
  /// notifications, unreadNotifications.
  final Map<String, int> totals;
  final Map<String, int> byStatus;
  final double completionRate;
  final int finished;

  /// deliveryTime keys: sampleSize, averageMinutes, fastestMinutes,
  /// slowestMinutes (minutes are null while nothing is delivered yet).
  final Map<String, num?> deliveryTime;
  final List<DriverStat> perDriver;
  final List<Map<String, dynamic>> recentActivity;

  int get delivered => byStatus['delivered'] ?? 0;
  int get failed => byStatus['failed'] ?? 0;
  int get open => (byStatus['pending'] ?? 0) + (byStatus['in_transit'] ?? 0);

  int get sampleSize => deliveryTime['sampleSize']?.toInt() ?? 0;
  double? get averageMinutes => deliveryTime['averageMinutes']?.toDouble();
  double? get fastestMinutes => deliveryTime['fastestMinutes']?.toDouble();
  double? get slowestMinutes => deliveryTime['slowestMinutes']?.toDouble();

  factory FleetStats.fromJson(Map<String, dynamic> json) {
    Map<String, int> intMap(Object? value) {
      if (value is! Map) return const {};
      return {
        for (final entry in value.entries)
          entry.key.toString(): (entry.value as num?)?.toInt() ?? 0,
      };
    }

    Map<String, num?> numMap(Object? value) {
      if (value is! Map) return const {};
      return {
        for (final entry in value.entries)
          entry.key.toString(): entry.value is num ? entry.value as num : null,
      };
    }

    final completion = json['completion'] is Map
        ? (json['completion'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};

    return FleetStats(
      generatedAt: DateTime.tryParse(json['generatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      totals: intMap(json['totals']),
      byStatus: intMap(json['byStatus']),
      completionRate: (completion['completionRate'] as num?)?.toDouble() ?? 0,
      finished: (completion['finished'] as num?)?.toInt() ?? 0,
      deliveryTime: numMap(json['deliveryTime']),
      perDriver: ((json['perDriver'] as List?) ?? const [])
          .whereType<Map>()
          .map((row) => DriverStat.fromJson(row.cast<String, dynamic>()))
          .toList(),
      recentActivity: ((json['recentActivity'] as List?) ?? const [])
          .whereType<Map>()
          .map((row) => row.cast<String, dynamic>())
          .toList(),
    );
  }
}
