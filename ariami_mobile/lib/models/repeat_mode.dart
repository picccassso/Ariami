/// Repeat modes for playback
enum RepeatMode {
  /// Play through queue once, then stop
  none,

  /// Repeat entire queue indefinitely
  all,

  /// Repeat current song indefinitely
  one;

  /// Get the next repeat mode (for cycling through modes)
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

  /// Get display name for UI
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

  /// Get icon name for UI (Material Icons)
  String get iconName {
    switch (this) {
      case RepeatMode.none:
        return 'repeat'; // repeat icon (inactive)
      case RepeatMode.all:
        return 'repeat'; // repeat icon (active)
      case RepeatMode.one:
        return 'repeat_one'; // repeat one icon
    }
  }

  /// Convert to string for persistence
  String toStorageString() {
    return name;
  }

  /// Parse from storage string
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
