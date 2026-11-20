import '../models/player_models.dart';

/// Separates a user's remote-streaming preference from the quality that the
/// current connection is allowed to request.
///
/// Remote clients may choose any quality. The player attached to this
/// desktop's embedded server always requests the original file (read directly
/// from the library files, with loopback only as a fallback when the file is
/// missing), while retaining the remote preference for a later switch back to
/// client mode.
class PlaybackQualityPolicy {
  StreamQuality _preferredQuality = StreamQuality.high;
  bool _isLocalPlayback = false;

  StreamQuality get preferredQuality => _preferredQuality;
  bool get isLocalPlayback => _isLocalPlayback;
  bool get canSelectQuality => !_isLocalPlayback;

  StreamQuality get effectiveQuality =>
      _isLocalPlayback ? StreamQuality.high : _preferredQuality;

  bool setLocalPlayback(bool value) {
    if (_isLocalPlayback == value) return false;
    _isLocalPlayback = value;
    return true;
  }

  bool setPreferredQuality(StreamQuality value) {
    if (!canSelectQuality || _preferredQuality == value) return false;
    _preferredQuality = value;
    return true;
  }

  /// Restores a saved preference even during local playback. It remains
  /// dormant until this desktop next connects as a remote client.
  bool restorePreferredQuality(StreamQuality value) {
    if (_preferredQuality == value) return false;
    _preferredQuality = value;
    return true;
  }
}
