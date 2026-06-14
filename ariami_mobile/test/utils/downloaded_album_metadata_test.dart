import 'package:ariami_mobile/models/download_task.dart';
import 'package:ariami_mobile/utils/downloaded_album_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the specific stored album artist', () {
    expect(
      resolveDownloadedAlbumArtist([
        _task(artist: 'Track Artist', albumArtist: 'Album Artist'),
      ]),
      'Album Artist',
    );
  });

  test('uses the shared track artist instead of Various Artists', () {
    expect(
      resolveDownloadedAlbumArtist([
        _task(artist: 'Real Artist', albumArtist: 'Various Artists'),
        _task(artist: 'Real Artist', albumArtist: 'Various Artists'),
      ]),
      'Real Artist',
    );
  });

  test('keeps Various Artists when downloaded track artists disagree', () {
    expect(
      resolveDownloadedAlbumArtist([
        _task(artist: 'First Artist', albumArtist: 'Various Artists'),
        _task(artist: 'Second Artist', albumArtist: 'Various Artists'),
      ]),
      'Various Artists',
    );
  });

  test('uses track artist when stored album artist is a YouTube channel name',
      () {
    expect(
      resolveDownloadedAlbumArtist([
        _task(artist: 'Steve Berman', albumArtist: 'EminemMusic'),
        _task(artist: 'Eminem', albumArtist: 'EminemMusic'),
        _task(artist: 'Eminem', albumArtist: 'EminemMusic'),
      ]),
      'Eminem',
    );
    expect(
      resolveDownloadedAlbumArtist([
        _task(artist: 'NF', albumArtist: 'NFrealmusic'),
        _task(artist: 'NF', albumArtist: 'NFrealmusic'),
      ]),
      'NF',
    );
  });
}

DownloadTask _task({
  required String artist,
  required String? albumArtist,
}) {
  return DownloadTask(
    id: 'song_$artist',
    songId: artist,
    title: 'Song',
    artist: artist,
    albumId: 'album',
    albumName: 'Album',
    albumArtist: albumArtist,
    albumArt: '',
    downloadUrl: '',
    totalBytes: 1,
  );
}
