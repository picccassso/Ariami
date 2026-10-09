import 'song.dart';

/// Snapshot of a removed queue item so the removal can be undone.
class QueueItemRemoval {
  final Song song;
  final int index;
  final bool wasCurrent;
  final bool wasPlaying;
  final bool wasOneShot;

  /// True when the removal edited a mirrored (Ariami Connect) queue, so undo
  /// must go back out as a Connect command instead of touching the local queue.
  final bool wasRemote;

  const QueueItemRemoval({
    required this.song,
    required this.index,
    required this.wasCurrent,
    required this.wasPlaying,
    required this.wasOneShot,
    this.wasRemote = false,
  });
}

class PlaybackQueue {
  final List<Song> _songs = <Song>[];
  int _currentIndex = 0;
  int _revision = 0;

  PlaybackQueue({
    List<Song>? songs,
    int currentIndex = 0,
  }) {
    if (songs != null) _songs.addAll(songs);
    _currentIndex =
        _songs.isEmpty ? 0 : currentIndex.clamp(0, _songs.length - 1);
  }

  List<Song> get songs => List.unmodifiable(_songs);

  int get currentIndex => _currentIndex;

  /// Changes only when the serialized queue/order changes. Playback progress
  /// and current-index moves deliberately leave it alone so Connect can reuse
  /// its cached queue payload between progress ticks.
  int get revision => _revision;

  Song? get currentSong {
    if (_songs.isEmpty || _currentIndex < 0 || _currentIndex >= _songs.length) {
      return null;
    }
    return _songs[_currentIndex];
  }

  Song? get nextSong {
    if (!hasNext) return null;
    return _songs[_currentIndex + 1];
  }

  Song? get previousSong {
    if (!hasPrevious) return null;
    return _songs[_currentIndex - 1];
  }

  bool get hasNext => _currentIndex < _songs.length - 1;

  bool get hasPrevious => _currentIndex > 0;

  int get length => _songs.length;

  bool get isEmpty => _songs.isEmpty;

  bool get isNotEmpty => _songs.isNotEmpty;

  void addSong(Song song) {
    _songs.add(song);
    _revision++;
  }

  void insertSong(int index, Song song) {
    if (index < 0 || index > _songs.length) return;
    _songs.insert(index, song);
    _revision++;

    // Adjust current index if insertion affects it
    if (index <= _currentIndex) {
      _currentIndex++;
    }
  }

  void removeSong(int index) {
    if (index < 0 || index >= _songs.length) return;

    _songs.removeAt(index);
    _revision++;

    // Adjust current index if removal affects it
    if (index < _currentIndex) {
      _currentIndex--;
    } else if (index == _currentIndex && _currentIndex >= _songs.length) {
      _currentIndex = _songs.length - 1;
    }
  }

  void clear() {
    if (_songs.isEmpty) return;
    _songs.clear();
    _currentIndex = 0;
    _revision++;
  }

  void setQueue(List<Song> songs, {int currentIndex = 0}) {
    final replacement = List<Song>.of(songs);
    _songs
      ..clear()
      ..addAll(replacement);
    _currentIndex =
        replacement.isEmpty ? 0 : currentIndex.clamp(0, replacement.length - 1);
    _revision++;
  }

  bool jumpToIndex(int index) {
    if (index < 0 || index >= _songs.length) return false;
    _currentIndex = index;
    return true;
  }

  Map<String, dynamic> toJson() {
    return {
      'songs': _songs.map((s) => s.toJson()).toList(),
      'currentIndex': _currentIndex,
    };
  }

  factory PlaybackQueue.fromJson(Map<String, dynamic> json) {
    final songsList = (json['songs'] as List<dynamic>)
        .map((s) => Song.fromJson(s as Map<String, dynamic>))
        .toList();

    return PlaybackQueue(
      songs: songsList,
      currentIndex: json['currentIndex'] as int? ?? 0,
    );
  }
}
