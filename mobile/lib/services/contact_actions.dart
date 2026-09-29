import 'package:url_launcher/url_launcher.dart';

import 'native_platform.dart';

/// Thin wrappers around `url_launcher` (with the native modules as first
/// choice where they exist) for the actions a driver needs while parked.
class ContactActions {
  ContactActions._();

  static Future<bool> call(String phone) => _launch('tel:${Uri.encodeComponent(phone)}');

  static Future<bool> openSms({String phone = '', String? body}) {
    final encodedBody = body == null ? '' : Uri.encodeComponent(body);
    final uri = phone.isEmpty
        ? Uri.parse('sms:?body=$encodedBody')
        : Uri.parse('sms:${Uri.encodeComponent(phone)}?body=$encodedBody');
    return _launch(uri.toString());
  }

  static Future<bool> openWhatsApp({String phone = '', String? body}) {
    final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    final text = body == null ? '' : Uri.encodeComponent(body);
    final uri = digits.isEmpty
        ? 'https://wa.me/?text=$text'
        : 'https://wa.me/$digits?text=$text';
    return _launch(uri);
  }

  /// Native navigation intent first (Android) / Maps (iOS), then a web maps
  /// link as a universal fallback.
  static Future<bool> navigate({
    required double? lat,
    required double? lng,
    required String label,
    required String address,
  }) async {
    if (lat != null && lng != null) {
      final native = await NativePlatform.openNavigation(lat: lat, lng: lng, label: label);
      if (native) return true;
      return _launch(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
      );
    }
    return _launch(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}',
    );
  }

  /// OS share sheet when the native module is present, SMS composer otherwise.
  static Future<bool> share(String text) async {
    if (await NativePlatform.shareText(text)) return true;
    return openSms(body: text);
  }

  static Future<bool> _launch(String url) async {
    try {
      final uri = Uri.parse(url);
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
