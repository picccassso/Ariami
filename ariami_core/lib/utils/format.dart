// Shared display formatters for durations, byte sizes and counts.

/// Whole seconds as `m:ss` (`185` -> `3:05`). Minutes are not capped at 59.
String formatMinSec(int seconds) {
  final minutes = seconds ~/ 60;
  final secs = seconds % 60;
  return '$minutes:${secs.toString().padLeft(2, '0')}';
}

/// [duration] as `m:ss`, see [formatMinSec].
String formatDurationMinSec(Duration duration) =>
    formatMinSec(duration.inSeconds);

/// [duration] as `m:ss`, or `h:mm:ss` from one hour up.
String formatClockDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final ss = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$ss';
  }
  return '$minutes:$ss';
}

/// Whole seconds as `12 min`, or `1 hr 12 min` from one hour up.
String formatHoursMinutes(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours > 0) {
    return '$hours hr $minutes min';
  }
  return '$minutes min';
}

/// Bytes as `B` / `KB` / `MB` / `GB` (1024-based). KB and MB show one
/// decimal; GB shows [gbDecimals].
String formatBytes(int bytes, {int gbDecimals = 1}) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(gbDecimals)} GB';
}

/// `1234567` -> `1,234,567`.
String formatCountWithCommas(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Thousands with one decimal and an `k` suffix (`4221` -> `4.2k`); the
/// trailing `.0` is trimmed so `45000` reads `45k`.
String formatThousandsCompact(int value) {
  var text = (value / 1000).toStringAsFixed(1);
  if (text.endsWith('.0')) text = text.substring(0, text.length - 2);
  return '${text}k';
}
