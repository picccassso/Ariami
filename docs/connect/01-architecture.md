# Architecture

## Topology

```
   phone (LAN)  ────┐
   desktop (LAN) ───┼──►  Ariami server  ──►  Connect hub (in memory)
   TV (Tailscale) ──┘         /api/ws
```

Every client opens one outbound WebSocket to the server. Nothing else. No
peer-to-peer, no audio proxying, no LAN multicast for playback state.

Consequences worth internalising:

- **Route-independent.** A device on Tailscale and a device on the LAN share a
  session because both sockets land on the same hub. A client keeps both
  endpoint aliases and can switch routes without changing its Connect identity.
- **Audio is fetched, not forwarded.** Each device mints its own short-lived
  stream ticket and pulls audio from the server. Connect payloads deliberately
  never carry stream URLs, tickets, passwords, or session tokens.
- **The hub is not a database.** It is in-memory state. A server restart clears
  it and clients re-establish. See [Retained state](#retained-state).

## Session rules

- Sessions are isolated by authenticated **user ID**. Two accounts on one server
  never see each other's devices.
- Exactly **one** online device is authoritative for playback at a time. That
  device is the *owner* (also called the active device).
- The owner publishes: queue, current index, position, playing state, shuffle,
  repeat, volume, and collection source.
- Every other device *mirrors* that state and can send commands to it.
- A device may declare `canPlay: false` — a pure controller. It receives state
  but is never listed as a playback target and can never become owner.

## Roles

| Role | Publishes state | Receives commands | Appears in device list |
|---|---|---|---|
| Owner (active device) | yes | yes | yes |
| Playback-capable mirror | no | no | yes |
| Controller (`canPlay: false`) | no | no | no |

Roles are not declared, they are situational. Any playback-capable device
becomes the owner by claiming the session, and stops being it the moment
ownership moves.

## Mirroring

While another device owns the session, a client's main transport UI shows
*that device's* playback, Spotify-Connect style, instead of its own idle queue:
the player bar and now-playing screen render the remote track, queue and
progress, and play/pause/skip/seek/shuffle/repeat/queue taps become Connect
commands.

- The mirrored position is extrapolated from the **local receipt time** of the
  last snapshot. Clock skew between devices never bends the seek bar.
- Controls apply an optimistic local adjustment immediately; the owner's next
  state broadcast is authoritative and overwrites it.
- The local queue survives underneath the mirror and returns when the remote
  session ends. Mirroring never destroys local playback state.
- Commands routed *to* a device always run against its local engine. They must
  never bounce back out as remote commands.

## Starting music from a mirror

This is where Connect differs from a plain remote control:

- Pressing **play/pause/next/seek** while mirroring sends a command to the owner.
- Choosing **new music** (an album, a playlist, a track) while mirroring sends
  `play_context` — the owner's queue is replaced and it starts playing. Browsing
  anywhere plays on the device that owns the session.
- Starting music when **no remote session exists** is an implicit takeover: you
  become the owner.

Moving playback *between* devices is always explicit, via the device picker.
Music never jumps devices on its own except during failover.

## Ownership in one paragraph

The hub mints a monotonically increasing `ownerEpoch`. Every ownership change
increments it. Commands, state publications, queue publications and handoffs all
carry the epoch they believe is current, and the hub rejects anything from an
older epoch. A device that learns about a newer epoch in which it is no longer
the owner **pauses its local engine before adopting the mirror**. That single
rule is what stops two devices making sound at once. Full detail in
[05-ownership.md](05-ownership.md).

## Retained state

The hub keeps a settled, peerless session in memory for **30 minutes**, so
devices can recover from an ordinary route change, sleep, or short outage. It
never expires a session while a failover, command, or handoff is pending — the
timer re-arms instead.

After 30 idle minutes with no peers and no pending transitions, the hub discards
the retained queue, playback snapshot, owner epoch and command bookkeeping. The
next device starts a fresh session from its own locally persisted state.

A server restart does the same thing. Neither deletes music, playlists,
downloads, listening history, or any client's local queue.

## Protocol versions

Two versions are live: **v2** and **v3**. Selection is per peer — a v2 phone and
a v3 TV can share a session, and the hub renders each broadcast in the
recipient's own dialect.

- **v2** sends a complete playback snapshot, queue included, on every state
  publish. Simple, and expensive: a 500-track queue measured ~155 KB per
  publication, ~28 MB/min at 1 Hz with two peers.
- **v3** splits the queue onto its own `connect_queue` message, sent only when
  the queue actually changes. Subsequent `connect_state` messages reference it
  by counter. Same semantics, far less traffic.

The server can disable v3 negotiation at runtime, so a client must accept
whatever version the welcome names and never assume v3.

## Security model

- The WebSocket uses the same session-token validation as the rest of Ariami.
  Tokens are revalidated during the connection, not just at identify.
- The hub derives the user scope from the validated session, never from
  client-supplied data.
- Queue payloads, string lengths, numeric ranges and message sizes are all
  bounded before use. See [08-reference.md](08-reference.md).
- Connect payloads carry catalog metadata only. Every playback device requests
  its own stream ticket.
