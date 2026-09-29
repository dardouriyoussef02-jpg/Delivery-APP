import 'package:geolocator/geolocator.dart';

import 'platform_call.dart';

/// Plain coordinate pair so screens never depend on geolocator types
/// (and tests can hand one in without a platform channel).
class DriverPosition {
  const DriverPosition({required this.lat, required this.lng});

  final double lat;
  final double lng;

  /// Marker-ready pair for flutter_map.
  (double, double) get asPair => (lat, lng);
}

/// What came back from a single position lookup - never throws.
enum LocationState {
  ready,

  /// Location services are switched off on the device (GPS toggle).
  serviceDisabled,

  /// Permission not granted (yet).
  permissionDenied,

  /// Permission blocked in system settings - only "open settings" helps.
  permissionDeniedForever,

  /// Platform missing, timeout, unable to determine, ... graceful fallback.
  unavailable,
}

class LocationResult {
  const LocationResult(this.state, [this.position]);

  final LocationState state;
  final DriverPosition? position;

  bool get hasPosition => position != null;
}

/// Single source of truth for "where am I" - implemented by geolocator and
/// by test fakes.
abstract class LocationService {
  /// One-shot lookup: permission flow included. No background tracking.
  Future<LocationResult> currentLocation();

  /// Opens the app's system settings page (for denied-forever).
  Future<void> openAppSettings();

  /// Opens the OS location settings page (for service-disabled).
  Future<void> openLocationSettings();
}

/// Production implementation over `geolocator`.
///
/// Every platform call is guarded: a missing plugin, an emulator without GPS
/// or a slow desktop embedder degrade to [LocationState.unavailable] instead
/// of hanging the map screen.
class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<LocationResult> currentLocation() async {
    final enabled = await guardedPlatformCall<bool>(
      Geolocator.isLocationServiceEnabled(),
      label: 'location',
    );
    if (!enabled.ok) return const LocationResult(LocationState.unavailable);
    if (enabled.value != true) return const LocationResult(LocationState.serviceDisabled);

    var permission = await guardedPlatformCall<LocationPermission>(
      Geolocator.checkPermission(),
      label: 'location',
    );
    if (!permission.ok) return const LocationResult(LocationState.unavailable);

    if (permission.value == LocationPermission.denied) {
      // Interactive ask (Android/iOS show the system dialog).
      permission = await guardedPlatformCall<LocationPermission>(
        Geolocator.requestPermission(),
        label: 'location',
      );
      if (!permission.ok) return const LocationResult(LocationState.unavailable);
    }

    switch (permission.value!) {
      case LocationPermission.denied:
        return const LocationResult(LocationState.permissionDenied);
      case LocationPermission.deniedForever:
        return const LocationResult(LocationState.permissionDeniedForever);
      case LocationPermission.unableToDetermine:
        return const LocationResult(LocationState.unavailable);
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        break;
    }

    final position = await guardedPlatformCall<Position>(
      Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      ),
      label: 'location',
    );
    if (!position.ok || position.value == null) {
      return const LocationResult(LocationState.unavailable);
    }

    return LocationResult(
      LocationState.ready,
      DriverPosition(lat: position.value!.latitude, lng: position.value!.longitude),
    );
  }

  @override
  Future<void> openAppSettings() async {
    // `.then` normalises whatever bool/void the platform answers with.
    await guardedPlatformCall<void>(
      Geolocator.openAppSettings().then((_) {}),
      label: 'location',
    );
  }

  @override
  Future<void> openLocationSettings() async {
    await guardedPlatformCall<void>(
      Geolocator.openLocationSettings().then((_) {}),
      label: 'location',
    );
  }
}
