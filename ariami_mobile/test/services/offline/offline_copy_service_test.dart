import 'package:ariami_mobile/models/download_task.dart';
import 'package:ariami_mobile/services/offline/offline_copy_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late OfflineCopyService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = OfflineCopyService()..resetToDefaults();
  });

  test('retains completed downloads removed from the server', () async {
    await service.reconcileAlbums(
      tasks: [
        _task('removed-song', albumId: 'removed-album'),
        _task('still-here', albumId: 'server-album'),
      ],
      serverSongIds: {'still-here'},
      serverAlbumIds: {'server-album'},
    );

    expect(service.retainedSongIds, {'removed-song'});
    expect(service.retainedAlbumIds, {'removed-album'});
  });

  test('automatically relinks retained downloads when stable IDs return',
      () async {
    final task = _task('song-1', albumId: 'album-1');

    await service.reconcileAlbums(
      tasks: [task],
      serverSongIds: {},
      serverAlbumIds: {},
    );
    expect(service.isRetainedAlbum('album-1'), isTrue);

    await service.reconcileAlbums(
      tasks: [task],
      serverSongIds: {'song-1'},
      serverAlbumIds: {'album-1'},
    );

    expect(service.retainedSongIds, isEmpty);
    expect(service.retainedAlbumIds, isEmpty);
  });

  test('retains an album when its songs remain visible during sync', () async {
    await service.reconcileAlbums(
      tasks: [_task('still-visible-song', albumId: 'removed-album')],
      serverSongIds: {'still-visible-song'},
      serverAlbumIds: {},
    );

    expect(service.retainedAlbumIds, {'removed-album'});
    expect(service.retainedSongIds, {'still-visible-song'});
  });

  test('claims an offline-copy notice only once', () async {
    expect(await service.claimNotice('album', 'album-1'), isTrue);
    expect(await service.claimNotice('album', 'album-1'), isFalse);
  });
}

DownloadTask _task(String songId, {required String albumId}) {
  return DownloadTask(
    id: 'song_$songId',
    songId: songId,
    title: songId,
    artist: 'Artist',
    albumId: albumId,
    albumName: 'Album',
    albumArt: '',
    downloadUrl: '',
    status: DownloadStatus.completed,
    bytesDownloaded: 100,
    totalBytes: 100,
  );
}
