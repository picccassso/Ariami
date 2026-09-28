# Ownership, handoff and failover

Exactly one device makes sound. Everything in this file exists to keep that true
across takeovers, network drops, races and slow devices.

## The counters

| Counter | Minted by | Increments when |
|---|---|---|
| `ownerEpoch` | hub only | ownership changes |
| `queueCounter` | hub only | canonical queue fingerprint changes |
| `stateRevision` / `revision` | hub only | any accepted state change |
| `semanticGeneration` | either side | a *meaningful* change happens |

All start at `0`. The hub mints epochs, and a client must never invent one,
which is why the hub rejects a *future* epoch just as firmly as a stale one.

### semanticGeneration

The "did something meaningful happen" counter, used to cancel a handoff that a
concurrent user action superseded.

It advances on a change to `{queue, currentIndex, isPlaying, shuffle, repeatMode,
volume, castDeviceName}`, or on an **inferred seek**: compare the actual position
to `previous + elapsed` and treat a gap over **1500 ms** as a seek. While either
side is casting, the seek threshold widens to **10000 ms**. The hub also advances
it when ownership changes and when it accepts a command.

Ordinary progress leaves it alone. Get this wrong in the loose direction and
every handoff gets cancelled by the 1 Hz position tick.

Note this is the only counter both sides touch, so two devices can mint the same
number concurrently. The hub arbitrates; do not build logic on its global
uniqueness.

## Fencing rules

### Server side

| Incoming `ownerEpoch` | Result |
|---|---|
| Absent | Accepted, unfenced (legacy v2 compatibility) |
| Non-integral or negative | Rejected |
| ≠ current (older *or* newer) | Rejected |
| = current | Accepted |

The hub answers rejected state and queue publishes with the **authoritative
queue and state** instead of dropping them, so a confused device resyncs within
one publish cycle.

Fenced messages: `connect_state`, `connect_queue`, `connect_command`,
`connect_command_result`, `connect_transfer`, `connect_transfer_result`, and
pending-command delivery.

### Client side

Apply the same discipline to inbound messages:

| Incoming | Result |
|---|---|
| Missing epoch | Accept, no fencing (old hub) |
| Malformed epoch | Reject |
| Lower than local | Reject |
| Equal, but the owner changed and you already know an owner | **Reject**: an owner cannot change without advancing the epoch |
| Higher, and it moves ownership *away from you* | **Pause locally, await completion, then adopt** |
| Higher, otherwise | Accept |

That fifth row is the single most important rule in Connect.

## Losing ownership

When a message tells you someone else now owns the session:

1. Pause your local engine.
2. **Await the pause to completion.** If it fails, reject the message entirely
   rather than adopting a mirror while still audible.
3. Only then adopt the new epoch, owner and remote state.

Make it **idempotent per epoch**: track the last epoch you paused for and share
the in-flight future. A commit and a devices broadcast for the same epoch must
produce exactly one pause.

Only the previous owner pauses on an ownership change. A device that was merely
mirroring the session was never audible.

The hub also sends the losing device an explicit synthetic pause command:

```json
{"type":"connect_command","data":{
  "commandId":"owner-8-pause-desk-1","command":"pause","arguments":{},
  "requestedBy":"phone-1","activeDeviceId":"tv-1",
  "ownerEpoch":8,"semanticGeneration":42}}
```

It is redelivered on reconnect and retired only when you answer `ok:true` for the
matching epoch. If the epoch transition already paused you, don't pause twice.
Just answer.

## Takeover

Takeover is implicit and driven by the user starting music locally.

Publish with `activate: true` (`connect_queue` on v3, `connect_state` on v2).
Takeover publications **bypass the throttle and the queue-echo gate**: the hub
must confirm the new owner immediately, before stale remote state can flash back
over the user's own music.

The condition the first-party clients use:

```
activate = (playing && trackId != null && trackId != lastTrackId)
        || (playing && !wasPlaying && !isThisDeviceActive)
```

Starting music is a takeover. A track change *while paused*, such as queueing
into an empty queue, is not.

Three things around takeover that the first-party clients had to get right:

1. **Register your playback listener before any async startup await.** A user
   who presses play during startup must have that intent stashed and flushed
   once the client exists, or the welcome's stale remote snapshot wins.
2. **Cancellation must stick.** Play-then-pause during startup cancels the
   takeover, and a reconnect must not resurrect it. If the activation already
   crossed the wire, republish the current (paused) state in the newly confirmed
   epoch. Otherwise the hub retains your stale *playing* snapshot forever.
3. **Suppress the mirror immediately on local play**, ahead of hub confirmation,
   for a bounded window (5 s in the first-party clients). A mirror arriving
   inside that window is deferred by a timer, not dropped.

## Handoff

Handoff is explicit: the user picks a device from the picker. Three phases,
all reversible until commit.

```
controller           hub                    target                source
    │  transfer  ──►  │                       │                     │
    │                 │  prepare  ──────────► │                     │
    │                 │  ◄──── transfer_result│  (load + seek,      │
    │                 │                       │   do NOT play)      │
    │                 │  commit ─────────────►│ ──────────────────► │
    │                 │                       │  play               │  pause
```

### Request

```json
{"type":"connect_transfer","data":{"targetDeviceId":"tv-1","ownerEpoch":7}}
```

Rejected with `DEVICE_OFFLINE` if the target isn't online or can't play,
`STALE_OWNER_EPOCH` on epoch drift, `NO_SESSION` if there's nothing to transfer,
and `UNSUPPORTED_CAST_HANDOFF` when the session is casting and the target has not
negotiated `preserve_cast_handoff`.

Any pending transfers are cancelled first: expired ones as `timeout`, live ones
as `superseded`.

### prepare (target only)

```json
{"type":"connect_transfer","data":{
  "phase":"prepare","transferId":"17673228450000000-phone-1",
  "sourceDeviceId":"desk-1","targetDeviceId":"tv-1",
  "snapshot":{...},
  "queueCounter":3,"ownerEpoch":7,"semanticGeneration":41}}
```

As the target:

1. Snapshot your current local state so you can restore it.
2. Suppress your own publication while applying.
3. **Apply with `isPlaying: false`.** Load and seek without starting, because a
   failed load must not silence the still-playing source.
4. Answer, echoing the hub's counters:

```json
{"type":"connect_transfer_result","data":{
  "transferId":"...","ok":true,
  "ownerEpoch":7,"queueCounter":3,"semanticGeneration":41}}
```

A v3 target **must** echo `queueCounter` and `semanticGeneration` exactly. The
hub compares them to detect a change that superseded the preparation. On error,
roll back and answer `ok:false` with a message.

### commit (broadcast to everyone)

```json
{"type":"connect_transfer","data":{
  "phase":"commit","transferId":"...",
  "sourceDeviceId":"desk-1","targetDeviceId":"tv-1",
  "snapshot":{...},"queueCounter":3,"stateRevision":13,
  "ownerEpoch":8,"semanticGeneration":42}}
```

Every device adopts it, so mirrors reflect the handoff without waiting for the
new owner's first publish. Make it idempotent by `transferId` (bounded LRU of
256), and reject a commit whose id isn't the transfer you prepared.

- **Target:** clear the prepared state, pre-seed your published-queue
  fingerprint from the committed snapshot so you don't immediately republish the
  whole queue, seek, then play or pause per `snapshot.isPlaying`, then publish.
  When the snapshot carries a `castDeviceName`, skip the seek and play/pause
  calls and join the receiver's existing media session instead.
- **Source:** pause, unless the epoch transition already paused you.

Do **not** await your engine's `play()` inside the commit handler. Engines like
just_audio return a future that stays pending until playback *ends*; awaiting it
pins you in "applying remote state" and suppresses every subsequent publication
for the whole track.

### cancel (target only)

```json
{"type":"connect_transfer","data":{
  "phase":"cancel","transferId":"...",
  "sourceDeviceId":"desk-1","targetDeviceId":"tv-1",
  "reason":"timeout",
  "ownerEpoch":7,"queueCounter":3,"semanticGeneration":41}}
```

Reasons: `timeout`, `superseded`, `stale_owner`, `state_changed`, `rejected`,
`disconnect`, `owner_reclaimed`.

Restore the state you held before preparation, **exactly**: track, position,
playing state. Await any in-flight prepare first. Restoration is also triggered
by a disconnect or dispose during preparation, so route all three through the
same path.

### Position compensation

Handoff snapshots are re-anchored to *now* at each stage, so a multi-stage
handoff doesn't compound transport delay into a drifting seek bar. Compensate
once per stage, not cumulatively.

### What cancels a preparation

A concurrent pause, seek, track change, queue edit, shuffle, repeat, volume or
cast handoff change, or an ownership change. Concretely: any move in
`ownerEpoch`, `queueCounter`, or `semanticGeneration` between prepare and
result.

Timeout is 30 seconds.

## Automatic failover

When the owner's socket goes, the hub fails over **immediately**, with no grace
period.

1. As soon as the socket loss is confirmed, connected playback candidates are
   tried in a deterministic order.
2. Ranking: devices that sent a command or requested a handoff within the last
   **120 seconds**, most recent first; then the previous playback device; then
   the most recently connected eligible client; then device id ascending.
3. The replacement inherits playing state, queue, track and position, through
   the same prepare/commit flow. A failed preparation advances to the next
   candidate.
4. If every candidate fails or none exist, the session settles **paused** and
   ownerless.

If the original owner reconnects before failover completes, pending automatic
transfers are cancelled with `owner_reclaimed` and it keeps ownership at the
same epoch.

### Why immediate failover shapes everything else

Because there is no grace period, the hub cannot distinguish a dead owner from
one that deliberately closed its socket. Two client-side rules follow directly:

- **An audible owner must never reconnect voluntarily.** Reopening the socket to
  resynchronise hands the session away and earns you a former-owner pause. Wait
  for the ping and liveness timeouts instead. A mirroring client may reconnect
  freely.
- **An intentional exit must not publish its local pause.** Freeze publication,
  stop the engine, then close the socket. The retained *playing* snapshot is the
  continuation intent the hub hands to the replacement device.

A former owner that reconnects after failover completed stays epoch-fenced and
paused. It cannot resume duplicate playback.
