import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../models/delivery.dart';
import '../services/api_client.dart';
import '../services/contact_actions.dart';
import '../services/location_service.dart';
import '../state/deliveries_controller.dart';
import 'delivery_detail_screen.dart';

/// The driver's route map: where I am (pickup/depot), where I'm going and the
/// straight-line route overview - plus the same external navigation handoff
/// the rest of the app uses.
///
/// Position handling is one-shot on open (no background tracking), and every
/// failure mode - permission denied, permission blocked, GPS off, platform
/// missing - lands on a friendly, actionable state instead of a broken map.
class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.deliveryId,
    this.locationService,
    this.tileUrlTemplate = osmTileUrl,
  });

  static const osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  final String deliveryId;

  /// Injectable for tests (permission/GPS states without a platform).
  final LocationService? locationService;

  /// Null renders the map without network tiles (used by widget tests).
  final String? tileUrlTemplate;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late final LocationService _location =
      widget.locationService ?? const GeolocatorLocationService();

  /// Null while the first lookup is running.
  LocationResult? _result;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    setState(() => _result = null);
    final result = await _location.currentLocation();
    if (!mounted) return;
    setState(() => _result = result);
  }

  Future<void> _openAppSettings() async {
    await _location.openAppSettings();
    if (mounted) await _locate();
  }

  Future<void> _openLocationSettings() async {
    await _location.openLocationSettings();
    if (mounted) await _locate();
  }

  @override
  Widget build(BuildContext context) {
    final deliveries = context.watch<DeliveriesController>();
    final delivery = deliveries.byId(widget.deliveryId);

    if (delivery == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.deliveryId)),
        body: const Center(child: Text('This stop is no longer available.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.map_outlined, size: 20, color: AppTheme.brand),
            const SizedBox(width: 8),
            Text('Map \u00b7 ${delivery.id}'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh position',
            onPressed: _result == null ? null : _locate,
            icon: const Icon(Icons.my_location),
          ),
        ],
      ),
      body: _body(delivery),
    );
  }

  Widget _body(Delivery delivery) {
    // First lookup in progress.
    if (_result == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            ),
            SizedBox(height: 14),
            Text('Finding your position\u2026', style: TextStyle(color: AppTheme.inkMuted)),
          ],
        ),
      );
    }

    switch (_result!.state) {
      case LocationState.permissionDenied:
        return _PermissionCard(
          icon: Icons.location_off_outlined,
          title: 'Location access needed',
          message:
              'Your position is only drawn on this map so you can see yourself '
              'relative to your stops. Nothing is tracked in the background.',
          primaryLabel: 'Allow location',
          onPrimary: _locate,
          secondaryLabel: 'Open settings',
          onSecondary: _openAppSettings,
        );
      case LocationState.permissionDeniedForever:
        return _PermissionCard(
          icon: Icons.location_disabled_outlined,
          title: 'Location is blocked',
          message:
              'Location permission for this app is switched off in your system '
              'settings. Enable it, then come back to the map.',
          primaryLabel: 'Open settings',
          onPrimary: _openAppSettings,
          secondaryLabel: 'Try again',
          onSecondary: _locate,
        );
      case LocationState.serviceDisabled:
        return _PermissionCard(
          icon: Icons.gps_off_outlined,
          title: 'GPS is switched off',
          message:
              'Turn on location services to see yourself on the route map. '
              'Your stops and navigation are available without it.',
          primaryLabel: 'Turn on location',
          onPrimary: _openLocationSettings,
          secondaryLabel: 'Try again',
          onSecondary: _locate,
        );
      case LocationState.ready:
      case LocationState.unavailable:
        return _buildMap(delivery);
    }
  }

  Widget _buildMap(Delivery delivery) {
    final position = _result?.position;
    final address = delivery.address;
    final destination =
        address.lat != null && address.lng != null
            ? LatLng(address.lat!, address.lng!)
            : null;
    final pickup = LatLng(AppConfig.depotLat, AppConfig.depotLng);
    final driver = position == null ? null : LatLng(position.lat, position.lng);

    final anchors = <LatLng>[
      pickup,
      if (destination != null) destination,
      if (driver != null) driver,
    ];

    final route = driver != null && destination != null
        ? <LatLng>[driver, destination]
        : <LatLng>[pickup, if (destination != null) destination];

    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            options: MapOptions(
              initialCenter: _centerOf(anchors),
              initialZoom: _zoomFor(anchors),
            ),
            children: [
              if (widget.tileUrlTemplate != null)
                TileLayer(
                  urlTemplate: widget.tileUrlTemplate,
                  userAgentPackageName: 'com.fleet.delivery_driver',
                ),
              if (route.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: route,
                      strokeWidth: 4,
                      color: AppTheme.brand.withValues(alpha: 0.75),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: pickup,
                    width: 40,
                    height: 40,
                    child: const _MapMarker(
                      key: ValueKey('marker-pickup'),
                      icon: Icons.warehouse_outlined,
                      color: AppTheme.surfaceHigh,
                      borderColor: AppTheme.inkMuted,
                    ),
                  ),
                  if (destination != null)
                    Marker(
                      point: destination,
                      width: 44,
                      height: 44,
                      child: const _MapMarker(
                        key: ValueKey('marker-destination'),
                        icon: Icons.flag_outlined,
                        color: AppTheme.danger,
                        borderColor: Colors.white,
                      ),
                    ),
                  if (driver != null)
                    Marker(
                      point: driver,
                      width: 34,
                      height: 34,
                      child: const _MapMarker(
                        key: ValueKey('marker-driver'),
                        icon: Icons.navigation_outlined,
                        color: AppTheme.brand,
                        borderColor: Colors.white,
                        iconColor: AppTheme.onBrand,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),

        // Honest fallback: the map still works without a position fix.
        if (_result!.state == LocationState.unavailable)
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AppTheme.surface.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.hairline),
              ),
              child: const Row(
                children: [
                  Icon(Icons.location_off_outlined, size: 16, color: AppTheme.warning),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your position is unavailable - stops and route are shown anyway.',
                      style: TextStyle(fontSize: 12.5, color: AppTheme.ink, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),

        if (widget.tileUrlTemplate != null)
          const Positioned(
            right: 8,
            bottom: 220,
            child: Text(
              '\u00a9 OpenStreetMap',
              style: TextStyle(fontSize: 10.5, color: AppTheme.inkFaint),
            ),
          ),

        // Selected stop + the external navigation handoff.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: _StopCard(delivery: delivery, onOpen: () => _openStop(delivery)),
          ),
        ),
      ],
    );
  }

  void _openStop(Delivery delivery) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DeliveryDetailScreen(deliveryId: delivery.id),
      ),
    );
  }

  LatLng _centerOf(List<LatLng> points) {
    final lat = points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
    final lng = points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length;
    return LatLng(lat, lng);
  }

  /// Rough zoom level so depot, driver and destination fit on screen.
  double _zoomFor(List<LatLng> points) {
    if (points.length < 2) return 13;
    final latitudes = points.map((p) => p.latitude).toList();
    final longitudes = points.map((p) => p.longitude).toList();
    final latSpan = latitudes.reduce(math.max) - latitudes.reduce(math.min);
    final lngSpan = longitudes.reduce(math.max) - longitudes.reduce(math.min);
    final span = math.max(latSpan, lngSpan);

    if (span <= 0.004) return 16;
    if (span <= 0.012) return 14.5;
    if (span <= 0.04) return 13;
    if (span <= 0.12) return 11.5;
    return 10;
  }
}

class _MapMarker extends StatelessWidget {
  const _MapMarker({
    super.key,
    required this.icon,
    required this.color,
    required this.borderColor,
    this.iconColor,
  });

  final IconData icon;
  final Color color;
  final Color borderColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(icon, size: 19, color: iconColor ?? AppTheme.ink),
    );
  }
}

/// Actionable state for every "cannot place you on the map" cause.
class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
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
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onPrimary,
              icon: const Icon(Icons.check_outlined, size: 18),
              label: Text(primaryLabel),
            ),
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onSecondary,
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: Text(secondaryLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StopCard extends StatelessWidget {
  const _StopCard({required this.delivery, required this.onOpen});

  final Delivery delivery;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.hairline),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  delivery.customer.fullName,
                  style: theme.textTheme.titleMedium?.copyWith(fontSize: 16),
                ),
              ),
              Text(
                'Stop ${delivery.sequence}',
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            delivery.address.singleLine,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text('Open stop'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => ContactActions.navigate(
                    lat: delivery.address.lat,
                    lng: delivery.address.lng,
                    label: delivery.customer.fullName,
                    address: delivery.address.singleLine,
                  ),
                  icon: const Icon(Icons.directions_outlined, size: 18),
                  label: const Text('Navigate'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
