import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Default budget for one platform-channel round trip.
///
/// Secure storage, notifications and geolocation all answer in milliseconds
/// on a healthy device. If the platform side is missing (desktop/web embedder
/// without the plugin) or wedged, the future may simply never complete - this
/// timeout turns that into a graceful fallback instead of a frozen screen.
const kPlatformCallTimeout = Duration(milliseconds: 1200);

class PlatformResult<T> {
  const PlatformResult({required this.ok, this.value});

  /// False when the call timed out or the platform implementation is missing.
  final bool ok;
  final T? value;
}

/// Runs a platform-channel call defensively.
///
/// Never throws: a failure is reported through [PlatformResult.ok] so callers
/// can degrade (memory storage, "location unavailable", "notifications off").
Future<PlatformResult<T>> guardedPlatformCall<T>(
  Future<T> action, {
  Duration timeout = kPlatformCallTimeout,
  String label = 'platform',
}) async {
  try {
    return PlatformResult<T>(ok: true, value: await action.timeout(timeout));
  } on TimeoutException {
    debugPrint('[$label] platform call timed out after ${timeout.inMilliseconds}ms');
  } on MissingPluginException {
    debugPrint('[$label] no platform implementation available');
  } on PlatformException catch (error) {
    debugPrint('[$label] platform error ${error.code}: ${error.message}');
  } catch (error) {
    // Plugins can fail in exotic ways (e.g. an unregistered federated
    // platform instance raising a LateInitializationError). The contract of
    // this helper is "never throws" - degrade instead of crashing the app.
    debugPrint('[$label] platform call failed: $error');
  }
  return PlatformResult<T>(ok: false);
}
