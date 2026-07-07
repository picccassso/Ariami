import 'dart:math';

/// Shared identity contract for "created" playlists — brand-new playlists that
/// a client made itself, as opposed to server "folder" playlists scanned from
/// disk. Created playlists have no catalog/base entry; they live purely as
/// account-scoped playlist edits (empty base snapshot) so they sync across a
/// user's devices via the same edit store.
///
/// Every client (mobile, desktop, TV) must agree on this convention: whoever
/// creates the playlist stamps its id with [createdPlaylistPrefix], and every
/// client recognizes such ids so it can surface the playlist and resolve its
/// pin locally (the server's pin catalog cannot resolve a created playlist).

/// Prefix stamped onto every newly created playlist id.
const String createdPlaylistPrefix = 'created:';

/// Legacy prefix used by an early desktop release before the shared
/// convention landed. Still recognized so playlists made with it keep
/// syncing.
const String legacyDesktopCreatedPlaylistPrefix = 'desktop-created:';

/// Whether [playlistId] refers to a client-created playlist rather than a
/// server folder playlist. Recognizes both the current and legacy prefixes.
bool isCreatedPlaylistId(String playlistId) =>
    playlistId.startsWith(createdPlaylistPrefix) ||
    playlistId.startsWith(legacyDesktopCreatedPlaylistPrefix);

final Random _createdPlaylistRandom = Random();

/// Generates a fresh, collision-resistant created-playlist id. The timestamp
/// keeps ids roughly ordered; the random suffix avoids clashes when two
/// playlists are created within the same microsecond.
String newCreatedPlaylistId() {
  final micros = DateTime.now().microsecondsSinceEpoch;
  final suffix = _createdPlaylistRandom.nextInt(1 << 32).toRadixString(16);
  return '$createdPlaylistPrefix$micros-$suffix';
}
