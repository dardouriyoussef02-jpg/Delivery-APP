import 'dart:ui' as ui;

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
      bottomNavigationBar: _FloatingNavigationBar(
        selectedIndex: _index,
        attentionCount: attention,
        onSelected: (index) => setState(() => _index = index),
      ),
    );
  }
}

class _FloatingNavigationBar extends StatelessWidget {
  const _FloatingNavigationBar({
    required this.selectedIndex,
    required this.attentionCount,
    required this.onSelected,
  });

  final int selectedIndex;
  final int attentionCount;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    // Full-width translucent bar (`bg-surface-container-low/90 backdrop-blur-xl`).
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceAlt.withValues(alpha: 0.90),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 24,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: SizedBox(
              height: 80,
              child: Row(
                children: [
                  _NavigationItem(
                    label: 'Deliveries',
                    icon: Icons.list_alt_outlined,
                    selectedIcon: Icons.list_alt_rounded,
                    selected: selectedIndex == 0,
                    onTap: () => onSelected(0),
                  ),
                  _NavigationItem(
                    label: 'Route',
                    icon: Icons.route_outlined,
                    selectedIcon: Icons.route_rounded,
                    selected: selectedIndex == 1,
                    badgeCount: attentionCount,
                    onTap: () => onSelected(1),
                  ),
                  _NavigationItem(
                    label: 'Profile',
                    icon: Icons.person_outline_rounded,
                    selectedIcon: Icons.person_rounded,
                    selected: selectedIndex == 2,
                    onTap: () => onSelected(2),
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

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final int badgeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Design: active item is `text-primary font-bold` with no background pill.
    final color = selected ? AppTheme.brand : AppTheme.inkMuted;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 72,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Badge(
                isLabelVisible: badgeCount > 0,
                label: Text('$badgeCount'),
                child: Icon(selected ? selectedIcon : icon,
                    color: color, size: 24),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.hasBoundedHeight && constraints.maxHeight < 200;
        final minHeight =
            constraints.hasBoundedHeight ? constraints.maxHeight : 0.0;

        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(compact ? 16 : 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!compact) ...[
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppTheme.brand.withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AppTheme.brand.withValues(alpha: 0.24)),
                        ),
                        child: Icon(icon, size: 34, color: AppTheme.brand),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Text(title,
                        style: theme.textTheme.titleMedium,
                        textAlign: TextAlign.center),
                    SizedBox(height: compact ? 6 : 8),
                    Text(message,
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center),
                    if (action != null) ...[
                      SizedBox(height: compact ? 12 : 18),
                      action!
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
