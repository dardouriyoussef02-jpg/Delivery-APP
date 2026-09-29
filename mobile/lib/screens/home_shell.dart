import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../state/deliveries_controller.dart';
import '../state/notifications_controller.dart';
import 'deliveries_screen.dart';
import 'profile_screen.dart';
import 'route_screen.dart';

/// Bottom-navigation shell: the driver's home for the whole shift.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    final deliveries = context.read<DeliveriesController>();
    final notifications = context.read<NotificationsController>();
    // Deferred so we never notify listeners during the build phase.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (deliveries.state == LoadState.initial) {
        deliveries.load();
      }
      // Feed + one-time system setup (channel, permission, launch payload).
      if (notifications.state == LoadState.initial) {
        notifications.load();
      } else {
        notifications.load(silent: true);
      }
      notifications.initSystem();
    });
  }

  @override
  Widget build(BuildContext context) {
    final deliveries = context.watch<DeliveriesController>();
    final attention = deliveries.attentionCount;

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          DeliveriesScreen(),
          RouteScreen(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: 'Deliveries',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: attention > 0,
              label: Text('$attention'),
              child: const Icon(Icons.route_outlined),
            ),
            selectedIcon: const Icon(Icons.route),
            label: 'Route',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

/// Shared empty-state widget for lists with no results.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.brand.withValues(alpha: 0.10),
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.brand.withValues(alpha: 0.24)),
              ),
              child: Icon(icon, size: 34, color: AppTheme.brand),
            ),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}
