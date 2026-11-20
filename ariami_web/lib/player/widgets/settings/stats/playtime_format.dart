import 'package:ariami_core/utils/format.dart';

/// How PLAYTIME (and AVG DAILY) render their durations. Tapping the metric
/// cycles through these in order and the choice is remembered.
enum PlaytimeUnit { hours, minutes, minutesCompact }

String formatListeningTime(int milliseconds) {
  if (milliseconds <= 0) return '0m';
  final duration = Duration(milliseconds: milliseconds);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours > 0) return '${hours}h ${minutes}m';
  if (duration.inMinutes > 0) return '${duration.inMinutes}m';
  return '<1m';
}

String formatListeningMinutes(int milliseconds) {
  if (milliseconds <= 0) return '0m';
  final minutes = Duration(milliseconds: milliseconds).inMinutes;
  return minutes > 0 ? '${minutes}m' : '<1m';
}

/// Compact minutes (e.g. 4221 → "4.2k"), for the third PLAYTIME unit. Values
/// under 1000 stay exact; the trailing ".0" is trimmed so 45000 reads "45k".
String formatListeningMinutesCompact(int milliseconds) {
  if (milliseconds <= 0) return '0m';
  final minutes = Duration(milliseconds: milliseconds).inMinutes;
  if (minutes <= 0) return '<1m';
  if (minutes < 1000) return '${minutes}m';
  return formatThousandsCompact(minutes);
}
