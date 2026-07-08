import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:ariami_core/services/library/playlist_decision_store.dart';

void main() {
  late Directory tempDir;
  late String storePath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ariami_decisions_');
    storePath = p.join(tempDir.path, 'playlist_decisions.json');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('decisions round-trip through a fresh store instance', () async {
    final store = PlaylistDecisionStore(filePath: storePath);
    await store.ensureLoaded();
    await store.setDecision(
      '/music/Road Trip',
      PlaylistFolderDecision.import,
    );
    await store.setDecision(
      '/music/Downloads Dump',
      PlaylistFolderDecision.ignore,
    );

    final reloaded = PlaylistDecisionStore(filePath: storePath);
    await reloaded.ensureLoaded();

    expect(reloaded.importedFolderPaths, {'/music/Road Trip'});
    expect(reloaded.ignoredFolderPaths, {'/music/Downloads Dump'});
    final record = reloaded.decisionFor('/music/Road Trip')!;
    expect(record.decision, PlaylistFolderDecision.import);
    expect(record.decidedAt.isUtc, isTrue);
  });

  test('a newer decision for the same folder replaces the old one', () async {
    final store = PlaylistDecisionStore(filePath: storePath);
    await store.ensureLoaded();
    await store.setDecision('/music/Mix', PlaylistFolderDecision.ignore);
    await store.setDecision('/music/Mix', PlaylistFolderDecision.import);

    expect(store.decisions, hasLength(1));
    expect(store.importedFolderPaths, {'/music/Mix'});
    expect(store.ignoredFolderPaths, isEmpty);
  });

  test('clearDecision removes and persists; false when nothing stored',
      () async {
    final store = PlaylistDecisionStore(filePath: storePath);
    await store.ensureLoaded();
    await store.setDecision('/music/Mix', PlaylistFolderDecision.ignore);

    expect(await store.clearDecision('/music/Mix'), isTrue);
    expect(await store.clearDecision('/music/Mix'), isFalse);

    final reloaded = PlaylistDecisionStore(filePath: storePath);
    await reloaded.ensureLoaded();
    expect(reloaded.decisions, isEmpty);
  });

  test('rejects empty and relative folder paths', () async {
    final store = PlaylistDecisionStore(filePath: storePath);
    await store.ensureLoaded();

    expect(
      () => store.setDecision('   ', PlaylistFolderDecision.import),
      throwsArgumentError,
    );
    expect(
      () => store.setDecision('relative/mix', PlaylistFolderDecision.ignore),
      throwsArgumentError,
    );
  });

  test('malformed file loads as empty without throwing', () async {
    await File(storePath).writeAsString('{not json');

    final store = PlaylistDecisionStore(filePath: storePath);
    await store.ensureLoaded();
    expect(store.decisions, isEmpty);

    // The store still accepts new decisions afterwards.
    await store.setDecision('/music/Mix', PlaylistFolderDecision.import);
    expect(store.importedFolderPaths, {'/music/Mix'});
  });

  test('unknown decision names on disk are skipped, valid ones kept',
      () async {
    await File(storePath).writeAsString(jsonEncode({
      'version': 1,
      'decisions': [
        {'folderPath': '/music/Bad', 'decision': 'always'},
        {
          'folderPath': '/music/Good',
          'decision': 'import',
          'decidedAt': '2026-07-08T00:00:00.000Z',
        },
      ],
    }));

    final store = PlaylistDecisionStore(filePath: storePath);
    await store.ensureLoaded();
    expect(store.decisions, hasLength(1));
    expect(store.importedFolderPaths, {'/music/Good'});
  });

  test('parses wire decision names', () {
    expect(
      playlistFolderDecisionFromName('import'),
      PlaylistFolderDecision.import,
    );
    expect(
      playlistFolderDecisionFromName('ignore'),
      PlaylistFolderDecision.ignore,
    );
    expect(playlistFolderDecisionFromName('reset'), isNull);
    expect(playlistFolderDecisionFromName(null), isNull);
  });
}
