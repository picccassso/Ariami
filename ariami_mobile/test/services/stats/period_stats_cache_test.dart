import 'package:ariami_mobile/models/server_info.dart';
import 'package:ariami_mobile/services/stats/period_stats_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = await SharedPreferences.getInstance();
  });

  test('persists exact ranges and isolates account scopes', () async {
    final cache = PeriodStatsCache.withPreferences(preferences);
    const stats = <String, dynamic>{
      'from': '2026-07-17',
      'to': '2026-07-17',
      'totalPlays': 4,
    };

    await cache.write(
      scope: 'server-a|user-a',
      from: '2026-07-17',
      to: '2026-07-17',
      stats: stats,
    );
    final reloadedCache = PeriodStatsCache.withPreferences(preferences);

    expect(
      await reloadedCache.read(
        scope: 'server-a|user-a',
        from: '2026-07-17',
        to: '2026-07-17',
      ),
      stats,
    );
    expect(
      await cache.read(
        scope: 'server-a|user-b',
        from: '2026-07-17',
        to: '2026-07-17',
      ),
      isNull,
    );
    expect(
      await cache.read(
        scope: 'server-a|user-a',
        from: '2026-07-16',
        to: '2026-07-16',
      ),
      isNull,
    );
  });

  test('scope remains stable when the active server route changes', () {
    ServerInfo info(String server) => ServerInfo(
          server: server,
          lanServer: '192.168.1.20',
          tailscaleServer: '100.64.0.20',
          port: 8642,
          name: 'Bedroom Mac',
          version: '5.0.0',
        );

    expect(
      PeriodStatsCache.scopeFor(
        userId: 'user-1',
        serverInfo: info('192.168.1.20'),
      ),
      PeriodStatsCache.scopeFor(
        userId: 'user-1',
        serverInfo: info('100.64.0.20'),
      ),
    );
  });

  test('evicts the oldest snapshot and can clear only one account', () async {
    var now = DateTime(2026, 7, 17, 10);
    final cache = PeriodStatsCache.withPreferences(
      preferences,
      maxEntries: 2,
      now: () => now,
    );

    Future<void> write(String scope, String day, int plays) => cache.write(
          scope: scope,
          from: day,
          to: day,
          stats: <String, dynamic>{'totalPlays': plays},
        );

    await write('account-a', '2026-07-15', 1);
    now = now.add(const Duration(minutes: 1));
    await write('account-b', '2026-07-16', 2);
    now = now.add(const Duration(minutes: 1));
    await write('account-a', '2026-07-17', 3);

    expect(
      await cache.read(
        scope: 'account-a',
        from: '2026-07-15',
        to: '2026-07-15',
      ),
      isNull,
    );
    expect(
      await cache.read(
        scope: 'account-b',
        from: '2026-07-16',
        to: '2026-07-16',
      ),
      isNotNull,
    );

    await cache.clearScope('account-a');
    expect(
      await cache.read(
        scope: 'account-a',
        from: '2026-07-17',
        to: '2026-07-17',
      ),
      isNull,
    );
    expect(
      await cache.read(
        scope: 'account-b',
        from: '2026-07-16',
        to: '2026-07-16',
      ),
      isNotNull,
    );
  });
}
