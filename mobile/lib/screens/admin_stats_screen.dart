import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../models/fleet_stats.dart';
import '../services/stats_repository.dart';
import '../state/session_controller.dart';
import '../widgets/section_card.dart';
import 'home_shell.dart';

/// Admin-only dashboard: fleet numbers aggregated by the backend from its
/// database (never bundled sample data). Reached from the Profile screen,
/// which only shows the entry to `role == 'admin'` sessions.
class AdminStatsScreen extends StatefulWidget {
  const AdminStatsScreen({super.key, this.repository});

  /// Injectable for tests; production resolves it from the signed-in session.
  final StatsRepository? repository;

  @override
  State<AdminStatsScreen> createState() => _AdminStatsScreenState();
}

class _AdminStatsScreenState extends State<AdminStatsScreen> {
  StatsRepository? _repository;
  FleetStats? _stats;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository;
    _load();
  }

  Future<void> _load() async {
    final repository =
        _repository ??= StatsRepository(context.read<SessionController>().api);

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final stats = await repository.fetch();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.insights_outlined, size: 20, color: AppTheme.brand),
            SizedBox(width: 8),
            Text('Fleet statistics'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _body(stats),
    );
  }

  Widget _body(FleetStats? stats) {
    if (_loading && stats == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && stats == null) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load statistics',
        message: _error!,
        action: FilledButton(onPressed: _load, child: const Text('Try again')),
      );
    }

    if (stats == null) {
      return const EmptyState(
        icon: Icons.insights_outlined,
        title: 'No data yet',
        message: 'Statistics appear once the service has a database to read.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                _error!,
                style: const TextStyle(color: AppTheme.warning, fontSize: 12.5),
              ),
            ),
          _KpiRow(stats: stats),
          const SizedBox(height: 14),
          _statusCard(stats),
          const SizedBox(height: 14),
          _deliveryTimeCard(stats),
          const SizedBox(height: 14),
          _driversCard(stats),
          const SizedBox(height: 14),
          _activityCard(stats),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Totals',
            child: Column(
              children: [
                _StatRow(
                  icon: Icons.message_outlined,
                  label: 'Messages sent',
                  value: '${stats.totals['messagesSent'] ?? 0}',
                ),
                const SizedBox(height: 8),
                _StatRow(
                  icon: Icons.people_outline,
                  label: 'Customers',
                  value: '${stats.totals['customers'] ?? 0}',
                ),
                const SizedBox(height: 8),
                _StatRow(
                  icon: Icons.badge_outlined,
                  label: 'Active drivers',
                  value: '${stats.totals['drivers'] ?? 0}',
                ),
                const SizedBox(height: 8),
                _StatRow(
                  icon: Icons.notifications_outlined,
                  label: 'Notifications (unread)',
                  value:
                      '${stats.totals['notifications'] ?? 0} (${stats.totals['unreadNotifications'] ?? 0})',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              'Aggregated from the service database \u00b7 ${relativeTime(stats.generatedAt)}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppTheme.inkFaint),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(FleetStats stats) {
    final theme = Theme.of(context);
    final total = stats.totals['deliveries'] ?? 0;
    const order = ['pending', 'in_transit', 'failed', 'delivered'];
    const colors = {
      'pending': AppTheme.inkMuted,
      'in_transit': AppTheme.accent,
      'failed': AppTheme.danger,
      'delivered': AppTheme.success,
    };
    const labels = {
      'pending': 'Scheduled',
      'in_transit': 'On the way',
      'failed': 'Attempt failed',
      'delivered': 'Delivered',
    };

    return SectionCard(
      title: 'Stops by status',
      trailing: Text(
        '${(stats.completionRate * 100).toStringAsFixed(0)}% done',
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppTheme.success,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: Column(
        children: [
          for (final status in order)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: colors[status],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          labels[status]!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        '${stats.byStatus[status] ?? 0}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: total == 0
                          ? 0
                          : (stats.byStatus[status] ?? 0) / total,
                      minHeight: 6,
                      color: colors[status],
                      backgroundColor: AppTheme.surfaceAlt,
                    ),
                  ),
                ],
              ),
            ),
          if (total == 0)
            const Text(
              'No stops in the database yet.',
              style: TextStyle(color: AppTheme.inkFaint, fontSize: 12.5),
            ),
        ],
      ),
    );
  }

  Widget _deliveryTimeCard(FleetStats stats) {
    final theme = Theme.of(context);

    return SectionCard(
      title: 'Delivery time',
      child: stats.sampleSize == 0
          ? const Text(
              'No completed deliveries yet - the average appears as soon as a '
              'stop is marked delivered.',
              style: TextStyle(color: AppTheme.inkFaint, fontSize: 12.5),
            )
          : Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _TimeStat(
                        label: 'Average',
                        value: '${stats.averageMinutes?.toStringAsFixed(1) ?? '-'} min',
                        highlight: true,
                      ),
                    ),
                    Expanded(
                      child: _TimeStat(
                        label: 'Fastest',
                        value: '${stats.fastestMinutes?.toStringAsFixed(1) ?? '-'} min',
                      ),
                    ),
                    Expanded(
                      child: _TimeStat(
                        label: 'Slowest',
                        value: '${stats.slowestMinutes?.toStringAsFixed(1) ?? '-'} min',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Based on '
                      '${plural(stats.sampleSize, 'completed delivery', pluralForm: 'completed deliveries')} '
                      '(creation \u2192 delivered).',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppTheme.inkFaint),
                ),
              ],
            ),
    );
  }

  Widget _driversCard(FleetStats stats) {
    final theme = Theme.of(context);

    return SectionCard(
      title: 'By driver',
      child: stats.perDriver.isEmpty
          ? const Text(
              'No active drivers in the database.',
              style: TextStyle(color: AppTheme.inkFaint, fontSize: 12.5),
            )
          : Column(
              children: [
                for (final driver in stats.perDriver)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.brand.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.person_outline,
                            size: 17,
                            color: AppTheme.brand,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                driver.name,
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontSize: 14),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${driver.driverId} \u00b7 ${plural(driver.assigned, 'stop')} '
                                '\u00b7 ${driver.delivered} delivered \u00b7 ${driver.failed} failed'
                                '${driver.averageMinutes != null ? ' \u00b7 avg ${driver.averageMinutes!.toStringAsFixed(1)} min' : ''}',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: AppTheme.inkMuted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _activityCard(FleetStats stats) {
    final theme = Theme.of(context);

    return SectionCard(
      title: 'Recent activity',
      child: stats.recentActivity.isEmpty
          ? const Text(
              'No status changes recorded yet.',
              style: TextStyle(color: AppTheme.inkFaint, fontSize: 12.5),
            )
          : Column(
              children: [
                for (final event in stats.recentActivity)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.history,
                          size: 16,
                          color: AppTheme.inkMuted,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${event['deliveryId'] ?? ''} \u00b7 '
                            '${event['fromStatus'] ?? 'new'} \u2192 ${event['toStatus'] ?? '?'}'
                            '${event['changedBy'] != null ? ' \u00b7 ${event['changedBy']}' : ''}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        Text(
                          relativeTime(
                            DateTime.tryParse(event['changedAt'] as String? ?? '') ??
                                DateTime.fromMillisecondsSinceEpoch(0),
                          ),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppTheme.inkFaint),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.stats});

  final FleetStats stats;

  @override
  Widget build(BuildContext context) {
    final total = stats.totals['deliveries'] ?? 0;

    return Row(
      children: [
        Expanded(
          child: _KpiCard(
            label: 'Stops',
            value: '$total',
            color: AppTheme.ink,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _KpiCard(
            label: 'Delivered',
            value: '${stats.delivered}',
            color: AppTheme.success,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _KpiCard(
            label: 'Failed',
            value: '${stats.failed}',
            color: AppTheme.danger,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _KpiCard(
            label: 'Open',
            value: '${stats.open}',
            color: AppTheme.accent,
          ),
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppTheme.inkMuted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeStat extends StatelessWidget {
  const _TimeStat({required this.label, required this.value, this.highlight = false});

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: highlight ? AppTheme.brand : AppTheme.ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppTheme.inkFaint,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 17, color: AppTheme.inkMuted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: AppTheme.inkMuted),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}
