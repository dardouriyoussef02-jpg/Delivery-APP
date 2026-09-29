import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../models/app_notification.dart';
import '../state/deliveries_controller.dart' show LoadState;
import '../state/notifications_controller.dart';
import 'delivery_detail_screen.dart';
import 'home_shell.dart';

/// The driver's inbox: assignments, route changes, customer updates, replies
/// and important status changes - newest first, unread on top.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  IconData _iconFor(AppNotification item) => switch (item.type) {
        'delivery_assigned' => Icons.local_shipping_outlined,
        'assignment_changed' => Icons.route_outlined,
        'customer_reply' => Icons.forum_outlined,
        'customer_update' => Icons.sticky_note_2_outlined,
        'status_changed' => Icons.error_outline,
        _ => Icons.notifications_outlined,
      };

  void _open(BuildContext context, AppNotification item) {
    final controller = context.read<NotificationsController>();
    if (!item.isRead) controller.markRead(item.id);
    if (!item.opensStop) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DeliveryDetailScreen(deliveryId: item.deliveryId!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<NotificationsController>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Notifications'),
            const SizedBox(height: 2),
            Text(
              controller.unreadCount == 0
                  ? 'You are up to date'
                  : plural(controller.unreadCount, 'unread update'),
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: controller.updating
                ? null
                : () => controller.load(silent: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _Body(controller: controller, iconFor: _iconFor, onOpen: _open),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.controller,
    required this.iconFor,
    required this.onOpen,
  });

  final NotificationsController controller;
  final IconData Function(AppNotification) iconFor;
  final void Function(BuildContext, AppNotification) onOpen;

  @override
  Widget build(BuildContext context) {
    if (controller.state == LoadState.loading && controller.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (controller.state == LoadState.failure && controller.items.isEmpty) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load notifications',
        message: controller.error ?? 'Something went wrong while loading your updates.',
        action: FilledButton(
          onPressed: () => controller.load(),
          child: const Text('Try again'),
        ),
      );
    }

    if (controller.items.isEmpty) {
      return const EmptyState(
        icon: Icons.notifications_none_outlined,
        title: 'You are up to date',
        message:
            'New stops, route changes, customer replies and status updates will show up here.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => controller.load(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        children: [
          if (!controller.systemEnabled)
            const _PermissionBanner(),
          if (controller.error != null && controller.items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                controller.error!,
                style: const TextStyle(color: AppTheme.warning, fontSize: 12.5),
              ),
            ),
          for (final item in controller.items)
            _NotificationTile(
              item: item,
              icon: iconFor(item),
              onTap: () => onOpen(context, item),
            ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.icon,
    required this.onTap,
  });

  final AppNotification item;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = !item.isRead;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: unread
          ? AppTheme.brand.withValues(alpha: 0.08)
          : AppTheme.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: unread
                  ? AppTheme.brand.withValues(alpha: 0.04)
                  : Colors.white.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: unread
                    ? AppTheme.brand.withValues(alpha: 0.28)
                    : Colors.white.withValues(alpha: 0.10),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: unread
                        ? AppTheme.brand.withValues(alpha: 0.16)
                        : AppTheme.surfaceAlt,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 19, color: unread ? AppTheme.brand : AppTheme.inkMuted),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                              ),
                            ),
                          ),
                          if (unread)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppTheme.brand,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      if (item.body.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(item.body, style: theme.textTheme.bodySmall),
                      ],
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          Text(
                            relativeTime(item.createdAt),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppTheme.inkFaint,
                            ),
                          ),
                          if (item.isDemo) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceHigh,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppTheme.hairline),
                              ),
                              child: const Text(
                                'demo',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.inkFaint,
                                ),
                              ),
                            ),
                          ],
                          if (item.opensStop) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.chevron_right, size: 16, color: AppTheme.inkFaint),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.28)),
      ),
      child: const Row(
        children: [
          Icon(Icons.notifications_off_outlined, size: 17, color: AppTheme.warning),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'System notifications are off - updates still appear in this list.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
