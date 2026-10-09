enum RepeatMode {
  /// Play through queue once, then stop
  none,

  /// Repeat entire queue indefinitely
  all,

  /// Repeat current song indefinitely
  one;

  RepeatMode get next {
    switch (this) {
      case RepeatMode.none:
        return RepeatMode.all;
      case RepeatMode.all:
        return RepeatMode.one;
      case RepeatMode.one:
        return RepeatMode.none;
    }
  }

  /// Match Spotify-style behavior when the user selects a different song.
  RepeatMode get forNewSongSelection {
    switch (this) {
      case RepeatMode.one:
        return RepeatMode.all;
      case RepeatMode.none:
      case RepeatMode.all:
        return this;
    }
  }

  bool get allowsBoundaryRestart => this != RepeatMode.none;

  String get displayName {
    switch (this) {
      case RepeatMode.none:
        return 'Off';
      case RepeatMode.all:
        return 'All';
      case RepeatMode.one:
        return 'One';
    }
  }

  String toStorageString() {
    return name;
  }

  static RepeatMode fromStorageString(String? value) {
    if (value == null) return RepeatMode.none;

    switch (value) {
      case 'all':
        return RepeatMode.all;
      case 'one':
        return RepeatMode.one;
      default:
        return RepeatMode.none;
    }
  }
}
