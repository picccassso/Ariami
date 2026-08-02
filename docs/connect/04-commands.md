# Commands

A command is how any device controls whoever is currently playing. The hub
validates it, checks the target actually supports it, routes it to the active
device only, and relays the result back to whoever asked.

## Sending

```json
{"type":"connect_command","data":{
  "commandId":"550e8400-e29b-41d4-a716-446655440000",
  "command":"seek",
  "arguments":{"positionMs":45678},
  "ownerEpoch":7}}
```

`commandId` is required, non-empty, ≤ 128 characters. Mint a fresh UUID v4 from
a secure RNG per command.

## Receiving (you are the active device)

```json
{"type":"connect_command","data":{
  "commandId":"550e8400-...","command":"seek","arguments":{"positionMs":45678},
  "requestedBy":"phone-1","activeDeviceId":"desk-1",
  "ownerEpoch":7,"semanticGeneration":42}}
```

Run it against your **local** engine and answer:

```json
{"type":"connect_command_result","data":{
  "commandId":"550e8400-...","ok":true,"ownerEpoch":7,"activeDeviceId":"desk-1"}}
```

Failures add `"code"` and `"message"` (message truncated to 1024 chars).

A routed command must **never bounce back out** as a remote command. The hub only
sends you commands for your own playback — including the takeover pause sent to
a device that just lost the session. If your transport layer re-routes them
because a stale mirror hasn't been cleared yet, the command goes straight back to
the previous owner.

## The command set

| Command | Arguments | Bounds |
|---|---|---|
| `play` | `{}` | must be empty |
| `pause` | `{}` | |
| `toggle` | `{}` | |
| `next` | `{}` | |
| `previous` | `{}` | |
| `toggle_shuffle` | `{}` | |
| `cycle_repeat` | `{}` | |
| `clear_queue` | `{}` | |
| `seek` | `{"positionMs": int}` | 0 … 86400000 |
| `set_volume` | `{"volume": num}` | finite, 0.0 … 1.0 |
| `play_queue_index` | `{"index": int}` | 0 … 4999 |
| `remove_queue_index` | `{"index": int, "id": String}` | index 0 … 4999; `id` ≤ 64 chars |
| `insert_queue_track` | `{"index": int, "track": Map}` | index 0 … **5000** (append is legal) |
| `play_context` | `{"snapshot": Map}` | full snapshot |

Argument maps must contain **exactly** the listed keys. Extra or missing keys
are a validation failure, not a warning.

### What the interesting ones do

- **`play_context`** replaces the active device's queue with one chosen on a
  controller — an album, playlist or track — and starts it. This is how browsing
  on your phone plays on the TV.
- **`play_queue_index`** jumps the active device to an absolute index within the
  queue it last published.
- **`clear_queue`** removes every entry except the currently playing track,
  atomically. Use it instead of N sequential `remove_queue_index` calls — those
  race against the owner's own position ticks.
- **`set_volume`** is only advertised by desktop among the first-party clients.
  There is a `supportedWithoutVolume` set for engines with no programmatic
  volume control.

There is **no** takeover command and no handoff command. Takeover is publishing
with `activate: true`; handoff is the `connect_transfer` message. See
[05-ownership.md](05-ownership.md).

## Queue index space

`index` always means **a position in the resolved play order the active device
last published** — an index into `snapshot.queue`. Never an index into any
backing or unshuffled list.

`remove_queue_index` also carries `id`, the track id you saw at that index, as a
guard against acting on a stale snapshot. Targets fall back to the first
matching id and ignore unknown ids.

Out-of-range edits should be a silent no-op that sends nothing.

### If you keep a separate backing order

An engine that stores a backing queue plus a play order of indices into it has
to decide where an inserted track lands in *both*. Insert into the play order
only, and the track sits correctly in the current order — but appears at the
bottom the moment the user turns shuffle off, because it was appended to the end
of the backing queue.

Decide deliberately, and mirror it on removal: compact the backing queue when
you remove, or a later shuffle toggle resurrects the removed track.

Clients also differ on whether a controller may remove the *currently playing*
entry remotely. The protocol permits it. If your engine can't, fail the command
rather than silently ignoring it.

### Repeat-one

An explicit track change widens `repeat: one` back to `repeat: all` — repeat-one
belongs to the track you chose, not the one you just skipped to. Apply it on
both send and receive of `play_context`.

## Reliability

Commands are delivered at-least-once with idempotency on both ends. The contract:

| Guard | Value |
|---|---|
| Client ack timeout | 4 s |
| Client max attempts | 4 |
| Hub command timeout | 10 s |
| Hub max deliveries | 4 |
| Max pending per session | 64 |
| Retained completed results | 256 |

### Retry envelope

Attempt 1 sends the full payload. Attempts 2+ send **only**:

```json
{"type":"connect_command","data":{"commandId":"550e8400-...","retry":true}}
```

Nothing else. The hub has the payload retained and redelivers it.

If a retry comes back `ok:false` with `UNKNOWN_COMMAND` or `UNSUPPORTED_COMMAND`
after at least two attempts, resend the **full original payload under the same
commandId**, exactly once. That covers a hub that restarted, or a hub predating
payload retention. If it fails again, surface the error.

### Idempotency, as the executing device

Cache results by `commandId` in a bounded LRU (256) and **replay the cached
result without re-running the handler**. A redelivered `next` that executes twice
skips two tracks.

### Idempotency, as the sender

Reusing a `commandId` for different work returns `COMMAND_ID_COLLISION`. So does
another device using an id you already used. Mint fresh ids.

### Never retry against a hub that can't dedupe

If the negotiated hub protocol version is below 2, the hub cannot deduplicate.
**Drop the command** with `COMMAND_RETRY_UNSUPPORTED` rather than retrying —
replaying `next`, `toggle` or `cycle_repeat` twice is worse than failing once.

### Across a disconnect

Keep pending commands, cancel their retry timers, and re-dispatch them after the
next welcome. A command issued while disconnected should execute exactly once
when the connection comes back.

## Failure paths

| Situation | Result |
|---|---|
| Empty or > 128-char `commandId` | `INVALID_COMMAND_ID` |
| Epoch doesn't match | `STALE_OWNER` |
| Id reused by another device, or for different work | `COMMAND_ID_COLLISION` |
| `retry:true` for an id the hub no longer holds | `UNKNOWN_COMMAND` |
| Command not in the allowlist | `UNSUPPORTED_COMMAND` |
| Target device didn't advertise it | `UNSUPPORTED_COMMAND` |
| Bad arguments | `INVALID_ARGUMENTS` |
| Bad arguments on `play_context` | `PLAY_CONTEXT_TOO_LARGE` |
| 64 already pending | `COMMAND_OVERFLOW` |
| No result in 10 s | `COMMAND_TIMEOUT` |
| 4 delivery attempts | `COMMAND_RETRY_EXHAUSTED` |
| Ownership changed mid-flight | `STALE_OWNER` |
| **No active device online** | `ok:false` with **no `code`**, message "The active playback device is offline." |

That last row is the inconsistency to code defensively around: it is the one
failure that carries no code. Synthesise your own (`COMMAND_FAILED`) so your UI
has something to key off.

Validate `play_context` size **before** the socket write — the reference client
surfaces `PLAY_CONTEXT_TOO_LARGE` locally and nothing crosses the wire.

## Optimistic UI

Send the command *and* immediately rewrite your local mirror so the UI moves
without waiting for a round trip. The owner's next state broadcast overwrites it
wholesale.

Two details:

- Optimistic play/pause must re-anchor at the **extrapolated** position, not the
  last broadcast position, or toggling rewinds the seek bar by up to a second.
- On command failure, deliver the reconciliation on a **deferred microtask**, so
  it lands after the caller's optimistic write has unwound. Otherwise the
  optimistic state sticks and the error is invisible.
