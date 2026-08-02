# Writing a third-party client

Connect has no SDK and no stability guarantee, but the protocol is plain JSON
over a WebSocket and is implementable in any language — the two contract
fixtures in `ariami_core/test/fixtures/connect/` are all you need to verify a
client against.

Decide first what you are building. It changes how much of this you need.

| Kind | `canPlay` | Publishes state | Handles commands | Effort |
|---|---|---|---|---|
| **Controller** — a remote, a Stream Deck, a web dashboard | `false` | no | no | low |
| **Player** — a speaker, a car head unit, a second app | `true` | yes | yes | high |

A controller is a weekend. A player is not — it has to be correct about
ownership, or it makes sound at the wrong time.

---

## Build a controller

### 1. Log in

```
POST /api/auth/login
{"username":"alex","password":"...","deviceId":"<your uuid>","deviceName":"Deck"}
```

Keep `sessionToken`. Persist `deviceId` — reuse it every launch.

### 2. Connect and identify

```
ws://<host>:8080/api/ws
```

```json
{"type":"connect_hello","data":{"protocolVersions":[3,2],"canPlay":false,
                                "supportedCommands":[]}}
{"type":"identify","data":{"deviceId":"<uuid>","deviceName":"Deck",
                           "sessionToken":"<token>","clientType":"desktop"}}
```

`clientType` must still be one of `desktop` / `mobile` / `tv` even for a pure
controller — the hub only registers those three. `canPlay: false` is what keeps
you out of the device picker.

### 3. Ping every 20 seconds

```json
{"type":"ping"}
```

### 4. Track the session

Keep `activeDeviceId`, `ownerEpoch`, the last revision you accepted, and (on v3)
the cached queue plus its counter. Update them from `connect_welcome`,
`connect_devices`, `connect_queue`, `connect_state` and transfer commits.

Reject anything with a stale revision or a stale epoch.

### 5. Send commands

```json
{"type":"connect_command","data":{
  "commandId":"<fresh uuid4>","command":"toggle","arguments":{},"ownerEpoch":7}}
```

Handle the result. Retry with `{commandId, retry:true}` after 4 s, up to 4
attempts total. That is the whole controller.

### 6. Render position

Do not display `positionMs` directly. Extrapolate:

```
displayed = snapshot.positionMs + (isPlaying ? now - localReceiptTime : 0)
clamped to durationMs
```

`localReceiptTime` is when *you* received the snapshot, on *your* clock. Never
use the snapshot's `updatedAt` — that is the sender's clock and skew will bend
your seek bar.

---

## Build a player

Everything above, plus the hard parts. Work through them in this order.

### 1. Publish state

Only when you are the owner. Never while applying inbound remote state — that
feedback loop is instant and ugly.

Two rates, and mixing them up is the classic mistake:

- **Discrete changes publish immediately.** Compute a fingerprint over
  `{queue, currentIndex, durationMs, isPlaying, shuffle, repeatMode, volume}` —
  note it excludes `positionMs`. Any change publishes now, cancelling any
  pending progress timer.
- **Pure progress coalesces to 1 Hz.** If a second has elapsed since your last
  publish, publish now. Otherwise arm a single timer for the remainder and drop
  every intervening call. Re-read your snapshot when that timer *fires*, not when
  you armed it, so you publish a fresh position.
- **Takeovers (`activate: true`) bypass both.**

### 2. Do the v3 queue handshake

1. Queue fingerprint changed → send `connect_queue`, **return without state**.
2. Wait for the hub's echo.
3. Adopt the hub's `queueCounter`, then send the deferred `connect_state`.

Never resend a queue while awaiting its echo — except a takeover, which must
resend, because the hub commits ownership from the queue message.

Canonicalise your fingerprint with recursively sorted map keys, or a different
key insertion order will look like a queue change and churn the counter.

### 3. Maintain semanticGeneration

Increment on a change to `{queue, currentIndex, isPlaying, shuffle, repeatMode,
volume}`, or on a position gap over 1500 ms versus `previous + elapsed`. Not on
ordinary progress.

After executing a routed command that carried a `semanticGeneration`, re-anchor
your baseline to the post-command snapshot, so the hub-reserved generation isn't
counted twice.

### 4. Implement epoch fencing, including the pause

See [05-ownership.md](05-ownership.md). The short version: on an epoch that
moves ownership away from you, **await a local pause to completion before
adopting the mirror**, idempotent per epoch, and abort the message if the pause
fails.

### 5. Handle routed commands

Execute against the local engine, cache the result by `commandId` (LRU 256) and
replay the cache on a redelivery. Never let a routed command re-enter your
"send a remote command" path.

Answer the synthetic former-owner pause (`commandId` looks like
`owner-<epoch>-pause-<deviceId>`) or it gets redelivered forever.

### 6. Handle transfers

Prepare loads and seeks *without playing*. Snapshot your prior state and restore
it exactly on cancel, disconnect or dispose. Commit is idempotent by
`transferId`. Don't await your engine's `play()`.

### 7. Fetch audio

Connect gives you song ids, not URLs. For each track:

```
POST /api/stream-ticket
{"songId":"<id>","quality":"high"}
→ {"streamToken":"<64 hex>","expiresAt":"..."}

GET /api/stream/<songId>?streamToken=<token>[&quality=medium|low]
```

- The ticket TTL is `max(duration + 10min, 20min)` capped at 2 hours — so a
  normal track gets **20 minutes**, not 2 hours. (The flat 2 h is the *download*
  ticket.)
- A ticket is bound to one `songId` at one quality, and to the issuing session.
  A ticket the previous owner used is worthless to you.
- `410 SONG_NOT_FOUND` means the library no longer has it. Skip the track, don't
  stall.
- Range requests are supported for seeking. `high` returns the original file;
  `medium` / `low` return transcoded AAC at 128 / 64 kbps.
- Artwork: `GET /api/artwork/<albumId>?size=thumbnail|full`. Accepts a bearer
  session *or* a matching `streamToken` — but a ticket for song X cannot fetch
  album Y's art.

### 8. Resolve a play_context

`play_context` hands you a complete snapshot, so the queue is already resolved —
you mostly just need per-track streaming. If you need to expand a playlist or
browse a library yourself, the v2 API is the one to use:

```
GET /api/v2/bootstrap?limit=100&cursor=<opaque>
GET /api/v2/changes?since=<syncToken>&limit=200
```

Bootstrap returns albums, songs and playlists (playlists carry `songIds`), plus
a `syncToken` for incremental sync. `GET /api/albums` and `GET /api/songs` are
empty v1 stubs — don't use them. `GET /api/albums/<albumId>` is real.

The v2 API is gated behind a server setting that defaults to **off**. Handle its
absence.

> **v2 bootstrap trap:** resume from the **minimum** `syncToken` across all
> bootstrap pages, not the last page's. Using the last page's silently strands
> rows.

---

## Test against the fixtures

Two files pin the contract. All four first-party clients decode them with their
own real decoders, which is the point — re-indexing the fixture's own arrays
would pass even for a client that ignores `backingOrder` entirely.

**`ariami_core/test/fixtures/connect/v2_contract.json`** pins:

- `protocolVersion: 2`, and `ownerEpoch: 7` with a `staleOwnerEpoch: 6`.
- A snapshot containing **the same track id at two positions with different
  titles**. Decode it, republish, and assert the two occurrences are still
  distinct. This is the single most valuable test in the set — every client that
  keys songs by id collapses duplicates somewhere, and the Connect boundary is
  where it shows.
- A `play_context` envelope with `backingOrder: [2, 0, 1]`. Adopt it, publish,
  assert the wire carries the **resolved play order** while `backingOrder`
  survives a second handoff. Then turn shuffle off and assert the order is what
  `backingOrder` said, duplicates intact.
- Reliable-command limits: 8388608-byte raw cap, 64 pending, 256 completed,
  4 attempts, the exact `{commandId, retry}` envelope keys, and the explicit
  failure codes.
- Per-client capability baselines — `set_volume` is present only for desktop.

**`ariami_core/test/fixtures/connect/fault_matrix.json`** enumerates every
failure mode with the correct behaviour: half-open sockets, bounded waits, stale
socket callbacks, 4001 and 4000-replaced suppression, backoff reset conditions,
epoch fencing, split-queue handshake, retry envelopes, transfer cancel paths.
Work through it — it is a test plan written for you.

---

## Checklist before you ship

- [ ] `connect_hello` before `identify`, every reconnect
- [ ] `clientType` is `desktop`, `mobile` or `tv`
- [ ] `deviceId` is stable across launches
- [ ] Ping every 20 s; watchdog replaces the socket after 60 s of silence
- [ ] Backoff `1,2,4,8,16,30`; reset only after 60 s of *received traffic*
- [ ] Reconnect suppressed on 4001 and on 4000-with-"replaced"
- [ ] Revision/epoch/queue-counter all reset on disconnect
- [ ] `ownerEpoch` echoed on every outbound state, queue, command and transfer
- [ ] Equal epoch with a changed owner is rejected
- [ ] Losing ownership awaits a local pause before adopting the mirror
- [ ] Fresh UUID4 `commandId`s; small retry envelope; no retry against a v1 hub
- [ ] Routed commands cached by id and never re-routed outward
- [ ] Position extrapolated from local receipt time
- [ ] Not audible-and-active when you voluntarily reconnect
- [ ] Intentional exit does not publish a paused snapshot
- [ ] Fresh stream ticket per device per track
- [ ] Both contract fixtures pass against your real decoder

Then read [07-gotchas.md](07-gotchas.md).
