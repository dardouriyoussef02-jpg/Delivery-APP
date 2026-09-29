import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../state/deliveries_controller.dart';
import '../state/notifications_controller.dart';
import '../state/session_controller.dart';
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
    final session = context.watch<SessionController>();
    final theme = Theme.of(context);
    final firstName = session.driverName.trim().split(RegExp(r'\s+')).first;
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening';

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        title: Row(
          children: [
            CircleAvatar(
              radius: 21,
              backgroundColor: AppTheme.surfaceHigh,
              child: Text(
                session.initials,
                style: const TextStyle(color: AppTheme.brand, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$greeting, ${firstName.isEmpty ? 'Driver' : firstName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text('Today\u2019s route', style: theme.textTheme.titleMedium),
                ],
              ),
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
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
              child: _ShiftOverview(
                done: controller.doneCount,
                total: controller.items.length,
                remainingKm: controller.remainingKm,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                onChanged: controller.setQuery,
                decoration: const InputDecoration(
                  hintText: 'Search customer, item, address or note',
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

class _ShiftOverview extends StatelessWidget {
  const _ShiftOverview({required this.done, required this.total, required this.remainingKm});

  final int done;
  final int total;
  final double remainingKm;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : done / total;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        boxShadow: [
          ...AppTheme.cardShadow,
          BoxShadow(
            color: AppTheme.brand.withValues(alpha: 0.10),
            blurRadius: 28,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_shipping_outlined, color: AppTheme.brand, size: 16),
              const SizedBox(width: 7),
              Text(
                'SHIFT OVERVIEW',
                style: theme.textTheme.labelSmall?.copyWith(color: AppTheme.inkMuted),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.brand.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.brand.withValues(alpha: 0.24)),
                ),
                child: const Text(
                  'ON SHIFT',
                  style: TextStyle(color: AppTheme.brand, fontSize: 10, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$done', style: theme.textTheme.headlineSmall?.copyWith(fontSize: 30)),
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 4),
                child: Text('of $total stops complete', style: theme.textTheme.bodySmall),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(distance(remainingKm), style: theme.textTheme.titleMedium),
                  Text('remaining', style: theme.textTheme.labelSmall),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: Colors.white.withValues(alpha: 0.10),
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.brand),
            ),
          ),
        ],
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
        message: controller.error ?? 'Something went wrong while loading your route.',
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
            color: selected ? null : AppTheme.surface.withValues(alpha: 0.72),
            gradient: selected ? AppTheme.brandGradient : null,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: selected ? AppTheme.brand.withValues(alpha: 0.56) : Colors.white.withValues(alpha: 0.10),
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
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_outlined, size: 15, color: AppTheme.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'You are offline - showing your saved demo route.',
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
