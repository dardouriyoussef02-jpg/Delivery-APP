/// Presentation helpers: compact, driver-friendly formatting without pulling
/// in a localisation package.
library;

String twoDigits(int value) => value.toString().padLeft(2, '0');

String timeOfDay(DateTime value) => '${twoDigits(value.hour)}:${twoDigits(value.minute)}';

String timeWindow(DateTime start, DateTime end) => '${timeOfDay(start)} – ${timeOfDay(end)}';

String _shortDate(DateTime value) => '${value.day}/${value.month}';

/// "in 12 min", "45 min ago", "tomorrow 09:15"
String relativeTime(DateTime value, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final difference = value.difference(reference);
  final minutes = difference.inMinutes.abs();

  if (difference.isNegative) {
    if (minutes < 60) return '$minutes min ago';
    if (minutes < 24 * 60) return '${difference.inHours.abs()} h ago';
    return '${_shortDate(value)} at ${timeOfDay(value)}';
  }

  if (minutes < 1) return 'now';
  if (minutes < 60) return 'in $minutes min';
  if (minutes < 24 * 60) return 'in ${difference.inHours} h';
  return 'in ${difference.inDays} d';
}

/// "Today 15:52" / "27/9 15:52"
String dateTimeShort(DateTime value, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final sameDay = value.year == reference.year && value.month == reference.month && value.day == reference.day;
  final tomorrow = reference.add(const Duration(days: 1));
  final isTomorrow = value.year == tomorrow.year && value.month == tomorrow.month && value.day == tomorrow.day;
  if (sameDay) return 'Today ${timeOfDay(value)}';
  if (isTomorrow) return 'Tomorrow ${timeOfDay(value)}';
  return '${_shortDate(value)} ${timeOfDay(value)}';
}

String distance(double km) => '${km.toStringAsFixed(1)} km';

const Map<String, String> _currencySymbols = {'EUR': '€', 'GBP': '£', 'USD': '\$', 'CHF': 'CHF '};

String money(double amount, String currency) {
  final symbol = _currencySymbols[currency] ?? '$currency ';
  return '$symbol${amount.toStringAsFixed(2)}';
}

String plural(int count, String singular, {String? pluralForm}) {
  final word = count == 1 ? singular : (pluralForm ?? '${singular}s');
  return '$count $word';
}

/// Shortens a note for a one-line preview.
String preview(String text, {int max = 90}) {
  final trimmed = text.trim();
  return trimmed.runes.length <= max ? trimmed : '${String.fromCharCodes(trimmed.runes.take(max - 1))}…';
}
