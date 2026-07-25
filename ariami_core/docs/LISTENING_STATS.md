# Listening stats and Spotify import

How Ariami decides that something counts as a play, how that differs from
Spotify's counting, and what actually happens when you import a Spotify
listening history.

Both the counting engine and the import pipeline live in `ariami_core`, so
they behave identically whether you run the desktop server GUI or the
headless CLI server. The import *button* lives in those apps; everything it
does is implemented here.

- [Part 1 — how Ariami counts](#part-1--how-ariami-counts)
- [Part 2 — how this differs from Spotify](#part-2--how-this-differs-from-spotify)
- [Part 3 — importing a Spotify history](#part-3--importing-a-spotify-history)
- [Part 4 — what to expect after an import](#part-4--what-to-expect-after-an-import)
- [Part 5 — undoing an import](#part-5--undoing-an-import)

---

## Part 1 — how Ariami counts

All live counting happens in
[`listening_event_tracker.dart`](../lib/services/stats/listening_event_tracker.dart).
The client audio engine feeds it track changes, play/pause flips and frequent
position ticks; it emits two *different kinds* of event.

### Two numbers, not one

Ariami tracks **plays** and **listened time** as separate quantities:

| Event kind | `plays` | `listenedMs` | Emitted when |
|---|---|---|---|
| Play event | `1` | `0` | The play threshold is crossed, once per play-action |
| Segment event | `0` | `> 0` | Genuine forward listening is committed |

This is why a track can show a large listening time and a small play count
(you left one song on in the background) or many plays and modest time (you
kept restarting it). They answer different questions and are never derived
from each other.

### When a play is counted

A play is credited once cumulative listening in the current play-action
reaches the threshold ([`listening_event_tracker.dart:127`](../lib/services/stats/listening_event_tracker.dart:127)):

```
threshold = min(30 seconds, track duration / 2)
```

- Tracks **60 seconds or longer** → the familiar 30-second rule.
- Tracks **shorter than 60 seconds** → half the track. A 40-second interlude
  counts at 20 seconds, so short tracks aren't unfairly hard to credit.
- Tracks **shorter than 30 seconds** that play to natural completion count as
  one play even if the threshold was never observed — sparse position ticks
  or an unknown duration would otherwise lose them entirely
  ([`onTrackCompleted`, line 224](../lib/services/stats/listening_event_tracker.dart:224)).

### What is never credited

The tracker is deliberately conservative about time
([`onPositionTick`, line 163](../lib/services/stats/listening_event_tracker.dart:163)):

- **Forward scrubbing.** A position jump larger than `seekToleranceMs`
  (2,000 ms) is treated as a seek, not listening. The audio you skipped over
  is not credited; listening resumes normally after the jump.
- **Backward movement.** Never credited under any circumstance.
- **Time past the end of the track.** A tick reporting a position beyond the
  known duration is clamped so a single tick can't over-credit.
- **Audio while paused.** Pausing commits what's accumulated and drops the
  position anchor, so a seek performed while paused can't be credited on
  resume.
- **Noise.** Uncommitted stretches under `minSegmentMs` (1,000 ms) are never
  emitted as segments.

### Repeat-one

A backward jump landing within `restartPositionMs` (5,000 ms) of the start is
read as the track restarting rather than as a scrub. The current play-action
is finalized and a new one opens, so **each full listen counts as its own
play while every second of audio is still credited exactly once**
(lines [174–185](../lib/services/stats/listening_event_tracker.dart:174)).

### Crash safety

Uncommitted listening is checkpointed into a segment event every
`checkpointMs` (default 30,000 ms), so an app that is killed loses at most
about 30 seconds of credit rather than the whole session.

---

## Part 2 — how this differs from Spotify

Ariami's live threshold is deliberately modelled on Spotify's 30-second
stream definition — the parser even documents them as the same rule
([`spotify_history_parser.dart:104`](../lib/services/stats/spotify_import/spotify_history_parser.dart:104)).
The differences are in everything around that number.

| | Spotify | Ariami (live tracking) |
|---|---|---|
| Play threshold | 30 seconds | 30 seconds, or half the track under 60s |
| Very short tracks | 30s rule only | Full listen counts on completion |
| Scrubbed-over audio | Included in `ms_played` | Not credited |
| Backward seeks | — | Never credited |
| Time vs. plays | One record per stream | Two independent quantities |
| Repeat-one | Each stream separate | Each wrap is a new play, time counted once |

The practical consequence: **Ariami's listened-time is a stricter number than
Spotify's.** Spotify's `ms_played` is wall-clock time the stream was open;
Ariami's listened time is audio you actually heard moving forward. For
normal listening they're nearly identical. For a session where you scrubbed
around a lot, Ariami's figure will be lower — and that's the intended
behaviour, not a bug.

---

## Part 3 — importing a Spotify history

### What you need

Request **Extended Streaming History** from Spotify's privacy page (not the
smaller "Account data" export — that one doesn't contain per-play records).
Spotify delivers it as a zip archive, and the request can take a while to
fulfil.

Unzip it and point the importer at the folder containing the
`Streaming_History_Audio_*.json` files. Only files matching that prefix and
the `.json` extension are read
([`spotify_import_service.dart:257`](../../ariami_desktop/lib/services/spotify_import_service.dart:257)),
so the `*_Video_*` files in the same export are ignored automatically, as is
everything else in the folder.

Your Ariami library must be scanned first — importing into an empty library
is refused, because there would be nothing to match against.

### Which plays are eligible

Every record in the export is tested against the rule in
[`spotify_history_parser.dart:150`](../lib/services/stats/spotify_import/spotify_history_parser.dart:150):

```
ms_played >= 30000  OR  (reason_end == 'trackdone' AND ms_played > 0)
```

So a play qualifies if it ran at least 30 seconds, **or** it played to its
natural end (which is how tracks shorter than 30 seconds survive).

Records dropped before that test even runs:

| Dropped | Why |
|---|---|
| Podcasts | `spotify_episode_uri` is set |
| Audiobooks | any `audiobook_*` field is set |
| No track identity | missing `spotify_track_uri` or track name |
| Unparseable timestamp | `ts` isn't a readable date |
| Private-session plays | `incognito_mode` is true |

Incognito plays are excluded by default. The parser accepts an
`importIncognito` flag, but neither the desktop nor the CLI web UI exposes a
toggle for it, so in practice private sessions are always skipped.

### Two data-quality fixes applied on the way in

These matter because they're the difference between plausible stats and
visibly broken ones:

**Offline plays get their real time back.** For records with `offline: true`,
Spotify's `ts` field is the *sync* time, not the play time — up to 185
records can share a single second, which would otherwise show up as an
impossible burst in your daily rollups. The parser uses `offline_timestamp`
instead ([lines 155–176](../lib/services/stats/spotify_import/spotify_history_parser.dart:155)).

**Timestamp units get normalized.** `offline_timestamp` is a Unix epoch whose
*unit is inconsistent across exports* — seconds in some records,
milliseconds in others. A seconds value taken at face value lands in January
1970 and poisons first-play and day-span statistics. Values below `1e12` are
scaled up ([`_normalizeEpochMs`, line 239](../lib/services/stats/spotify_import/spotify_history_parser.dart:239));
the boundary is safe because real second-scale values sit near 1.8e9 and
millisecond-scale near 1.8e12, with nothing in between.

### How tracks are matched to your library

[`library_track_matcher.dart`](../lib/services/stats/spotify_import/library_track_matcher.dart)
resolves each unique `(title, album artist, album)` key through a four-tier
cascade, stopping at the first hit:

1. **Exact** — normalized title + artist agree. Confidence 1.0 for a verbatim
   title on both sides, 0.9 when a suffix like `(feat. …)`, `(Live)` or
   `- 2012 Remaster` had to be stripped to make them meet.
2. **Album-anchored** — the artist string drifted but title + album agree.
   Confidence 0.9.
3. **Fuzzy** — a restricted search seeded from the rarest title token
   (never a full-library scan), scored on token overlap plus edit distance,
   and *gated on artist agreement*. Capped at 0.85 confidence.
4. **Unmatched** — nothing plausible found.

The matcher handles a lot of real-world messiness: featured-artist credits in
either the title or the artist field, `Various Artists` treated as carrying no
artist signal, Cyrillic transliteration, multi-script titles like
`오아시스 (Oasis)`, and conflicting version numbers being rejected rather than
fuzzy-matched together.

**Matched plays adopt your library's strings, never Spotify's**
([`_libraryMatch`, line 618](../lib/services/stats/spotify_import/library_track_matcher.dart:618)).
This is the detail that makes the whole feature work: if Spotify says
`Beyoncé` and your files say `Beyonce`, the imported plays are filed under
your spelling and merge cleanly with plays tracked live. Import Spotify's
strings instead and every artist total would silently split in two.

For the same reason, imported events deliberately carry **no album artist**
([`spotify_event_builder.dart:47`](../lib/services/stats/spotify_import/spotify_event_builder.dart:47)) —
importing Spotify's would fragment artist rollups.

When several library copies share a key (the studio album, a deluxe edition
and a compilation folder), the matcher prefers the copy whose album best
agrees with Spotify's, returns it as a confident match, and keeps the others
as alternates. Only genuinely *different* songs sharing a title — a solo
version versus a `feat.` version — are marked ambiguous.

### Unmatched plays still count

A track you don't own gets a stable synthetic id, `spotify-uri:<track id>`,
and is imported with Spotify's own metadata
([`syntheticSongIdFor`, line 75](../lib/services/stats/spotify_import/spotify_event_builder.dart:75)).
It counts in your totals and history; it simply isn't playable and has no
artwork. Your listening past stays intact even for music that isn't in your
library.

---

## Part 4 — what to expect after an import

### The preview, before anything is written

The desktop dialog shows the account, the eligible play count, how many
library tracks matched, and how many tracks weren't found
([`spotify_import_dialog.dart:157`](../../ariami_desktop/lib/widgets/spotify_import_dialog.dart:157)).
Nothing is uploaded until you confirm. After uploading it reports new plays
added, existing plays skipped, and any rejected as invalid.

### Imported plays are shaped differently from live ones

An imported play is a **single combined event** carrying both `plays = 1` and
`listenedMs = ms_played`, with no `playId`
([`spotify_event_builder.dart:29`](../lib/services/stats/spotify_import/spotify_event_builder.dart:29)).
Live listening, by contrast, arrives as one play event plus a stream of
segment events.

The important consequence: **imported listening time is Spotify's number, so
it carries Spotify's counting semantics with it.** Time you scrubbed past in
2019 is inside `ms_played` and there is no way to recover the distinction
after the fact. Your imported history is therefore very slightly more
generous than your live-tracked history. Both are internally consistent; the
two eras just measure with marginally different rulers.

Every imported event is tagged `sourceKind = 'import'`, so imported and live
plays remain distinguishable in the raw event log.

### Re-importing is safe

Each event's id is deterministic — `spotify:<userId>:sha256("v1|" +
rawIdentity)`, where the identity hashes the whole source record (`ts`,
track uri, `ms_played`, `reason_end`, `offline_timestamp`, `platform`). The
server dedupes on insert, so:

- Importing the same export twice adds nothing the second time.
- Overlapping exports (a fresh request that re-covers old ground) merge
  cleanly.
- Byte-identical duplicate rows *within* an export collapse into one.
- Genuinely distinct offline replays that share a sync timestamp stay
  separate, because `offline_timestamp` and `ms_played` differ.

Duplicates are reported as "existing plays skipped" rather than treated as
errors.

### Scale and stats are per-account

Imports upload in batches of 500 events
([`uploadBatchSize`](../../ariami_desktop/lib/services/spotify_import_service.dart:64)),
and matching collapses the play list to unique keys first — roughly 7,000
keys for 200,000 plays — so each track is resolved once. A large history
imports in one pass without special handling.

Listening stats are per-user throughout. An import is attributed to the
account performing it, and the desktop service re-checks that the signed-in
account hasn't changed between preview and upload.

---

## Part 5 — undoing an import

Imported plays can be removed on their own, leaving live-tracked history
untouched. `POST /api/v2/listening/reset` with a JSON body:

```json
{"source": "spotify"}
```

This deletes exactly the events whose id begins with `spotify:` and rebuilds
all rollups from the surviving raw log, returning how many were removed
([`listening_stats_handlers_part.dart:458`](../lib/services/server/http_server_parts/listening_stats_handlers_part.dart:458)).
The same endpoint with an **empty body** wipes that account's listening data
entirely. The only accepted `source` value is `spotify`.

The request is session-authenticated and acts on the calling account only.
Both dashboards drive it: **Remove Spotify listening stats** in the Desktop
overview tab's Listening Statistics section, and **REMOVE SPOTIFY STATS** in
the CLI web dashboard's Listening Statistics section. Each confirms first
and then reports how many plays were removed.

### Knowing what is imported

`GET /api/v2/listening/import-status` describes the calling account's
import — `plays`, `lastImportedAtMs` (the newest `received_at`, i.e. when
plays last landed) and `oldestPlayAtMs`/`newestPlayAtMs` (the span of
history covered). Everything is derived from the surviving events, so a
removal leaves it reporting nothing rather than a stale record of a past
import. It is a separate endpoint rather than more fields on the summary
because every client polls the summary and only the dashboards need this.

Both dashboards show it above the two buttons and disable removal when
there is nothing to remove; while the status is unknown removal stays
available, so a failed read never strands the action. The Desktop app hosts
the server in-process and reads the same query through
[`AriamiHttpServer.getSpotifyImportStatus`](../lib/services/server/http_server.dart)
instead of the endpoint — a passive status line must never prompt for the
owner password.

---

## Where this lives

| Concern | File |
|---|---|
| Live play/time counting | [`stats/listening_event_tracker.dart`](../lib/services/stats/listening_event_tracker.dart) |
| Export parsing and eligibility | [`stats/spotify_import/spotify_history_parser.dart`](../lib/services/stats/spotify_import/spotify_history_parser.dart) |
| Library matching | [`stats/spotify_import/library_track_matcher.dart`](../lib/services/stats/spotify_import/library_track_matcher.dart) |
| Event construction and idempotency | [`stats/spotify_import/spotify_event_builder.dart`](../lib/services/stats/spotify_import/spotify_event_builder.dart) |
| Pipeline facade | [`stats/spotify_import/spotify_importer.dart`](../lib/services/stats/spotify_import/spotify_importer.dart) |
| Storage, rollups, resets | [`stats/listening_stats_store.dart`](../lib/services/stats/listening_stats_store.dart) |
| HTTP endpoints | [`listening_stats_handlers_part.dart`](../lib/services/server/http_server_parts/listening_stats_handlers_part.dart) |
| Desktop import UI | [`ariami_desktop/lib/services/spotify_import_service.dart`](../../ariami_desktop/lib/services/spotify_import_service.dart) |
| CLI web import UI | [`ariami_cli/lib/web/services/spotify_import_service.dart`](../../ariami_cli/lib/web/services/spotify_import_service.dart) |

Storage schema and rollup tables are covered in
[DATA_AND_PERSISTENCE.md](DATA_AND_PERSISTENCE.md); the full endpoint list is
in [API_REFERENCE.md](API_REFERENCE.md).
