# Playlist detection rules

How the Ariami scanner decides what is a playlist, what is an album, and
what is merely *suggested* as a playlist. Implemented across
`library_scanner_isolate.dart`, `library_playlist_builder.dart`,
`playlist_folder_classifier.dart` and `m3u_playlist_parser.dart`.

## Core model

- A track can belong to an album **and** appear in any number of playlists.
  Playlist membership is additive, never destructive.
- Albums are built from tags only (album + album artist / normalized track
  artist). Folder paths never group albums.
- Playlists come from **explicit sources** (imported automatically),
  **high-confidence detections** (unmarked mixed-song folders with strong
  playlist evidence, also imported automatically), or **suggestions**
  (medium confidence, advisory only).
- Song IDs are always the MD5-prefix of the canonical file path; playlists
  reference those IDs, so listening stats, edits, and downloads are
  unaffected by playlist detection.

## Automatic (explicit sources)

Imported on every full scan without user confirmation:

1. **Marker folders** — a folder whose name *starts with* `[PLAYLIST]` in
   any casing (`[PLAYLIST] Gym`, `[playlist] Gym`, `[Playlist]Gym`). The
   marker is stripped from the displayed name. Nested marker folders
   collapse into the outermost one. Entries use deterministic **natural
   path order** (numeric-aware: `2 < 10 < 100`, so numbered files sort
   correctly past track 99 regardless of zero-padding) in both full scans
   and watcher (incremental) updates.

   *Suspicious-album-tag guard:* downloaders often write the source
   playlist's name into every track's album tag (each track keeping its
   own album artist). Grouping on that tag would shatter the folder into
   fake per-artist "albums" all sharing one name. Inside a playlist
   folder, a track's album tag is treated as an artifact — kept out of
   album grouping, track stays standalone and in the playlist — when
   either:
   - the album tag equals the playlist's display name
     (case-insensitive), or
   - the album tag *contains* the playlist's display name after
     normalizing both to letters/digits (catches prefixed artifacts like
     `album="AIENP's Elvis' Playlist"` in `[PLAYLIST] Elvis Playlist`);
     only applied when the normalized playlist name is 8+ characters so
     short names like "Elvis" can't swallow real albums, or
   - the same album tag is shared by tracks from **3 or more different
     album-grouping artists** within that folder (catches renamed
     folders, e.g. `[PLAYLIST] Sleep Time` full of
     `album="AIENP's sleep time"` files).

   Real albums have a single grouping artist and real compilations share
   one "Various Artists" album artist, so neither is affected. Genuine
   album tags (e.g. a properly tagged *Cruel Summer* track) still group
   normally, and albums that legitimately share a name with a playlist
   are unaffected when they live outside the playlist folder.
2. **M3U files** — every `.m3u` / `.m3u8` file found anywhere in the
   library:
   - `#`-prefixed lines (comments, `#EXTM3U`, `#EXTINF`) and blank lines
     are ignored.
   - Relative entries resolve against the M3U file's own directory;
     absolute paths and `file://` URIs are supported; `http(s)://` stream
     entries are skipped.
   - Only entries matching audio files the scanner actually indexed are
     included; missing entries surface in scan diagnostics.
   - File order is preserved (this is the one playlist type with an
     explicit ordering source). Repeated entries for the same song are
     deduplicated (first occurrence wins).
   - If a file inside the library was deduplicated, an M3U entry pointing
     at the duplicate copy resolves to the surviving song.
   - A malformed M3U never breaks the scan — it is reported in scan
     diagnostics and skipped.
   - The playlist ID hashes the M3U file path; the display name is the
     file name without extension.
   - **Limitation:** the folder watcher only tracks audio files, so edits
     to an M3U take effect on the next full scan (e.g. server restart or
     manual rescan). Incremental updates carry M3U playlists through
     unchanged, dropping entries whose songs were removed.

## Auto-imported (high confidence)

Without this tier, a fresh install looks like playlist detection failed:
normal folders full of mixed songs were only *suggested*, and users who
don't know about `[PLAYLIST]` saw no playlists at all. So unmarked folders
with **strong** playlist evidence import automatically, exactly like
`[PLAYLIST]` folders: recursive additive membership, natural path order,
dedupe handling, the artifact-tag guard, plain-basename display name, and
the stable `FolderPlaylist.generateId(folderPath)` ID.

A folder auto-imports only when **all** of these hold:

- it directly contains at least **8** loose audio files;
- it passes every album-protection guard below (so compilations, dominant
  albums, and artist dumps can never auto-import);
- tracks span **≥ 4 distinct albums** (no album above 40% of tagged
  tracks) **and ≥ 4 distinct artists** (no artist above 50%);
- **either** the folder name is playlist-like (see the word list below)
  **or** diversity is very high on its own: ≥ 6 distinct albums and ≥ 6
  distinct artists, with no album above 30% and no artist above 40% of
  tagged tracks.

So `Gym/` with 10 tracks from 5 albums auto-imports (name + diversity),
and an unnamed dump with 50 tracks from 25 albums / 30 artists
auto-imports (diversity alone) — but `Kanye West/808s and Heartbreak/`,
`Various Artists/Now Album/`, and single-artist album dumps never do.

If most tracks are missing album tags there is no diversity evidence, so
only a playlist-like name counts: 8+ untagged files in a playlist-named
folder still auto-import (those tracks would stay standalone anyway);
fewer fall back to a flagged suggestion.

Special cases:

- a user **ignore** decision on the folder blocks auto-import entirely;
- nested qualifying folders collapse into the outermost one (mirroring
  `[PLAYLIST]` nesting);
- a qualifying folder that *contains* an explicit playlist folder is
  demoted to a suggestion — importing it would make incremental rebuilds
  (which collapse nested playlist paths to the outermost) swallow the
  inner playlist;
- files already owned by an explicit playlist folder are never stolen.

Auto-imported folders are reported in scan diagnostics
(`autoImportedPlaylistFolders`, same shape as suggestions) and can be
removed with an **ignore** decision (`POST
/api/playlists/suggestions/decision`) followed by a rescan. Incremental
(watcher) rebuilds carry auto-imported playlists through from the previous
library snapshot; classification itself only runs on full scans.

## Suggested (advisory only)

`PlaylistFolderClassifier` looks at every folder that **directly** contains
at least 5 loose audio files. Folders that don't meet the auto-import bar
but still look playlist-shaped are reported in scan diagnostics
(`playlistSuggestions` on the scan-status endpoint) without being imported;
the dashboard offers *Import / Ignore* actions on top of this data (see
"Approval workflow" below).

A folder is **never** suggested when any of these hold (album protection):

- it is the library root, or it lives inside an explicit playlist folder;
- any track carries a "Various Artists"-style album-artist tag
  (compilations stay albums no matter how many track artists they have);
- the tracks span only 1–2 distinct album tags;
- one album tag covers ≥ 60% of the tagged tracks;
- one album artist covers ≥ 80% of the tagged tracks (artist dumps are not
  playlists);
- fewer than half the tracks have album tags *and* the folder name is not
  playlist-like (poorly tagged folders are left alone).

A folder **is** suggested when it survives the guards and shows at least
two signals, at least one of which is tag diversity:

- tracks come from ≥ 4 different albums with no album above 40% share;
- tracks come from ≥ 4 different artists with no artist above 50% share;
- track numbers are missing on half the tracks or contain duplicates
  (ripped-from-many-albums shape);
- the folder name contains a playlist word (`playlist`, `mix`, `mixtape`,
  `favourites`, `favorites`, `liked`, `road trip`, `roadtrip`, `gym`,
  `workout`, `running`, `party`, `setlist`, `car`) on a word boundary —
  "carnival" does not match "car".

A playlist-like name alone is never sufficient.

**Missing tags:** if most tracks lack album tags, the folder is surfaced
only when its name is playlist-like, and the suggestion carries
`missingTags: true` plus a "review before importing" reason.

Suggestions are path-sorted and capped at 25 per scan for deterministic,
bounded diagnostics.

## Approval workflow

Suggestions become playlists only through an explicit user decision. Three
decisions exist, keyed by the folder's **absolute path**:

- **import** — from then on the folder is treated exactly like a
  `[PLAYLIST]` folder on every scan: additive membership, natural path
  order, dedupe preference, and the playlist-name-as-album artifact guard
  all apply unchanged. The display name is the plain folder basename (no
  marker to strip, no rename needed) and the playlist ID uses the same
  `FolderPlaylist.generateId(folderPath)` scheme, so it is stable across
  scans and restarts. Approved folders are never suggested again.
- **ignore** — the folder is never suggested *and never auto-imported*
  again. No other effect.
- **reset** — clears a previous decision so the folder is re-evaluated on
  the next scan.

Decisions persist in `playlist_decisions.json` next to the metadata cache
(`PlaylistDecisionStore`, loaded before each full scan) and cross into the
scanner isolate as plain data. Incremental (watcher) rebuilds regrow
approved playlists from the previous library snapshot, so they survive file
changes without rescanning.

A decision is data about a *path*, not about the files inside it. If the
user renames a decided folder, the old decision goes stale (it simply never
matches again) and the renamed folder is evaluated fresh on the next scan;
renames are deliberately not tracked. Explicit sources (`[PLAYLIST]`
folders, `.m3u` files) are unaffected by decisions.

HTTP API (same authorization as the setup endpoints: open during first-run
setup, admin session once users exist):

- `GET /api/playlists/suggestions` — pending suggestions (decided folders
  are filtered out immediately, without waiting for a rescan) plus all
  recorded decisions.
- `POST /api/playlists/suggestions/decision` with
  `{folderPath, decision: "import" | "ignore" | "reset"}`. An import
  triggers a rescan so the playlist materializes without further action.

The CLI web dashboard renders a "Suggested playlists" card (name,
songs · artists · albums counts, a "tags missing" review badge, Import /
Ignore buttons) on the Overview tab. TV and mobile need nothing: imported
playlists arrive through the normal library API.

## Ignored

- Normal album folders (dominant album tag, sequential track numbers).
- Compilation folders (Various Artists).
- Folders with fewer than 5 loose files.
- Poorly tagged folders without a playlist-like name.
- Any folder already covered by an explicit playlist source.
- Any folder with a recorded **ignore** decision.

## Deliberately left for later passes

- **Desktop-embedded dashboard card** — the desktop premium app embeds its
  own native `DashboardScreen` (it does not render the CLI web assets), so
  it does not show the "Suggested playlists" card yet. The decisions API is
  shared, so the card is purely UI work.
- **`.ariami-playlist` marker files** — trivial to add next to the M3U
  branch once the format is decided.
- **Watcher-driven M3U re-parse** — requires widening the folder watcher
  beyond audio extensions.
- **Folder-path metadata fallback** (infer artist/album/track from
  `Artist/Album/01 Title.mp3` when tags are missing): recommended as its
  own pass. It must be gated on (a) the folder *not* being playlist-like or
  a suggestion, (b) a strict two-level `Artist/Album` shape with mostly
  numbered files, and (c) a scan diagnostic listing every inference so
  users can spot bad guesses. Doing it casually would mis-tag download
  dumps and Soulseek-style folders, which is worse than leaving files
  standalone.
