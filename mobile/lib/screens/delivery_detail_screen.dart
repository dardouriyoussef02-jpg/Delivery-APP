import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../models/delivery.dart';
import '../services/contact_actions.dart';
import '../state/assistant_controller.dart';
import '../state/deliveries_controller.dart';
import '../state/notifications_controller.dart';
import '../state/session_controller.dart';
import '../widgets/item_image.dart';
import '../widgets/section_card.dart';
import '../widgets/status_chip.dart';
import 'assistant_sheet.dart';
import 'map_screen.dart';

/// One stop in full detail: customer, address, notes, timeline - and the AI
/// assistant entry point.
class DeliveryDetailScreen extends StatelessWidget {
  const DeliveryDetailScreen({super.key, required this.deliveryId});

  final String deliveryId;

  void _openAssistant(BuildContext context, {String? note}) {
    final delivery = context.read<DeliveriesController>().byId(deliveryId);
    if (delivery == null) return;

    final controller = context.read<AssistantController>();
    controller.prepare(delivery, initialNote: note);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const AssistantSheet(),
    );

    final session = context.read<SessionController>();
    if (session.autoSuggest) {
      controller.analyze();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DeliveriesController>();
    final delivery = controller.byId(deliveryId);
    final theme = Theme.of(context);

    if (delivery == null) {
      return Scaffold(
        appBar: AppBar(title: Text(deliveryId)),
        body: const Center(child: Text('This stop is no longer available.')),
      );
    }

    final canComplete = delivery.status != DeliveryStatus.delivered;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(delivery.id),
            const SizedBox(width: 10),
            StatusChip(status: delivery.status, compact: true),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _Header(delivery: delivery),
          const SizedBox(height: 12),
          if (delivery.item != null) ...[
            _ItemCard(item: delivery.item!, parcels: delivery.parcels),
            const SizedBox(height: 12),
          ],
          _CustomerCard(
            delivery: delivery,
            onMessage: () => _openAssistant(context),
          ),
          const SizedBox(height: 12),
          _AddressCard(delivery: delivery),
          const SizedBox(height: 12),
          if (delivery.notes.isNotEmpty) ...[
            SectionCard(
              title: 'Delivery notes',
              trailing: Text(
                plural(delivery.notes.length, 'note'),
                style: theme.textTheme.bodySmall,
              ),
              child: Column(
                children: [
                  for (final note in delivery.notes) ...[
                    _NoteTile(
                      note: note,
                      onAskAi: () => _openAssistant(context, note: note.text),
                    ),
                    if (note != delivery.notes.last) const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (delivery.events.isNotEmpty) ...[
            SectionCard(
              title: 'Timeline',
              child: Column(
                children: [
                  for (final event in delivery.events)
                    _TimelineTile(
                      event: event,
                      isLast: event == delivery.events.last,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (delivery.history.isNotEmpty)
            SectionCard(
              title: 'Previous attempts',
              child: Column(
                children: [
                  for (final attempt in delivery.history)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.history, size: 16, color: AppTheme.inkMuted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${attempt.label} \u00b7 ${dateTimeShort(attempt.at)}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
              onPressed: () => _openAssistant(context),
              icon: const Icon(Icons.auto_awesome, size: 19),
              label: const Text('AI assistant \u00b7 analyse this note'),
            ),
            if (canComplete) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _confirmCompletion(context, delivery),
                icon: Icon(
                  delivery.status == DeliveryStatus.failed
                      ? Icons.replay_outlined
                      : Icons.check_outlined,
                  size: 19,
                ),
                label: Text(
                  delivery.status == DeliveryStatus.failed
                      ? 'Retry this stop'
                      : 'Mark as delivered',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmCompletion(BuildContext context, Delivery delivery) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = context.read<DeliveriesController>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(delivery.status == DeliveryStatus.failed ? 'Retry this stop?' : 'Complete this stop?'),
        content: Text(
          delivery.status == DeliveryStatus.failed
              ? 'The stop goes back into your route.'
              : '${delivery.customer.fullName} \u00b7 ${delivery.address.singleLine}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final target =
        delivery.status == DeliveryStatus.failed ? DeliveryStatus.pending : DeliveryStatus.delivered;

    final ok = await controller.updateStatus(
      delivery.id,
      target,
      label: target == DeliveryStatus.delivered ? 'Handed over in person' : 'Driver requested a retry',
    );

    // Important status changes raise a server-side notification (e.g. a failed
    // stop) - pull the feed so the badge is fresh.
    if (context.mounted) {
      unawaited(context.read<NotificationsController>().load(silent: true));
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(ok
            ? '${delivery.id} marked as ${target.label.toLowerCase()}'
            : controller.error ?? 'Could not update the stop'),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.delivery});

  final Delivery delivery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.hairline),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(delivery.zone, style: theme.textTheme.bodySmall),
              ),
              Text(
                'Stop ${delivery.sequence}',
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.schedule, size: 17, color: AppTheme.accent),
              const SizedBox(width: 8),
              Text(
                '${timeWindow(delivery.windowStart, delivery.windowEnd)} window',
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 14),
              const Icon(Icons.navigation_outlined, size: 17, color: AppTheme.brand),
              const SizedBox(width: 8),
              Text(
                'ETA ${relativeTime(delivery.eta)}',
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              MetaPill(icon: Icons.inventory_2_outlined, label: plural(delivery.parcels, 'parcel')),
              MetaPill(icon: Icons.near_me_outlined, label: distance(delivery.distanceKm)),
              if (delivery.codAmount > 0)
                MetaPill(
                  icon: Icons.payments_outlined,
                  label: 'COD ${money(delivery.codAmount, delivery.currency)}',
                  color: AppTheme.warning,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The goods themselves: a large product photo plus name, category and the
/// references the driver can read out at the door.
class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item, required this.parcels});

  final DeliveryItem item;
  final int parcels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SectionCard(
      title: 'What you are delivering',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ItemImage(
            item: item,
            width: double.infinity,
            height: 176,
            radius: 18,
            iconSize: 34,
          ),
          const SizedBox(height: 12),
          Text(
            item.name,
            style: theme.textTheme.titleLarge?.copyWith(fontSize: 19),
          ),
          if (item.category.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(item.category, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 11),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              MetaPill(icon: Icons.inventory_2_outlined, label: plural(parcels, 'parcel')),
              if (item.sku.isNotEmpty)
                MetaPill(icon: Icons.qr_code_2_outlined, label: item.sku),
            ],
          ),
        ],
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.delivery, required this.onMessage});

  final Delivery delivery;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customer = delivery.customer;

    return SectionCard(
      title: 'Customer',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 23,
                backgroundColor: AppTheme.brand.withValues(alpha: 0.16),
                child: Text(
                  customer.initials,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.brand,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(customer.fullName, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      '${customer.phone} \u00b7 prefers ${customer.channel.label}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => ContactActions.call(customer.phone),
                  icon: const Icon(Icons.call_outlined, size: 18),
                  label: const Text('Call'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: onMessage,
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('Assist'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.delivery});

  final Delivery delivery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final address = delivery.address;

    return SectionCard(
      title: 'Address',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MapScreen(deliveryId: delivery.id),
              ),
            ),
            icon: const Icon(Icons.map_outlined, size: 18),
            label: const Text('Map'),
          ),
          TextButton.icon(
            onPressed: () => ContactActions.navigate(
              lat: address.lat,
              lng: address.lng,
              label: delivery.customer.fullName,
              address: address.singleLine,
            ),
            icon: const Icon(Icons.directions_outlined, size: 18),
            label: const Text('Navigate'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(address.singleLine, style: theme.textTheme.bodyMedium),
          if (address.accessHint.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.warning.withValues(alpha: 0.28)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_outlined, size: 17, color: AppTheme.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      address.accessHint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppTheme.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.note, required this.onAskAi});

  final DeliveryNote note;
  final VoidCallback onAskAi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: note.fromCustomer
            ? AppTheme.brand.withValues(alpha: 0.07)
            : AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: note.fromCustomer
              ? AppTheme.brand.withValues(alpha: 0.24)
              : AppTheme.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                note.fromCustomer ? Icons.person_outline : Icons.support_agent_outlined,
                size: 15,
                color: note.fromCustomer ? AppTheme.brand : AppTheme.inkMuted,
              ),
              const SizedBox(width: 6),
              Text(
                note.fromCustomer ? 'Customer' : 'Dispatcher',
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Text(' \u00b7 ${relativeTime(note.createdAt)}',
                  style: theme.textTheme.bodySmall),
              const Spacer(),
              TextButton(
                onPressed: onAskAi,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  foregroundColor: AppTheme.accent,
                ),
                child: const Text('Ask AI', style: TextStyle(fontSize: 12.5)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(note.text, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({required this.event, required this.isLast});

  final DeliveryEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 5),
                decoration: const BoxDecoration(
                  color: AppTheme.brand,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: AppTheme.hairline),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.label, style: theme.textTheme.bodyMedium),
                  Text(
                    dateTimeShort(event.at),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
