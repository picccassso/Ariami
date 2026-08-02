# Connecting

## 1. Log in

```
POST /api/auth/login
{"username":"...","password":"...","deviceId":"...","deviceName":"...",
 "allowOtherDeviceTakeover": false}
```

All four of username, password, `deviceId` and `deviceName` are required —
missing any gives `400 INVALID_REQUEST`.

```json
{"userId":"...","username":"...",
 "sessionToken":"<64 lowercase hex>","expiresAt":"<ISO-8601 UTC>"}
```

| Status | Code | What to do |
|---|---|---|
| 429 | `RATE_LIMITED` | Back off |
| 409 | `ALREADY_LOGGED_IN_OTHER_DEVICE` | Ask the user, retry with `allowOtherDeviceTakeover: true` |
| 401 | — | Bad credentials |

The token is a **30-day sliding TTL** — using it pushes the expiry out. There is
no refresh endpoint; if it dies, log in again.

## 2. Pick a device identity

The `deviceId` is chosen and persisted **by the client**. The server never mints
one for the WebSocket path. The reference clients use a UUID v4 stored on disk.

Make it stable. The hub evicts duplicates by `(userId, deviceId)`, so a stable
id means a reconnect cleanly displaces your own ghost socket. A randomised id
per launch means ghost devices pile up in everyone's device picker.

`deviceName` is your suggested display name, capped at 40 visible characters. If
the user renamed the device server-side, the server's name wins — read your own
name back out of the hub's device list rather than assuming.

## 3. Open the socket

```
GET /api/ws
```

One socket carries both the legacy library-sync messages and all Connect
messages. There is no separate Connect path.

Build the URL from your HTTP base URL: `https` → `wss`, anything else → `ws`,
append `/api/ws` to the base path, drop query and fragment.

```
http://192.168.1.20:8080        →  ws://192.168.1.20:8080/api/ws
https://music.example.com/ariami →  wss://music.example.com/ariami/api/ws
```

No subprotocol is required or inspected. No auth header is consulted at upgrade
time — `/api/ws` is a public path and authentication happens in the first
`identify` frame.

Two upgrade-time guards:

- An IP already holding **8** unidentified sockets gets
  `429 TOO_MANY_PENDING_CONNECTIONS`.
- A socket that hasn't sent `identify` within **20 seconds** is closed with
  **4008 "Identify timeout"**.

The server sends protocol-level WebSocket pings every 30 s; a missed pong closes
the socket.

## 4. Handshake

Order matters. Send `connect_hello` **first**, then `identify`.

```json
{"type":"connect_hello","data":{
  "protocolVersions":[3,2],
  "canPlay":true,
  "supportedCommands":["clear_queue","cycle_repeat","next","pause","play",
                       "play_context","play_queue_index","previous",
                       "remove_queue_index","seek","toggle","toggle_shuffle"]}}
```

```json
{"type":"identify","data":{
  "deviceId":"<stable id>",
  "deviceName":"<display name>",
  "sessionToken":"<64 hex>",
  "clientType":"desktop"}}
```

Hello arrives before authentication finishes, so the hub retains it as a pending
offer and negotiates once identify lands. Old hubs ignore hello entirely and
fall back to v2.

**`clientType` must be `desktop`, `mobile`, or `tv`.** Anything else (including
absent) registers you for presence but never joins the Connect hub — you will
sit there waiting for a `connect_welcome` that never arrives.

If the server has no registered users yet (first-run bootstrap), the token is
not required and peers register under a legacy user scope.

## 5. Wait for welcome

```json
{"type":"connect_welcome","data":{
  "protocolVersion":3,
  "supportedCommands":[...],
  "devices":[...],
  "activeDeviceId":"desk-1",
  "queueCounter":3,
  "stateRevision":12,
  "ownerEpoch":7,
  "semanticGeneration":41}}
```

You are *connected* when the socket opens. You are *ready* only after welcome.
Gate command sending and takeover flushing on it.

Adopt every counter in the welcome — `protocolVersion`, `ownerEpoch`,
`queueCounter`/`stateRevision`, `semanticGeneration`. On v3 the hub immediately
follows the welcome with `connect_queue` (if a queue exists) and then
`connect_state` (if a snapshot exists). On v2 the snapshot is inline in the
welcome itself.

If no welcome arrives within 5 seconds, the server does not support Connect.
Surface that as a message, not a disconnect.

Full field reference in [03-protocol.md](03-protocol.md).

## Liveness

| Mechanism | Interval | Owner |
|---|---|---|
| Client app-level `ping` | 20 s | client |
| Server WebSocket ping | 30 s | server |
| Client liveness watchdog | 60 s since last inbound | client |
| Hub stale-peer sweep | evicts after 90 s, sweeps every 30 s | server |

Send `{"type":"ping"}` every 20 seconds. The server replies `{"type":"pong"}`,
refreshes your heartbeat, and revalidates your session token. On the same tick,
if you are the owner, publish your state — that keeps the hub fresh even during
a long silent track.

Rearm the 60 s watchdog on **every** inbound message, including malformed ones —
the rearm is about the socket being alive, not the message being valid. When it
fires, replace the socket. This is the only defence against a half-open socket
that still reports "connected" (common when a mobile OS freezes a backgrounded
app's socket without emitting a close event).

## Reconnect

```
delay = min(30, 1 << min(attempt, 5))  seconds
      → 1, 2, 4, 8, 16, 30, 30, 30 ...
```

No jitter, no attempt cap. It retries forever unless suppressed.

Reset the attempt counter after 60 seconds of a connection that has actually
**received inbound traffic**. A socket that opens but never delivers a byte has
not earned a reset.

### When to stop reconnecting

| Close | Reason | Action |
|---|---|---|
| 4001 | `Authentication required` / `Session expired or invalid` / `Session expired or revoked` | **Stop.** Clear the cached token, prompt for sign-in |
| 4000 | reason contains `replaced` | **Stop.** Another socket for this same device took over |
| 4000 | `Connection timed out`, shutdown | Reconnect normally |
| 4002 | `Disconnected by admin` | Reconnect normally |
| 4008 | `Identify timeout` | Fix your handshake |

Not suppressing on `4000 replaced` creates a two-socket reconnect fight between
your own client instances.

### State to reset on every disconnect

Reset these, or the next session desyncs:

- `lastRevision` high-water mark → `-1`. Keeping it across a hub restart
  silently freezes every remote mirror, because the fresh hub counts from zero.
- `ownerEpoch` → 0, `activeDeviceId` → null, cached queue counter → cleared.
- Negotiated protocol version → back to the pre-welcome sentinel. Never assume
  the next hub speaks v3.
- Pending-command retry timers → cancelled, but the **pending commands
  themselves are kept** and replayed after the next welcome.
- Any pending takeover *intent* survives; the "already sent on this connection"
  flag does not.

### The rule that will bite you

**An audible owner must never reconnect voluntarily.**

Failover is immediate, so the hub cannot tell a dropped owner apart from one
that closed its own socket. Reopening the socket to resynchronise — on
foreground resume, for example — hands the session to another device and earns
you a former-owner pause the moment the reconnect lands, silencing the very
playback you meant to keep.

Gate any voluntary refresh on "am I connected, active, and locally playing?".
If yes, do nothing and let the ping and liveness timers handle a genuinely dead
socket. A device that is only mirroring may reconnect freely.

### Leaving on purpose

When the user quits the app while this device is the owner, do **not** publish
the resulting local pause. Order:

1. Freeze Connect publication.
2. Stop the local engine.
3. Close the socket.

The retained *playing* snapshot is the continuation intent the hub hands to the
replacement device. Publishing a final paused snapshot kills the session for
everyone instead of continuing it elsewhere.

## Bounded teardown

Every close path is time-boxed: 8 s to open, 1 s to close on refresh, 1 s to
close on dispose. A transport that never completes its close must not block its
replacement. There is no unbounded await anywhere in the reference transport,
and there should not be one in yours.

## Discovery

`GET /api/server-info` (public, no auth) returns the addresses to keep:

```json
{"server":"100.x.y.z","lanServer":"192.168.1.20","tailscaleServer":"100.x.y.z",
 "publicOrigin":"https://…","port":8080,"name":"studio-pi","version":"5.0.0",
 "authRequired":true,"hasUsers":true}
```

Keep **both** the LAN and Tailscale aliases and switch routes without changing
your Connect identity. Ports are 8080 preferred with 8081–8099 fallback.

Auto-discovery on a LAN: UDP `ARIAMI_DISCOVER_V1` to port 45420 (multicast
239.255.90.90), and mDNS `_ariami._tcp.local`.

**Apple platforms:** App Transport Security blocks plain `http` to Tailscale
100.64/10 CGNAT addresses (LAN ranges are exempt), and AVPlayer fails with
-1022. You will need an ATS exception to stream over Tailscale. Budget for it.
