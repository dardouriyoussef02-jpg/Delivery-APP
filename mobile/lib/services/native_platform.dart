import 'package:flutter/services.dart';

import 'api_client.dart';

/// Bridge to the small native modules shipped with the app:
///
/// * Android (`MainActivity.kt`) - opens the turn-by-turn navigation intent and
///   the OS share sheet.
/// * iOS (`AppDelegate.swift`)   - opens Maps via `MKMapItem` and the
///   `UIActivityViewController` share sheet.
///
/// Every call degrades gracefully: when the platform code is not present (for
/// example in a widget test) the caller falls back to `url_launcher`.
class NativePlatform {
  NativePlatform._();

  static const MethodChannel channel = MethodChannel('delivery.driver/native');

  /// Opens the driver's preferred navigation app at the stop coordinates.
  /// Returns false when the native side is unavailable.
  static Future<bool> openNavigation({
    required double lat,
    required double lng,
    required String label,
  }) async {
    try {
      final opened = await channel.invokeMethod<bool>('openNavigation', {
        'lat': lat,
        'lng': lng,
        'label': label,
      });
      return opened ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Hands the text to the OS share sheet (WhatsApp, SMS, e-mail, ...).
  static Future<bool> shareText(String text) async {
    try {
      final shared = await channel.invokeMethod<bool>('shareText', {'text': text});
      return shared ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Verifies the channel is wired up (shown in Settings for the client demo).
  static Future<bool> isAvailable() async {
    try {
      return await channel.invokeMethod<bool>('ping') ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Small helper so screens can show one friendly error for any failure.
String readableError(Object error) {
  if (error is ApiException) return error.message;
  return 'Something went wrong. Please try again.';
}
