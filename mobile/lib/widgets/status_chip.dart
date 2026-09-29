import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/delivery.dart';

/// Compact pill showing the status of a stop. Colours come from the theme's
/// status extension, which is tuned to pop on the dark canvas.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status, this.compact = false});

  final DeliveryStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 11, vertical: compact ? 4 : 5),
      decoration: BoxDecoration(
        color: status.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: status.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: compact ? 13 : 15, color: status.color),
          const SizedBox(width: 5),
          Text(
            status.label,
            style: TextStyle(
              fontSize: compact ? 11.5 : 12.5,
              fontWeight: FontWeight.w800,
              color: status.color,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}
