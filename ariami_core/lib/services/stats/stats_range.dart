/// User-selectable listening-stats ranges, shared by the mobile and desktop
/// stats screens so "week" and "month" mean exactly the same thing on every
/// client.
library;

/// Which slice of listening history a stats view is showing.
enum StatsRangeKind { all, today, day, week, month, year }

/// A user-selectable stats range. All-time keeps a client's local/summary
/// view; other ranges are normally served by the server's day/period
/// endpoints.
///
/// Ranges are anchorable: `weekOf`/`monthOf`/`yearOf` pin a range to the
/// calendar unit containing that date, and [stepped] moves one unit at a
/// time, so the UI can page through history stats.fm-style. Un-anchored
/// ranges resolve against "now" at query time.
class StatsRange {
  const StatsRange._(this.kind, [this.day]);

  final StatsRangeKind kind;

  /// The anchor date: the picked day for [StatsRangeKind.day], or the date
  /// whose calendar week/month/year the range covers. Null resolves to now.
  final DateTime? day;

  static const StatsRange all = StatsRange._(StatsRangeKind.all);
  static const StatsRange today = StatsRange._(StatsRangeKind.today);
  static const StatsRange week = StatsRange._(StatsRangeKind.week);
  static const StatsRange month = StatsRange._(StatsRangeKind.month);
  static const StatsRange year = StatsRange._(StatsRangeKind.year);

  factory StatsRange.specificDay(DateTime day) =>
      StatsRange._(StatsRangeKind.day, _dateOnly(day));

  /// The calendar week (Monday–Sunday) containing [day].
  factory StatsRange.weekOf(DateTime day) =>
      StatsRange._(StatsRangeKind.week, _dateOnly(day));

  /// The calendar month containing [day].
  factory StatsRange.monthOf(DateTime day) =>
      StatsRange._(StatsRangeKind.month, _dateOnly(day));

  /// The calendar year containing [day].
  factory StatsRange.yearOf(DateTime day) =>
      StatsRange._(StatsRangeKind.year, _dateOnly(day));

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool get isAllTime => kind == StatsRangeKind.all;

  DateTime _anchor(DateTime? now) => day ?? _dateOnly(now ?? DateTime.now());

  /// Inclusive `yyyy-mm-dd` local-day bounds, or null for all-time.
  /// Weeks are calendar Monday–Sunday; months/years are whole calendar
  /// units (future days in the current unit simply hold no data yet).
  ({String from, String to})? bounds({DateTime? now}) {
    switch (kind) {
      case StatsRangeKind.all:
        return null;
      case StatsRangeKind.today:
      case StatsRangeKind.day:
        final d = formatLocalDay(_anchor(now));
        return (from: d, to: d);
      case StatsRangeKind.week:
        final anchor = _anchor(now);
        final monday = DateTime(
            anchor.year, anchor.month, anchor.day - (anchor.weekday - 1));
        final sunday = DateTime(monday.year, monday.month, monday.day + 6);
        return (from: formatLocalDay(monday), to: formatLocalDay(sunday));
      case StatsRangeKind.month:
        final anchor = _anchor(now);
        return (
          from: formatLocalDay(DateTime(anchor.year, anchor.month, 1)),
          to: formatLocalDay(DateTime(anchor.year, anchor.month + 1, 0)),
        );
      case StatsRangeKind.year:
        final anchor = _anchor(now);
        return (
          from: formatLocalDay(DateTime(anchor.year, 1, 1)),
          to: formatLocalDay(DateTime(anchor.year, 12, 31)),
        );
    }
  }

  /// True when the range covers exactly one local day, i.e. the dedicated
  /// `/v2/listening/day` endpoint applies.
  bool get isSingleDay =>
      kind == StatsRangeKind.today || kind == StatsRangeKind.day;

  /// Whether ‹ › paging applies (everything except all-time).
  bool get isSteppable => kind != StatsRangeKind.all;

  /// Whether this range contains the complete recorded history between
  /// [firstPlayed] and [lastPlayed]. Missing or inverted boundaries are not
  /// treated as covered because the caller cannot safely substitute an
  /// all-time summary for a calendar-period response.
  bool coversHistory({
    required DateTime? firstPlayed,
    required DateTime? lastPlayed,
    DateTime? now,
  }) {
    if (firstPlayed == null || lastPlayed == null) return false;
    final first = formatLocalDay(firstPlayed);
    final last = formatLocalDay(lastPlayed);
    if (first.compareTo(last) > 0) return false;
    final b = bounds(now: now);
    if (b == null) return true;
    return first.compareTo(b.from) >= 0 && last.compareTo(b.to) <= 0;
  }

  /// The same granularity shifted by [delta] units (days, weeks, months or
  /// years). All-time is unaffected. Uses calendar arithmetic, so stepping
  /// is DST-safe and month steps land on the 1st.
  StatsRange stepped(int delta, {DateTime? now}) {
    if (delta == 0 || !isSteppable) return this;
    final base = _anchor(now);
    switch (kind) {
      case StatsRangeKind.all:
        return this;
      case StatsRangeKind.today:
      case StatsRangeKind.day:
        return StatsRange.specificDay(
            DateTime(base.year, base.month, base.day + delta));
      case StatsRangeKind.week:
        return StatsRange.weekOf(
            DateTime(base.year, base.month, base.day + 7 * delta));
      case StatsRangeKind.month:
        return StatsRange.monthOf(DateTime(base.year, base.month + delta, 1));
      case StatsRangeKind.year:
        return StatsRange.yearOf(DateTime(base.year + delta, 1, 1));
    }
  }

  /// False once this range already reaches today — there is no listening in
  /// the future to page to.
  bool canStepForward({DateTime? now}) {
    final b = bounds(now: now);
    if (b == null) return false;
    return b.to.compareTo(formatLocalDay(now ?? DateTime.now())) < 0;
  }

  /// False once this range already reaches the account's first listening
  /// day ([earliestDay], `yyyy-mm-dd`; null means no history at all).
  bool canStepBack(String? earliestDay, {DateTime? now}) {
    if (earliestDay == null) return false;
    final b = bounds(now: now);
    if (b == null) return false;
    return b.from.compareTo(earliestDay) > 0;
  }

  static const List<String> _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static const List<String> _monthAbbr = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// A human label for the stepper: "Today", "12 Jun 2026",
  /// "6 – 12 Jul 2026", "July 2026", "2026" or "All time".
  String title({DateTime? now}) {
    final today = _dateOnly(now ?? DateTime.now());
    switch (kind) {
      case StatsRangeKind.all:
        return 'All time';
      case StatsRangeKind.today:
      case StatsRangeKind.day:
        final anchor = _anchor(now);
        if (anchor == today) return 'Today';
        if (anchor == DateTime(today.year, today.month, today.day - 1)) {
          return 'Yesterday';
        }
        return '${anchor.day} ${_monthAbbr[anchor.month - 1]} ${anchor.year}';
      case StatsRangeKind.week:
        final anchor = _anchor(now);
        final monday = DateTime(
            anchor.year, anchor.month, anchor.day - (anchor.weekday - 1));
        final sunday = DateTime(monday.year, monday.month, monday.day + 6);
        if (monday.month == sunday.month) {
          return '${monday.day} – ${sunday.day} '
              '${_monthAbbr[monday.month - 1]} ${monday.year}';
        }
        return '${monday.day} ${_monthAbbr[monday.month - 1]} – '
            '${sunday.day} ${_monthAbbr[sunday.month - 1]} ${sunday.year}';
      case StatsRangeKind.month:
        final anchor = _anchor(now);
        return '${_monthNames[anchor.month - 1]} ${anchor.year}';
      case StatsRangeKind.year:
        return '${_anchor(now).year}';
    }
  }

  @override
  bool operator ==(Object other) =>
      other is StatsRange && other.kind == kind && other.day == day;

  @override
  int get hashCode => Object.hash(kind, day);

  static String formatLocalDay(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
