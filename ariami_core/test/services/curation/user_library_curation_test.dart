import 'dart:io';

import 'package:ariami_core/models/hidden_item.dart';
import 'package:ariami_core/models/library_curation.dart';
import 'package:ariami_core/services/curation/user_library_curation_store.dart';
import 'package:ariami_core/services/hidden/hidden_item_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late UserLibraryCurationStore store;
  late HiddenItemStore hiddenStore;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ariami_curation_store_');
    store = UserLibraryCurationStore(
      databasePath: p.join(tempDir.path, 'user_library_curation.db'),
    )..initialize();
    hiddenStore = HiddenItemStore(
      databasePath: p.join(tempDir.path, 'hidden_items.db'),
    )..initialize();
  });

  tearDown(() async {
    store.close();
    hiddenStore.close();
    await tempDir.delete(recursive: true);
  });

  group('LibraryCurationFilter', () {
    test('full mode includes everything unless explicitly excluded', () {
      final filter = LibraryCurationFilter.fromCuration(
        UserLibraryCuration(
          userId: 'u1',
          mode: LibraryCurationMode.full,
          onboardingCompleted: true,
          revision: 1,
          updatedAt: DateTime.now().toUtc(),
          rules: [
            CurationRuleEntry(
              targetType: CurationTargetType.artist,
              targetId: 'Drake',
              action: CurationRuleAction.exclude,
              updatedAt: DateTime.now().toUtc(),
            ).normalized(),
            CurationRuleEntry(
              targetType: CurationTargetType.album,
              targetId: 'alb-drake-override',
              action: CurationRuleAction.include,
              updatedAt: DateTime.now().toUtc(),
            ),
            CurationRuleEntry(
              targetType: CurationTargetType.album,
              targetId: 'alb-bad',
              action: CurationRuleAction.exclude,
              updatedAt: DateTime.now().toUtc(),
            ),
            CurationRuleEntry(
              targetType: CurationTargetType.song,
              targetId: 'song-skip',
              action: CurationRuleAction.exclude,
              updatedAt: DateTime.now().toUtc(),
            ),
          ],
        ),
      );

      expect(filter.isAlbumIncluded(albumId: 'alb-ok', artist: 'Daft Punk'), isTrue);
      expect(filter.isAlbumIncluded(albumId: 'alb-drake', artist: 'Drake'), isFalse);
      expect(
        filter.isAlbumIncluded(albumId: 'alb-drake-override', artist: 'Drake'),
        isTrue,
      );
      expect(filter.isAlbumIncluded(albumId: 'alb-bad', artist: 'Daft Punk'), isFalse);

      expect(
        filter.isSongIncluded(
          songId: 's1',
          artist: 'Daft Punk',
          albumId: 'alb-ok',
        ),
        isTrue,
      );
      expect(
        filter.isSongIncluded(
          songId: 'song-skip',
          artist: 'Daft Punk',
          albumId: 'alb-ok',
        ),
        isFalse,
      );
      expect(
        filter.isSongIncluded(
          songId: 's2',
          artist: 'Future feat. Drake',
          albumId: 'alb-future',
        ),
        isFalse,
      );
    });

    test('curated mode respects artist credits, protected names, and overrides', () {
      final now = DateTime.now().toUtc();
      final filter = LibraryCurationFilter.fromCuration(
        UserLibraryCuration(
          userId: 'u2',
          mode: LibraryCurationMode.curated,
          onboardingCompleted: true,
          revision: 1,
          updatedAt: now,
          rules: [
            CurationRuleEntry(
              targetType: CurationTargetType.artist,
              targetId: 'Tyler, the Creator',
              action: CurationRuleAction.include,
              updatedAt: now,
            ).normalized(),
            CurationRuleEntry(
              targetType: CurationTargetType.artist,
              targetId: 'Kanye West',
              action: CurationRuleAction.include,
              updatedAt: now,
            ).normalized(),
            CurationRuleEntry(
              targetType: CurationTargetType.album,
              targetId: 'alb-yeezus',
              action: CurationRuleAction.exclude,
              updatedAt: now,
            ),
            CurationRuleEntry(
              targetType: CurationTargetType.album,
              targetId: 'alb-single-pick',
              action: CurationRuleAction.include,
              updatedAt: now,
            ),
            CurationRuleEntry(
              targetType: CurationTargetType.song,
              targetId: 'song-standalone',
              action: CurationRuleAction.include,
              updatedAt: now,
            ),
            CurationRuleEntry(
              targetType: CurationTargetType.playlist,
              targetId: 'pl-chill',
              action: CurationRuleAction.include,
              updatedAt: now,
            ),
          ],
        ),
      );

      // Protected artist name not split on comma
      expect(
        filter.isAlbumIncluded(albumId: 'alb-igor', artist: 'Tyler, the Creator'),
        isTrue,
      );
      // Multi-credit song includes included artist
      expect(
        filter.isSongIncluded(
          songId: 's-mercy',
          artist: 'Big Sean, Kanye West, Pusha T',
          albumId: 'alb-cruel',
        ),
        isTrue,
      );
      // Album exclusion overrides included artist
      expect(
        filter.isAlbumIncluded(albumId: 'alb-yeezus', artist: 'Kanye West'),
        isFalse,
      );
      expect(
        filter.isSongIncluded(
          songId: 's-black-skinhead',
          artist: 'Kanye West',
          albumId: 'alb-yeezus',
        ),
        isFalse,
      );
      // Single album included without including its artist
      expect(
        filter.isAlbumIncluded(albumId: 'alb-single-pick', artist: 'Daft Punk'),
        isTrue,
      );
      expect(
        filter.isAlbumIncluded(albumId: 'alb-other-daft', artist: 'Daft Punk'),
        isFalse,
      );
      // Standalone song included without including artist or album
      expect(
        filter.isSongIncluded(
          songId: 'song-standalone',
          artist: 'Unknown',
          albumId: null,
        ),
        isTrue,
      );
      // Playlists: server playlist included only if allowlisted; account playlists always included
      expect(filter.isServerPlaylistIncluded('pl-chill'), isTrue);
      expect(filter.isServerPlaylistIncluded('pl-other'), isFalse);
      expect(filter.isServerPlaylistIncluded('__LIKED_SONGS__'), isTrue);
      expect(filter.isServerPlaylistIncluded('created:123'), isTrue);
    });
  });

  group('UserLibraryCurationStore & Hidden migration', () {
    test('saves, reads, patches, and deletes per-user rules', () {
      final now = DateTime.now().toUtc();
      final saved = store.saveForUser(
        'u1',
        mode: LibraryCurationMode.curated,
        onboardingCompleted: true,
        rules: [
          CurationRuleEntry(
            targetType: CurationTargetType.artist,
            targetId: 'Radiohead',
            action: CurationRuleAction.include,
            updatedAt: now,
          ),
          CurationRuleEntry(
            targetType: CurationTargetType.album,
            targetId: 'alb-1',
            action: CurationRuleAction.exclude,
            updatedAt: now,
          ),
        ],
        sourceDeviceId: 'dev-1',
      );

      expect(saved.revision, 1);
      expect(saved.mode, LibraryCurationMode.curated);
      expect(saved.onboardingCompleted, isTrue);
      expect(saved.rules, hasLength(2));

      final loaded = store.getForUser('u1');
      expect(loaded.revision, 1);
      expect(loaded.mode, LibraryCurationMode.curated);
      expect(loaded.rules.map((r) => r.key),
          unorderedEquals(['artist:radiohead', 'album:alb-1']));

      final patched = store.applyPatchForUser(
        'u1',
        removeTargets: [
          (targetType: CurationTargetType.album, targetId: 'alb-1'),
        ],
        upsertRules: [
          CurationRuleEntry(
            targetType: CurationTargetType.song,
            targetId: 'song-9',
            action: CurationRuleAction.include,
            updatedAt: now,
          ),
        ],
      );
      expect(patched.revision, 2);
      expect(patched.rules.map((r) => r.key),
          unorderedEquals(['artist:radiohead', 'song:song-9']));

      store.deleteUser('u1');
      final afterDelete = store.getForUser('u1');
      expect(afterDelete.rules, isEmpty);
      expect(afterDelete.revision, 0);
    });

    test('migrates legacy hidden_items.db rows into exclude rules once', () {
      hiddenStore.hide('user-1', HiddenItem.albumType, 'alb-hidden');
      hiddenStore.hide('user-1', HiddenItem.artistType, 'Kanye West');
      hiddenStore.hide('admin-1', HiddenItem.playlistType, 'pl-hidden');

      final didRunFirst = store.migrateFromHiddenItems(
        hiddenStore,
        isAdminUser: (id) => id == 'admin-1',
      );
      expect(didRunFirst, isTrue);

      final user1 = store.getForUser('user-1');
      expect(user1.mode, LibraryCurationMode.full);
      expect(user1.onboardingCompleted, isFalse);
      expect(
        user1.rules.map((r) => '${r.action.wireName}:${r.key}'),
        unorderedEquals([
          'exclude:album:alb-hidden',
          'exclude:artist:kanye west',
        ]),
      );

      final admin1 = store.getForUser('admin-1');
      expect(admin1.onboardingCompleted, isTrue);
      expect(admin1.rules.single.key, 'playlist:pl-hidden');

      // Second run is a no-op
      hiddenStore.hide('user-1', HiddenItem.albumType, 'alb-after');
      final didRunSecond = store.migrateFromHiddenItems(hiddenStore);
      expect(didRunSecond, isFalse);
      expect(store.getForUser('user-1').rules, hasLength(2));
    });
  });
}
