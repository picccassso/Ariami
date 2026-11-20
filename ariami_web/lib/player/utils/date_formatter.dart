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
