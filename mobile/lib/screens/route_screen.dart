import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../models/delivery.dart';
import '../state/deliveries_controller.dart';
import '../widgets/item_image.dart';
import '../widgets/section_card.dart';
import 'delivery_detail_screen.dart';
import 'home_shell.dart';
import 'map_screen.dart';

/// Ordered overview of the whole shift with progress and per-stop shortcuts.
class RouteScreen extends StatelessWidget {
  const RouteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DeliveriesController>();
    final theme = Theme.of(context);
    final deliveries = [...controller.items]..sort((a, b) => a.sequence.compareTo(b.sequence));

    // Next unfinished stop (falls back to the first stop of the route).
    Delivery? nextStop() {
      for (final delivery in deliveries) {
        if (!delivery.status.isFinished) return delivery;
      }
      return deliveries.isEmpty ? null : deliveries.first;
    }

    final target = nextStop();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Route overview'),
        actions: [
          IconButton(
            tooltip: 'Map of the next stop',
            onPressed: target == null
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MapScreen(deliveryId: target.id),
                      ),
                    ),
            icon: const Icon(Icons.map_outlined),
          ),
        ],
      ),
      body: deliveries.isEmpty
          ? const EmptyState(
              icon: Icons.route_outlined,
              title: 'No stops yet',
              message: 'Pull to refresh your route from the Deliveries tab.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _ProgressCard(
                  done: controller.doneCount,
                  total: deliveries.length,
                  remainingKm: controller.remainingKm,
                ),
                const SizedBox(height: 16),
                Text('Stops in order', style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                for (var index = 0; index < deliveries.length; index++)
                  _RouteTile(
                    delivery: deliveries[index],
                    position: index + 1,
                    isLast: index == deliveries.length - 1,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DeliveryDetailScreen(deliveryId: deliveries[index].id),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.done, required this.total, required this.remainingKm});

  final int done;
  final int total;
  final double remainingKm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = total == 0 ? 0.0 : done / total;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('$done of $total stops completed',
                    style: theme.textTheme.titleMedium),
              ),
              Text('${(progress * 100).round()}%',
                  style: theme.textTheme.titleMedium?.copyWith(color: AppTheme.brand)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: AppTheme.surfaceHigh,
              color: AppTheme.brand,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              MetaPill(icon: Icons.near_me_outlined, label: '${distance(remainingKm)} to go'),
              const SizedBox(width: 8),
              const MetaPill(
                icon: Icons.local_shipping_outlined,
                label: 'On shift',
                color: AppTheme.success,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RouteTile extends StatelessWidget {
  const _RouteTile({
    required this.delivery,
    required this.position,
    required this.isLast,
    required this.onTap,
  });

  final Delivery delivery;
  final int position;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final delivered = delivery.status.isFinished;
    final active = delivery.status == DeliveryStatus.inTransit;
    final item = delivery.item;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 34,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: delivered
                        ? AppTheme.success
                        : active
                            ? AppTheme.brand
                            : AppTheme.surfaceAlt,
                    border: delivered || active
                        ? null
                        : Border.all(color: AppTheme.hairline, width: 1.4),
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: AppTheme.brand.withValues(alpha: 0.45),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: delivered
                      ? const Icon(Icons.check_rounded, size: 17, color: AppTheme.onBrand)
                      : Text(
                          '$position',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: active ? AppTheme.onBrand : AppTheme.inkMuted,
                          ),
                        ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: delivered ? AppTheme.success : AppTheme.hairline,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                margin: EdgeInsets.only(bottom: isLast ? 0 : 10),
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: AppTheme.surface.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.hairline),
                  boxShadow: AppTheme.cardShadow,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(delivery.customer.fullName,
                              style: theme.textTheme.titleMedium?.copyWith(fontSize: 15)),
                          if (item != null) ...[
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                ItemImage(item: item, width: 30, height: 30, radius: 9, iconSize: 15),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    item.name,
                                    style: theme.textTheme.bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 2),
                          Text(
                            '${delivery.zone} \u00b7 ${timeOfDay(delivery.eta)} \u00b7 '
                            '${distance(delivery.distanceKm)}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: delivered ? AppTheme.success : AppTheme.inkFaint,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
