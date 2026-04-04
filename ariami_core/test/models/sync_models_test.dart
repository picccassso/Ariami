import 'package:ariami_core/models/api_models.dart';
import 'package:test/test.dart';

void main() {
  group('V2PageInfo', () {
    test('serializes and deserializes', () {
      final model = V2PageInfo(
        cursor: 'cursor-1',
        nextCursor: 'cursor-2',
        hasMore: true,
        limit: 100,
      );

      final json = model.toJson();
      final parsed = V2PageInfo.fromJson(json);

      expect(parsed.cursor, 'cursor-1');
      expect(parsed.nextCursor, 'cursor-2');
      expect(parsed.hasMore, isTrue);
      expect(parsed.limit, 100);
    });
  });

  group('V2BootstrapResponse', () {
    test('serializes and deserializes', () {
      final model = V2BootstrapResponse(
        syncToken: 42,
        albums: [
          AlbumModel(
            id: 'album-1',
            title: 'Album 1',
            artist: 'Artist 1',
            coverArt: 'cover-1',
            songCount: 2,
            duration: 300,
          ),
        ],
        songs: [
          SongModel(
            id: 'song-1',
            title: 'Song 1',
            artist: 'Artist 1',
            albumId: 'album-1',
            duration: 180,
            trackNumber: 1,
          ),
        ],
        playlists: [
          PlaylistModel(
            id: 'playlist-1',
            name: 'Playlist 1',
            songCount: 1,
            duration: 180,
          ),
        ],
        pageInfo: V2PageInfo(
          cursor: null,
          nextCursor: 'next',
          hasMore: true,
          limit: 500,
        ),
      );

      final json = model.toJson();
      final parsed = V2BootstrapResponse.fromJson(json);

      expect(parsed.syncToken, 42);
      expect(parsed.albums.single.id, 'album-1');
      expect(parsed.songs.single.id, 'song-1');
      expect(parsed.playlists.single.id, 'playlist-1');
      expect(parsed.pageInfo.nextCursor, 'next');
      expect(parsed.pageInfo.hasMore, isTrue);
    });
  });

  group('V2ChangeEvent', () {
    test('serializes and deserializes with payload', () {
      final model = V2ChangeEvent(
        token: 101,
        op: V2ChangeOperation.upsert,
        entityType: V2EntityType.playlistSong,
        entityId: 'playlist-1:0',
        payload: {
          'playlistId': 'playlist-1',
          'songId': 'song-1',
          'position': 0
        },
        occurredAt: '2026-02-07T10:00:00Z',
      );

      final json = model.toJson();
      final parsed = V2ChangeEvent.fromJson(json);

      expect(parsed.token, 101);
      expect(parsed.op, V2ChangeOperation.upsert);
      expect(parsed.entityType, V2EntityType.playlistSong);
      expect(parsed.entityId, 'playlist-1:0');
      expect(parsed.payload?['playlistId'], 'playlist-1');
      expect(parsed.payload?['position'], 0);
      expect(parsed.occurredAt, '2026-02-07T10:00:00Z');
    });

    test('serializes and deserializes without payload', () {
      final model = V2ChangeEvent(
        token: 102,
        op: V2ChangeOperation.delete,
        entityType: V2EntityType.album,
        entityId: 'album-1',
        payload: null,
        occurredAt: '2026-02-07T10:05:00Z',
      );

      final json = model.toJson();
      final parsed = V2ChangeEvent.fromJson(json);

      expect(parsed.op, V2ChangeOperation.delete);
      expect(parsed.entityType, V2EntityType.album);
      expect(parsed.payload, isNull);
    });
  });

  group('V2ChangesResponse', () {
    test('serializes and deserializes', () {
      final model = V2ChangesResponse(
        fromToken: 100,
        toToken: 102,
        events: [
          V2ChangeEvent(
            token: 101,
            op: V2ChangeOperation.upsert,
            entityType: V2EntityType.song,
            entityId: 'song-1',
            payload: {'id': 'song-1'},
            occurredAt: '2026-02-07T10:01:00Z',
          ),
          V2ChangeEvent(
            token: 102,
            op: V2ChangeOperation.delete,
            entityType: V2EntityType.artwork,
            entityId: 'art-1',
            payload: null,
            occurredAt: '2026-02-07T10:02:00Z',
          ),
        ],
        hasMore: false,
      );

      final json = model.toJson();
      final parsed = V2ChangesResponse.fromJson(json);

      expect(parsed.fromToken, 100);
      expect(parsed.toToken, 102);
      expect(parsed.events.length, 2);
      expect(parsed.events.first.entityType, V2EntityType.song);
      expect(parsed.events.last.entityType, V2EntityType.artwork);
      expect(parsed.hasMore, isFalse);
    });
  });
}
