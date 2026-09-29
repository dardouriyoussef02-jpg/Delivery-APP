import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_theme.dart';
import 'screens/delivery_detail_screen.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/ai_agent_service.dart';
import 'services/delivery_repository.dart';
import 'services/notifications_repository.dart';
import 'state/assistant_controller.dart';
import 'state/deliveries_controller.dart';
import 'state/notifications_controller.dart';
import 'state/session_controller.dart';

/// Wires the controllers together and decides between splash, login and the
/// driver shell.
class DeliveryApp extends StatefulWidget {
  const DeliveryApp({super.key, this.session});

  /// Injectable for tests; production builds create its own.
  final SessionController? session;

  @override
  State<DeliveryApp> createState() => _DeliveryAppState();
}

class _DeliveryAppState extends State<DeliveryApp> with WidgetsBindingObserver {
  /// Used by notification taps to deep-link to a stop from anywhere
  /// (foreground banner taps and cold starts).
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  late final SessionController _session = widget.session ?? SessionController();
  late final bool _ownsSession = widget.session == null;
  late final NotificationsController _notifications =
      NotificationsController(NotificationsRepository(_session.api));
  late final DeliveriesController _deliveries =
      DeliveriesController(DeliveryRepository(_session.api));
  late final AssistantController _assistant = AssistantController(
    AiAgentService(_session.api),
    onMessageSent: () => _notifications.load(silent: true),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notifications.onOpenStop = _openStopFromNotification;
    _session.bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsSession) _session.dispose();
    _notifications.dispose();
    _deliveries.dispose();
    _assistant.dispose();
    super.dispose();
  }

  /// Fresh feed whenever the app returns to the foreground (customer replies,
  /// dispatch changes, ... arrive while backgrounded).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _session.signedIn) {
      _notifications.load(silent: true);
    }
  }

  void _openStopFromNotification(String deliveryId) {
    if (!_session.signedIn) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigatorKey.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => DeliveryDetailScreen(deliveryId: deliveryId),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionController>.value(value: _session),
        ChangeNotifierProvider<DeliveriesController>.value(value: _deliveries),
        ChangeNotifierProvider<AssistantController>.value(value: _assistant),
        ChangeNotifierProvider<NotificationsController>.value(value: _notifications),
      ],
      child: MaterialApp(
        title: 'Delivery Driver',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        navigatorKey: navigatorKey,
        home: Consumer<SessionController>(
          builder: (context, session, _) {
            if (!session.ready) return const _SplashScreen();

            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOut,
              child: session.signedIn
                  ? const HomeShell(key: ValueKey('shell'))
                  : const LoginScreen(key: ValueKey('login')),
            );
          },
        ),
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Lime bloom in the top-right corner, matching the app's hero look.
          DecoratedBox(
            decoration: BoxDecoration(gradient: AppTheme.bloom(alpha: 0.22)),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: AppTheme.brandGradient,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.brand.withValues(alpha: 0.4),
                        blurRadius: 40,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.local_shipping_outlined,
                      color: AppTheme.onBrand, size: 40),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Delivery Driver',
                  style: TextStyle(
                    color: AppTheme.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 20),
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.6),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
