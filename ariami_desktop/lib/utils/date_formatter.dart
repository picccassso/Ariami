/// Formats a [DateTime] for dashboard display (relative or absolute).
String formatDashboardDateTime(DateTime? dateTime) {
  if (dateTime == null) return '—';
  final now = DateTime.now();
  final difference = now.difference(dateTime);

  if (difference.inSeconds < 60) {
    return 'Just now';
  } else if (difference.inMinutes < 60) {
    return '${difference.inMinutes} min ago';
  } else if (difference.inHours < 24) {
    return '${difference.inHours} hours ago';
  } else {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}

/// Date only, for spans where a time of day would be noise.
String formatDashboardDate(DateTime? dateTime) {
  if (dateTime == null) return '—';
  return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
}

/// Epoch millis to local time; null passes through so the formatters above
/// can render their em dash.
DateTime? millisToLocal(int? millis) =>
    millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);

/// `1234567` → `1,234,567`, so six-figure imports stay readable.
String formatDashboardCount(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
