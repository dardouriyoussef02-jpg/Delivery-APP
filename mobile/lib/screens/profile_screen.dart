import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../models/delivery.dart';
import '../services/native_platform.dart';
import '../state/deliveries_controller.dart';
import '../state/session_controller.dart';
import '../widgets/section_card.dart';
import 'admin_stats_screen.dart';

/// Driver profile + the settings the client can tweak during a demo.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _testing = false;
  bool? _nativeAvailable;

  @override
  void initState() {
    super.initState();
    NativePlatform.isAvailable().then((available) {
      if (mounted) setState(() => _nativeAvailable = available);
    });
  }

  Future<void> _test() async {
    final session = context.read<SessionController>();
    setState(() => _testing = true);
    final result = await session.testConnection();
    if (!mounted) return;
    setState(() => _testing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.ok ? null : AppTheme.danger,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final deliveries = context.watch<DeliveriesController>();
    final theme = Theme.of(context);
    final connectionColor = deliveries.offline ? AppTheme.warning : AppTheme.success;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          SectionCard(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: AppTheme.brand,
                  child: Text(
                    session.initials,
                    style: const TextStyle(
                      color: AppTheme.onBrand,
                      fontWeight: FontWeight.w800,
                      fontSize: 19,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(session.driverName, style: theme.textTheme.titleLarge?.copyWith(fontSize: 18)),
                      const SizedBox(height: 2),
                      Text(session.driverEmail.isEmpty ? 'Not signed in' : session.driverEmail,
                          style: theme.textTheme.bodySmall),
                      const SizedBox(height: 6),
                      MetaPill(icon: Icons.badge_outlined, label: 'Driver ${session.driverId}'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          SectionCard(
            title: 'AI assistant',
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Analyse automatically', style: TextStyle(fontSize: 15)),
                  subtitle: Text(
                    'Open a stop and get the suggestion straight away.',
                    style: theme.textTheme.bodySmall,
                  ),
                  value: session.autoSuggest,
                  activeThumbColor: AppTheme.brand,
                  onChanged: session.setAutoSuggest,
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Default channel', style: TextStyle(fontSize: 15)),
                  subtitle: Wrap(
                    spacing: 8,
                    children: [
                      for (final channel in MessageChannel.values)
                        ChoiceChip(
                          label: Text(channel.label, style: const TextStyle(fontSize: 12.5)),
                          selected: session.defaultChannel == channel,
                          onSelected: (_) => session.setDefaultChannel(channel),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          SectionCard(
            title: 'Connection',
            trailing: Text(
              deliveries.offline ? 'offline demo' : 'live',
              style: theme.textTheme.bodySmall?.copyWith(
                color: deliveries.offline ? AppTheme.warning : AppTheme.success,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(13),
                  decoration: AppTheme.innerDecoration,
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: connectionColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: connectionColor.withValues(alpha: 0.55),
                                blurRadius: 8),
                          ],
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          deliveries.offline
                              ? 'Offline \u00b7 showing the bundled demo route'
                              : 'Connected \u00b7 live delivery service',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppTheme.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.onBrand),
                        )
                      : const Icon(Icons.wifi_tethering_outlined, size: 18),
                  label: Text(_testing ? 'Testing\u2026' : 'Test connection'),
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  icon: Icons.smart_toy_outlined,
                  label: 'Native modules (Maps / share sheet)',
                  value: switch (_nativeAvailable) {
                    null => 'checking\u2026',
                    true => 'available',
                    false => 'not wired yet',
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Admin-only shortcut: the role gate lives both here (visibility)
          // and on the server (GET /api/v1/stats requires the admin role).
          if (session.driverRole == 'admin') ...[
            SectionCard(
              title: 'Administration',
              trailing: Text(
                'admin',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.brand,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: AppTheme.brand.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.insights_outlined,
                    size: 20,
                    color: AppTheme.brand,
                  ),
                ),
                title: const Text('Fleet statistics'),
                subtitle: Text(
                  'Live totals for the whole fleet',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppTheme.inkMuted),
                ),
                trailing:
                    const Icon(Icons.chevron_right, size: 20, color: AppTheme.inkFaint),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminStatsScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],

          SectionCard(
            title: 'About',
            child: Column(
              children: [
                _InfoRow(icon: Icons.local_shipping_outlined, label: 'App', value: 'Delivery Driver 1.0.0'),
                const SizedBox(height: 8),
                const _InfoRow(
                  icon: Icons.code_outlined,
                  label: 'Built with',
                  value: 'Flutter 3.47 \u00b7 Dart 3.13',
                ),
                const SizedBox(height: 8),
                const _InfoRow(
                  icon: Icons.auto_awesome_outlined,
                  label: 'AI feature',
                  value: 'note \u2192 action \u2192 draft message',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          OutlinedButton.icon(
            onPressed: () => _confirmSignOut(context, session),
            icon: const Icon(Icons.logout_outlined, size: 18),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, SessionController session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You can sign back in at any time.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(minimumSize: const Size(110, 44)),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed == true) await session.signOut();
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});

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
        Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
        Text(value, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}
