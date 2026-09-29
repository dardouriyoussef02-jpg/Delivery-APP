import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../models/delivery.dart';
import 'section_card.dart';
import 'status_chip.dart';

/// One stop in the route list.
class DeliveryCard extends StatelessWidget {
  const DeliveryCard({
    super.key,
    required this.delivery,
    required this.index,
    this.onTap,
  });

  final Delivery delivery;
  final int index;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finished = delivery.status.isFinished;
    final active = delivery.status == DeliveryStatus.inTransit;
    final note = delivery.primaryNote;

    return Container(
      decoration: AppTheme.cardDecoration,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Opacity(
            opacity: finished ? 0.62 : 1,
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StopBadge(
                    index: index + 1,
                    status: delivery.status,
                    active: active,
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                delivery.customer.fullName,
                                style: theme.textTheme.titleMedium?.copyWith(fontSize: 16.5),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            StatusChip(status: delivery.status, compact: true),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          delivery.address.singleLine,
                          style: theme.textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 11),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            MetaPill(
                              icon: Icons.flag_outlined,
                              label: relativeTime(delivery.eta),
                              color: AppTheme.accent,
                            ),
                            MetaPill(
                                icon: Icons.near_me_outlined,
                                label: distance(delivery.distanceKm)),
                            if (delivery.parcels > 1)
                              MetaPill(
                                icon: Icons.inventory_2_outlined,
                                label: plural(delivery.parcels, 'parcel'),
                              ),
                            if (delivery.codAmount > 0)
                              MetaPill(
                                icon: Icons.payments_outlined,
                                label: money(delivery.codAmount, delivery.currency),
                                color: AppTheme.warning,
                              ),
                          ],
                        ),
                        if (note != null) ...[
                          const SizedBox(height: 11),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                            decoration: BoxDecoration(
                              color: note.fromCustomer
                                  ? AppTheme.brand.withValues(alpha: 0.07)
                                  : AppTheme.surfaceAlt,
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(
                                color: note.fromCustomer
                                    ? AppTheme.brand.withValues(alpha: 0.22)
                                    : AppTheme.hairline,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  note.fromCustomer
                                      ? Icons.auto_awesome_outlined
                                      : Icons.person_outline,
                                  size: 15,
                                  color:
                                      note.fromCustomer ? AppTheme.brand : AppTheme.inkMuted,
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    preview(note.text),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: AppTheme.ink.withValues(alpha: 0.82),
                                      height: 1.35,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StopBadge extends StatelessWidget {
  const _StopBadge({required this.index, required this.status, required this.active});

  final int index;
  final DeliveryStatus status;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final delivered = status == DeliveryStatus.delivered;

    final BoxDecoration decoration = delivered
        ? const BoxDecoration(color: AppTheme.success, shape: BoxShape.circle)
        : active
            ? BoxDecoration(
                color: AppTheme.brand,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.brand.withValues(alpha: 0.45),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              )
            : BoxDecoration(
                color: AppTheme.surfaceAlt,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.hairline, width: 1.4),
              );

    return Container(
      width: 36,
      height: 36,
      decoration: decoration,
      alignment: Alignment.center,
      child: delivered
          ? const Icon(Icons.check_rounded, size: 19, color: AppTheme.onBrand)
          : Text(
              '$index',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: active ? AppTheme.onBrand : AppTheme.inkMuted,
              ),
            ),
    );
  }
}
