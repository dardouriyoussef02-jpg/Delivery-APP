import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../state/deliveries_controller.dart';
import '../state/notifications_controller.dart';
import '../widgets/delivery_card.dart';
import 'delivery_detail_screen.dart';
import 'home_shell.dart';
import 'notifications_screen.dart';

/// The driver's stop list: search, filter, pull to refresh.
class DeliveriesScreen extends StatelessWidget {
  const DeliveriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DeliveriesController>();
    final notifications = context.watch<NotificationsController>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Today\u2019s route'),
            const SizedBox(height: 2),
            Text(
              controller.items.isEmpty
                  ? 'Loading stops\u2026'
                  : '${plural(controller.doneCount, 'stop')} done \u00b7 '
                      '${distance(controller.remainingKm)} left',
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
            ),
            icon: Badge(
              isLabelVisible: notifications.unreadCount > 0,
              label: Text('${notifications.unreadCount}'),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: controller.state == LoadState.loading
                ? null
                : () => controller.load(silent: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (controller.offline) const _OfflineBanner(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                onChanged: controller.setQuery,
                decoration: const InputDecoration(
                  hintText: 'Search customer, address or note',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _FilterButton(
                    label: 'All',
                    count: controller.items.length,
                    selected: controller.filter == DeliveryFilter.all,
                    onTap: () => controller.setFilter(DeliveryFilter.all),
                  ),
                  const SizedBox(width: 8),
                  _FilterButton(
                    label: 'To do',
                    count: controller.todoCount,
                    selected: controller.filter == DeliveryFilter.todo,
                    onTap: () => controller.setFilter(DeliveryFilter.todo),
                  ),
                  const SizedBox(width: 8),
                  _FilterButton(
                    label: 'Attention',
                    count: controller.attentionCount,
                    selected: controller.filter == DeliveryFilter.attention,
                    onTap: () => controller.setFilter(DeliveryFilter.attention),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(child: _Body(controller: controller)),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.controller});

  final DeliveriesController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.state == LoadState.loading && controller.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (controller.state == LoadState.failure && controller.items.isEmpty) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load your route',
        message: controller.error ?? 'The API did not answer.',
        action: FilledButton(
          onPressed: () => controller.load(),
          child: const Text('Try again'),
        ),
      );
    }

    final visible = controller.visible;

    if (visible.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => controller.load(silent: true),
        child: EmptyState(
          icon: Icons.checklist_outlined,
          title: controller.query.isEmpty ? 'Nothing here yet' : 'No matching stops',
          message: controller.query.isEmpty
              ? 'Pull to refresh and your stops will appear.'
              : 'Try another name, address or note keyword.',
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => controller.load(silent: true),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        itemCount: visible.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final delivery = visible[index];
          return DeliveryCard(
            delivery: delivery,
            index: delivery.sequence - 1,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DeliveryDetailScreen(deliveryId: delivery.id),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppTheme.brand : AppTheme.surface,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected ? AppTheme.brand : AppTheme.hairline,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppTheme.brand.withValues(alpha: 0.30),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: selected ? AppTheme.onBrand : AppTheme.inkMuted,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? AppTheme.onBrand.withValues(alpha: 0.16)
                      : AppTheme.surfaceHigh,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: selected ? AppTheme.onBrand : AppTheme.inkMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppTheme.warning.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_outlined, size: 15, color: AppTheme.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Backend unreachable - showing the bundled demo route.',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppTheme.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
