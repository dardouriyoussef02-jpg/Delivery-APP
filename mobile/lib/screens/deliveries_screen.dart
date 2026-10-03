import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../core/test_env_stub.dart'
    if (dart.library.io) '../core/test_env_io.dart' show isRunningUnderTest;
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
    final firstName = session.driverName.trim().split(RegExp(r'\s+')).first;

    return Scaffold(
      // Fixed translucent ShiftFlow header from the design system.
      appBar: AppBar(
        toolbarHeight: 80,
        titleSpacing: 16,
        // Design: `bg-surface/85 backdrop-blur border-b border-surface-container-high`.
        backgroundColor: AppTheme.bg.withValues(alpha: 0.85),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: SizedBox(
            width: double.infinity,
            height: 1,
            child: ColoredBox(color: AppTheme.surfaceHigh),
          ),
        ),
        title: Row(
          children: [
            Image.asset(
              'assets/brand/shiftflow-logo.png',
              height: 32,
              width: 32,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                  Icons.local_shipping_outlined,
                  color: AppTheme.brand,
                  size: 28),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'SHIFTFLOW',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppTheme.ink,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text('\u2022',
                            style: TextStyle(color: AppTheme.inkFaint)),
                      ),
                      Flexible(
                        child: Text(
                          'Delivery Queue',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: AppTheme.brand,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const PulsingDot(),
                      const SizedBox(width: 6),
                      Text(
                        'ON DUTY',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppTheme.brand,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text('\u2022',
                            style: TextStyle(color: AppTheme.inkFaint)),
                      ),
                      Flexible(
                        child: Text(
                          firstName.isEmpty ? 'Driver' : firstName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppTheme.inkMuted,
                                    fontWeight: FontWeight.w500,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => const NotificationsScreen()),
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
          const SizedBox(width: 4),
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
                attention: controller.attentionCount,
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

/// Solid mint dot with the design's expanding "ping" ring.
class PulsingDot extends StatefulWidget {
  const PulsingDot({super.key, this.color = AppTheme.brand, this.size = 8});

  final Color color;
  final double size;

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    // The ping repeats forever by design, which would make
    // `WidgetTester.pumpAndSettle` hang - so keep it still under `flutter test`.
    if (!isRunningUnderTest()) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: 1 + t * 2,
                child: Opacity(
                  opacity: (1 - t) * 0.7,
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                        color: widget.color, shape: BoxShape.circle),
                  ),
                ),
              ),
              Container(
                width: size,
                height: size,
                decoration:
                    BoxDecoration(color: widget.color, shape: BoxShape.circle),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Shift performance glance banner: progress bar + 3-column bento metrics.
class _ShiftOverview extends StatelessWidget {
  const _ShiftOverview({
    required this.done,
    required this.total,
    required this.remainingKm,
    required this.attention,
  });

  final int done;
  final int total;
  final double remainingKm;
  final int attention;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = total == 0 ? 0.0 : done / total;
    final pct = (progress * 100).round();

    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration,
      child: Stack(
        children: [
          // Ambient cockpit glows from the design (mint top-right, blue bottom-left).
          Positioned(
            right: -40,
            top: -40,
            child: _Glow(color: AppTheme.brand),
          ),
          Positioned(
            left: -40,
            bottom: -40,
            child: _Glow(color: AppTheme.accent),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.brand.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const PulsingDot(size: 6),
                        const SizedBox(width: 6),
                        Text(
                          'ON SHIFT',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppTheme.brand,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceHigh,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.near_me_outlined,
                            size: 13, color: AppTheme.accent),
                        const SizedBox(width: 4),
                        Text(
                          '${distance(remainingKm)} left',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppTheme.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Shift progress tracker
              Row(
                children: [
                  Icon(Icons.schedule, size: 15, color: AppTheme.inkMuted),
                  const SizedBox(width: 6),
                  Text(
                    '$done of $total stops complete',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: AppTheme.ink),
                  ),
                  const Spacer(),
                  Text(
                    '$pct% Done',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppTheme.brand,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  children: [
                    Container(
                      height: 8,
                      color: AppTheme.surfaceHighest,
                    ),
                    FractionallySizedBox(
                      widthFactor: progress.clamp(0.0, 1.0),
                      child: Container(
                        height: 8,
                        decoration: const BoxDecoration(
                            gradient: AppTheme.progressGradient),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Key metrics 3-column bento grid
              Row(
                children: [
                  Expanded(
                    child: _MetricTile(
                      label: 'DROPOFFS',
                      footer: '$pct% done',
                      footerIcon: Icons.check_circle,
                      footerColor: AppTheme.brand,
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: '$done',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.ink,
                              ),
                            ),
                            TextSpan(
                              text: ' / $total',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: AppTheme.inkMuted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MetricTile(
                      label: 'DISTANCE',
                      footer: 'remaining',
                      footerIcon: Icons.route_outlined,
                      footerColor: AppTheme.accent,
                      child: Text(
                        distance(remainingKm),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.ink,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MetricTile(
                      label: 'ATTENTION',
                      footer: 'to review',
                      footerIcon: Icons.report_problem_outlined,
                      footerColor: AppTheme.warning,
                      child: Text(
                        '$attention',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.ink,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 176,
      height: 176,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.10), color.withValues(alpha: 0.0)],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.child,
    required this.footer,
    required this.footerIcon,
    required this.footerColor,
  });

  final String label;
  final Widget child;
  final String footer;
  final IconData footerIcon;
  final Color footerColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: AppTheme.innerDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppTheme.inkMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          child,
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(footerIcon, size: 11, color: footerColor),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  footer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: footerColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
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
        message: controller.error ??
            'Something went wrong while loading your route.',
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
          title: controller.query.isEmpty
              ? 'Nothing here yet'
              : 'No matching stops',
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
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppTheme.brand : AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
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
                  fontWeight: FontWeight.w700,
                  color: selected ? AppTheme.onBrand : AppTheme.inkMuted,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? AppTheme.onBrand.withValues(alpha: 0.16)
                      : AppTheme.surfaceHighest,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_outlined,
              size: 15, color: AppTheme.warning),
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
