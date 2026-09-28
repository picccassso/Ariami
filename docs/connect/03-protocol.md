# Protocol reference

## Envelope

Every frame is JSON text:

```json
{"type":"connect_state","data":{...},"timestamp":"2026-01-02T03:04:05.000Z"}
```

`timestamp` must be a string on every frame. The server answers a frame where
it is missing or non-string with `INVALID_MESSAGE`, though no Connect logic
reads its value; treat it as opaque local time. All meaningful ordering comes
from the revision and epoch counters.

Raw frames are capped at **8 MiB**, checked on the encoded byte length *before*
JSON decoding. An oversize frame gets a `connect_error` with code
`MESSAGE_TOO_LARGE`; the socket stays open.

Every `connect_*` payload is additionally shape-checked: max nesting depth 7,
max 32 map keys, key length ≤ 64, string length ≤ 2048, list length ≤ 5000.
Violations return `INVALID_PAYLOAD`.

## Message catalogue

**Client → server**

| Type | Purpose |
|---|---|
| `connect_hello` | Capability and version offer |
| `connect_queue` | Publish the queue (v3 only) |
| `connect_state` | Publish playback state |
| `connect_command` | Control the active device |
| `connect_command_result` | Answer a routed command |
| `connect_transfer` | Request a handoff |
| `connect_transfer_result` | Answer a handoff `prepare` |
| `connect_rename` | Rename this device |

**Server → client**

| Type | Purpose |
|---|---|
| `connect_welcome` | Negotiated version, device list, session baseline |
| `connect_devices` | Device list / ownership broadcast |
| `connect_queue` | Canonical queue + counter (v3 only) |
| `connect_state` | Authoritative playback state |
| `connect_command` | Relayed command for this device |
| `connect_command_result` | Result for a command you sent |
| `connect_transfer` | Handoff `prepare` / `commit` / `cancel` |
| `connect_error` | Protocol-level error |

---

## connect_hello

```json
{"type":"connect_hello","data":{
  "protocolVersions":[3,2],
  "canPlay":true,
  "supportedCommands":["pause","play","seek","toggle"],
  "features":["preserve_cast_handoff"]}}
```

| Field | Type | Default | Notes |
|---|---|---|---|
| `protocolVersions` | `List<num>` | (none) | Preference order. v3 is selected only if the server has v3 enabled **and** the list contains a numeric `3` |
| `canPlay` | `bool` | `true` | `false` = pure controller; excluded from device lists and device broadcasts |
| `supportedCommands` | `List<String>` | see below | Intersected with the protocol allowlist; unknown strings dropped |
| `features` | `List<String>` | `[]` | Capability features, intersected with the hub's allowlist and echoed in the welcome |

**The `supportedCommands` inversion is load-bearing:**

| Sent | Means |
|---|---|
| Key absent | Supports **everything** (legacy peers are grandfathered) |
| `[]` | Supports **nothing** |
| `["play","pause"]` | Supports exactly those |

Getting this backwards either mutes your client or makes it silently swallow
commands it advertised.

`protocolVersions` fails the other way: a missing key, a non-list, or a list
with no numeric `3` silently selects v2. There is no error.

You may re-send `connect_hello` on a live socket. It renegotiates version and
capabilities, re-sends the welcome and re-broadcasts devices.

---

## connect_welcome

**v3:**
```json
{"type":"connect_welcome","data":{
  "protocolVersion":3,
  "supportedCommands":["pause","play","seek","toggle"],
  "features":["preserve_cast_handoff"],
  "devices":[{"id":"desk-1","name":"Studio Mac","type":"desktop","canPlay":true,
              "connectedAt":"2026-01-02T03:04:00.000Z","isActive":true,
              "supportedCommands":[...],"features":[...]}],
  "activeDeviceId":"desk-1",
  "queueCounter":3,
  "stateRevision":12,
  "ownerEpoch":7,
  "semanticGeneration":41}}
```

**v2** replaces `queueCounter` + `stateRevision` with `revision`, and carries the
full playback snapshot inline as `snapshot` (omitted when the session has none).

`supportedCommands` and `features` here are **your own** advertised sets, sorted
and filtered to what the hub recognised. It is the server telling you what it
recorded, not what the owner can do.

`activeDeviceId` may be JSON `null`. All counters default to `0` when there is
no session.

---

## connect_devices

```json
{"type":"connect_devices","data":{
  "devices":[{"id":"desk-1","name":"Studio Mac","type":"desktop","canPlay":true,
              "connectedAt":"2026-01-02T03:04:00.000Z","isActive":true,
              "supportedCommands":[...],"features":[...]}],
  "activeDeviceId":"desk-1",
  "ownerEpoch":7,
  "semanticGeneration":41}}
```

Only `canPlay` peers are listed, and only `canPlay` peers receive the broadcast.
Each device entry also carries `features`, that peer's negotiated capability
set. Sorted by display name, then stable device id; the id tie-breaker keeps two
devices with the same visible name in a deterministic order.

Parse defaults when a field is missing: `id` `''`, `name` `'Unknown device'`,
`type` `'unknown'`, `canPlay` `false`, `isActive` `false`, `supportedCommands`
the full set, `features` empty.

> **UI note:** re-sort this list yourself for display: this device first, then
> the playing device, then alphabetical. The hub's ordering is deterministic but
> name-based, so without a local sort your own row can sit anywhere in the list;
> on TV that also decides which row autofocuses under the user's thumb.

---

## connect_state

### v2, client → server

```json
{"type":"connect_state","data":{
  "activate":false,
  "snapshot":{"queue":[...],"currentIndex":1,"positionMs":45678,
              "durationMs":202000,"isPlaying":true,"shuffle":true,
              "repeatMode":"all","volume":0.75,
              "sourceId":"playlist:shared-fixture",
              "updatedAt":"2026-01-02T03:04:08.000Z"},
  "ownerEpoch":7,
  "semanticGeneration":41}}
```

The hub overwrites `updatedAt` with its own clock. Validation failure returns
`INVALID_STATE`.

### v3, client → server

```json
{"type":"connect_state","data":{
  "queueCounter":3,"currentIndex":1,"positionMs":45678,"durationMs":202000,
  "isPlaying":true,"shuffle":true,"repeatMode":"all","volume":0.75,
  "stateRevision":9,"ownerEpoch":7,"semanticGeneration":41}}
```

The v3 publish carries bare playback fields, with the queue sent separately and
takeover going through `connect_queue`. Your outbound `stateRevision` is
**ignored** by the hub, which uses its own counter; it exists on the wire but
carries no server meaning.

`queueCounter` **must** equal the hub's current counter. If it is absent,
non-integral, or stale, the hub rejects the publish and pushes the authoritative
queue and state back at you instead of dropping it silently, so you resync
within one cycle.

When both peers negotiated `preserve_cast_handoff`, the v3 publish may also
carry `castDeviceName`; a publish that includes it without the feature
negotiated is rejected with `INVALID_STATE`.

### Server → client

**v3:**
```json
{"type":"connect_state","data":{
  "activeDeviceId":"desk-1","ownerEpoch":7,"queueCounter":3,
  "semanticGeneration":41,"currentIndex":1,"positionMs":45678,
  "durationMs":202000,"isPlaying":true,"shuffle":true,"repeatMode":"all",
  "volume":0.75,"stateRevision":12,"updatedAt":"2026-01-02T03:04:08.000Z"}}
```

The hub adds `castDeviceName` when the recipient negotiated
`preserve_cast_handoff` and the session has one.

**v2** uses `revision` instead of `stateRevision` and wraps everything in
`snapshot` alongside the full `queue`.

State broadcasts go to **all** peers of the account regardless of `canPlay`,
normally excluding the publisher.

### Ordering

Reject any state whose revision is **less than** the last one you accepted.
Equal is accepted. Read `stateRevision` on v3 and `revision` on v2; a transfer
commit carries whichever one matches your negotiated version, so read the
same field there too.

---

## connect_queue (v3 only)

Sending this on a v2 connection returns `UNSUPPORTED_MESSAGE`.

### Client → server

```json
{"type":"connect_queue","data":{
  "activate":false,
  "tracks":[{"id":"track-a","title":"First Track","artist":"...","albumId":"..."}],
  "backingOrder":[2,0,1],
  "sourceId":"playlist:shared-fixture",
  "queueCounter":4,
  "ownerEpoch":7,
  "semanticGeneration":41}}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `tracks` | `List<Map>` | yes | ≤ 5000 entries |
| `backingOrder` | `List<int>` | no | Absent → identity order |
| `sourceId` | `String` | no | ≤ 512 chars, opaque |
| `activate` | `bool` | no | `true` = claim the session |
| `ownerEpoch` | `int` | no, but send it | Omitting means no fencing at all |
| `queueCounter` | `int` | no | **Advisory: the hub ignores it** and derives its own from the queue fingerprint |
| `semanticGeneration` | `int` | no | Adopted only if integral, ≥ 0, and greater than the hub's |

### Server → client

```json
{"type":"connect_queue","data":{
  "activeDeviceId":"desk-1","ownerEpoch":7,"queueCounter":3,
  "semanticGeneration":41,
  "tracks":[...],"backingOrder":[2,0,1],
  "sourceId":"playlist:shared-fixture"}}
```

`sourceId` is omitted entirely when null. Broadcast only to v3 peers.

### The publish handshake

This is the part implementers get wrong:

1. Queue changed → send `connect_queue`. **Return without sending state.**
2. Wait for the hub's `connect_queue` echo.
3. On the echo, adopt the hub's counter and *then* send the deferred
   `connect_state` carrying it.

And: **never resend a queue while awaiting its echo**, with one exception: a
takeover (`activate: true`) must resend, because the hub commits ownership from
the queue message itself.

### backingOrder

`backingOrder` is a complete permutation of **positions into `queue`**, listing
resolved positions in pre-shuffle order.

```
queue        = [Track C, Track A, Track B]   ← what plays, in order
backingOrder = [1, 2, 0]                     ← unshuffled: A, B, C
```

Validation is strict: a list of exactly `queue.length` integers, each in
`[0, length)`, no duplicates. Anything else is rejected. Absent → identity.

**It is positional, never id-keyed.** Queues legitimately contain the same track
id twice; an id-keyed unshuffle silently collapses the two occurrences into one.
This is exactly what the shared contract fixture exists to catch.

A queue that originated on v2 is forced to identity backing order, because its
pre-shuffle order cannot be inferred safely.

### Queue counter

The hub increments its counter whenever the canonical queue **fingerprint**
changes. The fingerprint is a JSON encoding of `{tracks, backingOrder, sourceId}`
with map keys sorted recursively, so a different key insertion order cannot
spuriously bump the counter. Reproduce that canonicalisation or your client will
churn the counter on every publish.

A counter regression is legal **across** an epoch change and illegal **within**
one.

---

## Snapshot shape

Allowed keys, exhaustively. Any other key is rejected.

| Key | Type | Range |
|---|---|---|
| `queue` | `List<Map>` | ≤ 5000 |
| `backingOrder` | `List<int>` | permutation of queue positions |
| `currentIndex` | `int` | `-1` … 4999 |
| `positionMs` | `int` | 0 … 86400000 |
| `durationMs` | `int` | 0 … 86400000 |
| `isPlaying` | `bool` | strict bool |
| `shuffle` | `bool` | strict bool |
| `repeatMode` | `String` | `off` \| `all` \| `one` |
| `volume` | `num` | 0.0 … 1.0, finite |
| `sourceId` | `String` | ≤ 512 |
| `castDeviceName` | `String` | ≤ 256, only with `preserve_cast_handoff` |
| `updatedAt` | `String` | parseable date, ≤ 64 chars |

Lenient parse defaults (for reading, not validating): empty queue, index `-1`,
positions `0`, `isPlaying`/`shuffle` `false`, `repeatMode` `off`, `volume` `1`.
Queue entries that aren't maps with a non-empty `id` are silently dropped;
tolerate a malformed item rather than blanking the whole session.

`backingOrder` appears in a snapshot only for v3 transfer payloads and
`play_context` echoes; ordinary v2 state omits it.

## Track shape

A queue track is a **flat** map with no nesting.

| Rule | Value |
|---|---|
| Max keys | 20 |
| Max key-name length | 40 |
| Value types | `String`, `num`, `bool`, `null` |
| Required | `id`, non-empty String |

String length caps: `id`, `albumId`, `modifiedTime` ≤ 64; `genre` ≤ 256;
`title`, `album`, `artist`, `albumArtist` ≤ 512; everything else ≤ 1024.

Fields in use: `id`, `title`, `artist`, `album`, `albumId`, `albumArtist`,
`trackNumber`, `discNumber`, `year`, `genre`, `duration` (seconds), `filePath`,
`fileSize`, `modifiedTime`.

`id` is the library song id: feed it to `POST /api/stream-ticket` and
`GET /api/stream/<songId>`. `albumId` feeds `GET /api/artwork/<albumId>`.

**Connect never carries stream URLs, tickets, passwords or session tokens.** A
device that receives a queue mints its own ticket before it can play anything.

---

## connect_rename

```json
{"type":"connect_rename","data":{"name":"Living Room TV"}}
```

Control characters become spaces, whitespace runs collapse, trimmed, capped at
40 characters. If nothing visible remains you get `INVALID_NAME`.

There is **no success ack**. Every peer sharing that `(userId, deviceId)` is
renamed and a `connect_devices` broadcast follows; that broadcast is your
confirmation.

---

## connect_error

```json
{"type":"connect_error","data":{"code":"STALE_OWNER_EPOCH","message":"..."}}
```

Default to `CONNECT_ERROR` / `Ariami Connect error` when a field is missing.
Full code table in [08-reference.md](08-reference.md).

---

## Version differences at a glance

| Aspect | v2 | v3 |
|---|---|---|
| Queue transport | inline in every state publish | separate message, only on change |
| `connect_queue` | rejected (`UNSUPPORTED_MESSAGE`) | supported both ways |
| Revision field | `revision` | `stateRevision` |
| Queue reference | none | `queueCounter`, must match exactly |
| `backingOrder` on the wire | never for ordinary state | in `connect_queue` and transfer snapshots |
| Welcome snapshot | inline | pushed as separate queue + state |
| Takeover | `connect_state` with `activate:true` | `connect_queue` with `activate:true` |
| Transfer commit | `revision` | `stateRevision` + `queueCounter` |
| Transfer result | may omit counters | **must** echo `queueCounter` and `semanticGeneration` |

v2 traffic never forces v3 peers back onto full snapshots. The hub renders each
broadcast per recipient.
