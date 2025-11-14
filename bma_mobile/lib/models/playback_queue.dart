import 'song.dart';

/// Manages the playback queue
class PlaybackQueue {
  List<Song> _songs = [];
  int _currentIndex = 0;

  PlaybackQueue({
    List<Song>? songs,
    int currentIndex = 0,
  }) {
    _songs = songs ?? [];
    _currentIndex = currentIndex;
  }

  /// Get all songs in queue
  List<Song> get songs => List.unmodifiable(_songs);

  /// Get current index
  int get currentIndex => _currentIndex;

  /// Get current song
  Song? get currentSong {
    if (_songs.isEmpty || _currentIndex < 0 || _currentIndex >= _songs.length) {
      return null;
    }
    return _songs[_currentIndex];
  }

  /// Get next song
  Song? get nextSong {
    if (!hasNext) return null;
    return _songs[_currentIndex + 1];
  }

  /// Get previous song
  Song? get previousSong {
    if (!hasPrevious) return null;
    return _songs[_currentIndex - 1];
  }

  /// Check if there's a next song
  bool get hasNext => _currentIndex < _songs.length - 1;

  /// Check if there's a previous song
  bool get hasPrevious => _currentIndex > 0;

  /// Get queue length
  int get length => _songs.length;

  /// Check if queue is empty
  bool get isEmpty => _songs.isEmpty;

  /// Check if queue is not empty
  bool get isNotEmpty => _songs.isNotEmpty;

  /// Add a song to the end of the queue
  void addSong(Song song) {
    _songs.add(song);
  }

  /// Add multiple songs to the end of the queue
  void addSongs(List<Song> songs) {
    _songs.addAll(songs);
  }

  /// Insert a song at a specific index
  void insertSong(int index, Song song) {
    if (index < 0 || index > _songs.length) return;
    _songs.insert(index, song);

    // Adjust current index if insertion affects it
    if (index <= _currentIndex) {
      _currentIndex++;
    }
  }

  /// Remove a song at a specific index
  void removeSong(int index) {
    if (index < 0 || index >= _songs.length) return;

    _songs.removeAt(index);

    // Adjust current index if removal affects it
    if (index < _currentIndex) {
      _currentIndex--;
    } else if (index == _currentIndex && _currentIndex >= _songs.length) {
      _currentIndex = _songs.length - 1;
    }
  }

  /// Move a song from one position to another
  void moveSong(int fromIndex, int toIndex) {
    if (fromIndex < 0 || fromIndex >= _songs.length) return;
    if (toIndex < 0 || toIndex >= _songs.length) return;
    if (fromIndex == toIndex) return;

    final song = _songs.removeAt(fromIndex);
    _songs.insert(toIndex, song);

    // Adjust current index based on the move
    if (fromIndex == _currentIndex) {
      // Moving the current song
      _currentIndex = toIndex;
    } else if (fromIndex < _currentIndex && toIndex >= _currentIndex) {
      // Moving a song from before to after current
      _currentIndex--;
    } else if (fromIndex > _currentIndex && toIndex <= _currentIndex) {
      // Moving a song from after to before current
      _currentIndex++;
    }
  }

  /// Clear the entire queue
  void clear() {
    _songs.clear();
    _currentIndex = 0;
  }

  /// Set the queue to a new list of songs
  void setQueue(List<Song> songs, {int currentIndex = 0}) {
    _songs = List.from(songs);
    _currentIndex = currentIndex.clamp(0, songs.length - 1);
  }

  /// Move to next song
  bool moveToNext() {
    if (!hasNext) return false;
    _currentIndex++;
    return true;
  }

  /// Move to previous song
  bool moveToPrevious() {
    if (!hasPrevious) return false;
    _currentIndex--;
    return true;
  }

  /// Jump to a specific index
  bool jumpToIndex(int index) {
    if (index < 0 || index >= _songs.length) return false;
    _currentIndex = index;
    return true;
  }

  /// Jump to a specific song
  bool jumpToSong(Song song) {
    final index = _songs.indexOf(song);
    if (index == -1) return false;
    _currentIndex = index;
    return true;
  }

  /// Convert to JSON for persistence
  Map<String, dynamic> toJson() {
    return {
      'songs': _songs.map((s) => s.toJson()).toList(),
      'currentIndex': _currentIndex,
    };
  }

  /// Create from JSON
  factory PlaybackQueue.fromJson(Map<String, dynamic> json) {
    final songsList = (json['songs'] as List<dynamic>)
        .map((s) => Song.fromJson(s as Map<String, dynamic>))
        .toList();

    return PlaybackQueue(
      songs: songsList,
      currentIndex: json['currentIndex'] as int? ?? 0,
    );
  }

  /// Create a copy
  PlaybackQueue copy() {
    return PlaybackQueue(
      songs: List.from(_songs),
      currentIndex: _currentIndex,
    );
  }
}
