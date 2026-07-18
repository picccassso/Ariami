import 'dart:async';

import '../../../utils/shared_preferences_cache.dart';

/// How PLAYTIME (and AVG DAILY) render their durations. Tapping the metric
/// cycles through these in order and the choice is remembered.
enum PlaytimeUnit { hours, minutes, minutesCompact }

/// PLAYTIME (and AVG DAILY, when shown) cycle through hours, minutes, and
/// compact minutes when the PLAYTIME metric is tapped. Until the very first
/// tap a little finger demonstrates the gesture on the metric, and that
/// first tap triggers a one-time explainer dialog.
class PlaytimeFormat {
  static const String _hintSeenKey = 'stats_playtime_hint_seen';
  static const String _unitKey = 'stats_playtime_unit';

  PlaytimeUnit unit = PlaytimeUnit.hours;
  bool hintPending = false;

  /// PLAYTIME total (ms) for the currently shown view, recorded while
  /// formatting so the tap handler can skip compact minutes when it wouldn't
  /// differ from plain minutes (i.e. under 1000 minutes).
  int lastTotalMs = 0;

  PlaytimeFormat.load() {
    final unitIndex = sharedPrefs.getInt(_unitKey) ?? 0;
    unit =
        PlaytimeUnit.values[unitIndex.clamp(0, PlaytimeUnit.values.length - 1)];
    hintPending = !(sharedPrefs.getBool(_hintSeenKey) ?? false);
  }

  /// Formats the PLAYTIME total and records it so the tap handler can skip
  /// compact minutes when it wouldn't differ from plain minutes.
  String formatPlaytime(Duration duration) {
    lastTotalMs = duration.inMilliseconds;
    return formatDurationShort(duration);
  }

  String formatDurationShort(Duration duration) {
    switch (unit) {
      case PlaytimeUnit.minutes:
        return '${duration.inMinutes}m';
      case PlaytimeUnit.minutesCompact:
        return _formatMinutesCompact(duration);
      case PlaytimeUnit.hours:
        if (duration.inHours > 0) {
          return '${duration.inHours}h';
        }
        return '${duration.inMinutes}m';
    }
  }

  /// Compact minutes (e.g. 4221 → "4.2k"). Values under 1000 stay exact; the
  /// trailing ".0" is trimmed so 45000 reads "45k".
  static String _formatMinutesCompact(Duration duration) {
    final minutes = duration.inMinutes;
    if (minutes < 1000) return '${minutes}m';
    var text = (minutes / 1000).toStringAsFixed(1);
    if (text.endsWith('.0')) text = text.substring(0, text.length - 2);
    return '${text}k';
  }

  /// The next unit in the cycle, skipping compact minutes when it would render
  /// identically to plain minutes (under 1000 minutes) so the user never taps
  /// through a no-op change on the way back to hours.
  PlaytimeUnit _nextUnit(PlaytimeUnit current) {
    var next =
        PlaytimeUnit.values[(current.index + 1) % PlaytimeUnit.values.length];
    if (next == PlaytimeUnit.minutesCompact &&
        Duration(milliseconds: lastTotalMs).inMinutes < 1000) {
      next = PlaytimeUnit.hours;
    }
    return next;
  }

  /// Advances to the next unit and persists the choice. Returns true when
  /// this was the very first tap (the hint was still pending), so the caller
  /// can show the one-time explainer dialog.
  bool advance() {
    unit = _nextUnit(unit);
    final firstTap = hintPending;
    hintPending = false;
    unawaited(sharedPrefs.setInt(_unitKey, unit.index));
    if (firstTap) unawaited(sharedPrefs.setBool(_hintSeenKey, true));
    return firstTap;
  }
}
