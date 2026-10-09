import 'package:ariami_core/utils/format.dart';
import 'package:test/test.dart';

void main() {
  group('formatMinSec', () {
    test('formats zero, under ten seconds and minutes', () {
      expect(formatMinSec(0), '0:00');
      expect(formatMinSec(5), '0:05');
      expect(formatMinSec(30), '0:30');
      expect(formatMinSec(60), '1:00');
      expect(formatMinSec(185), '3:05');
    });

    test('does not roll over into hours', () {
      expect(formatMinSec(3600), '60:00');
      expect(formatMinSec(3725), '62:05');
    });

    test('negative input keeps the old truncate/modulo behaviour', () {
      expect(formatMinSec(-5), '0:55');
    });
  });

  group('formatDurationMinSec', () {
    test('matches formatMinSec and truncates sub-seconds', () {
      expect(formatDurationMinSec(Duration.zero), '0:00');
      expect(formatDurationMinSec(const Duration(seconds: 65)), '1:05');
      expect(formatDurationMinSec(const Duration(hours: 1, seconds: 1)),
          '60:01');
      expect(formatDurationMinSec(const Duration(milliseconds: 1999)), '0:01');
    });
  });

  group('formatClockDuration', () {
    test('uses m:ss below one hour', () {
      expect(formatClockDuration(Duration.zero), '0:00');
      expect(formatClockDuration(const Duration(seconds: 9)), '0:09');
      expect(formatClockDuration(const Duration(minutes: 59, seconds: 59)),
          '59:59');
    });

    test('uses h:mm:ss from one hour up', () {
      expect(formatClockDuration(const Duration(hours: 1)), '1:00:00');
      expect(
          formatClockDuration(
              const Duration(hours: 2, minutes: 3, seconds: 4)),
          '2:03:04');
      expect(formatClockDuration(const Duration(hours: 25)), '25:00:00');
    });
  });

  group('formatHoursMinutes', () {
    test('formats minutes only and hours with minutes', () {
      expect(formatHoursMinutes(0), '0 min');
      expect(formatHoursMinutes(59), '0 min');
      expect(formatHoursMinutes(540), '9 min');
      expect(formatHoursMinutes(3600), '1 hr 0 min');
      expect(formatHoursMinutes(5520), '1 hr 32 min');
    });
  });

  group('formatBytes', () {
    test('uses B below 1 KB', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(1023), '1023 B');
    });

    test('switches unit at the 1024 boundaries', () {
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(1024 * 1024 - 1), '1024.0 KB');
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(5 * 1024 * 1024 + 524288), '5.5 MB');
      expect(formatBytes(1024 * 1024 * 1024), '1.0 GB');
    });

    test('gbDecimals only affects GB', () {
      const gb = 1024 * 1024 * 1024;
      expect(formatBytes(gb + gb ~/ 8, gbDecimals: 2), '1.13 GB');
      expect(formatBytes(gb + gb ~/ 8), '1.1 GB');
      expect(formatBytes(2048, gbDecimals: 2), '2.0 KB');
    });
  });

  group('formatCountWithCommas', () {
    test('groups digits by three', () {
      expect(formatCountWithCommas(0), '0');
      expect(formatCountWithCommas(999), '999');
      expect(formatCountWithCommas(1000), '1,000');
      expect(formatCountWithCommas(1234567), '1,234,567');
    });
  });

  group('formatThousandsCompact', () {
    test('keeps one decimal and trims a trailing .0', () {
      expect(formatThousandsCompact(4221), '4.2k');
      expect(formatThousandsCompact(1000), '1k');
      expect(formatThousandsCompact(45000), '45k');
      expect(formatThousandsCompact(45500), '45.5k');
    });
  });
}
