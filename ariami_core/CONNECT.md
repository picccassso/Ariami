# Ariami Connect protocol and recovery

Ariami Connect is an authenticated, account-scoped playback rendezvous. The
server is authoritative for the current owner and mirrored state, while every
client keeps its own playback engine and persists its own local queue. Exactly
one device should produce audio for an account at a time.

## Connection and authentication

Clients first send `connect_hello` with their supported protocol versions and
command capabilities. They then identify over the shared WebSocket with their
session token, stable device ID, display name, and client type. The server
validates the token when the socket identifies and revalidates it during the
connection. A revoked or expired session closes with code `4001`; clients must
stop reconnecting and request sign-in recovery.

Device lists are ordered by display name, then stable device ID. The ID
tie-breaker keeps two devices with the same visible name in a deterministic
order without affecting playback ownership.

## Protocol versions

Protocol selection is per peer. The server can disable v3 negotiation at
runtime, and the v2 path remains supported during rolling upgrades.

- Legacy v2 clients may omit `connect_hello`; a missing or malformed offer
  selects the established v2 full-snapshot behavior.
- V3 sends `connect_queue` when the resolved queue, positional
  `backingOrder`, or source changes. Later `connect_state` progress updates
  refer to that queue by owner epoch and queue counter.
- V2 sends complete playback snapshots. The hub normalizes incoming v2 state
  and reconstructs complete snapshots only for v2 peers.
- V2 traffic does not force v3 peers back onto complete snapshots.
- A queue originating on v2 has identity backing order because its original
  pre-shuffle order cannot be inferred safely.

Commands, queue/state publications, and handoffs are fenced by the hub-minted
owner epoch. Work from an older epoch is rejected. A former audible owner that
learns about a newer owner pauses before adopting the remote mirror.

## Disconnect recovery and failover

When the audible owner disconnects:

1. The server gives that device 20 seconds to reclaim the same owner epoch.
2. If it does not return, the server tries connected playback candidates in a
   deterministic order.
3. A device that issued an accepted command in this session within the last
   120 seconds may inherit playing state. Connection recency alone never
   authorizes automatic playback.
4. Other candidates prepare the session paused. A failed preparation advances
   to the next candidate.
5. If every candidate fails or none exist, the session becomes ownerless and
   settles paused.

Handoffs capture the owner epoch, queue identity, and semantic generation.
Concurrent pause, seek, track, queue, shuffle, repeat, volume, or ownership
changes cancel a stale preparation. A rejected, timed-out, disconnected, or
superseded target restores the local state it held before preparation.

## Retained state

The hub keeps a settled, peerless session in memory for 30 minutes so devices
can recover from an ordinary route change, sleep, or short outage. It never
expires a session while a reclaim, command, or handoff transition is pending.

After 30 idle minutes with no peers or pending transitions, the hub discards
the retained queue, playback snapshot, owner epoch, and command bookkeeping.
The next device starts a fresh Connect session from its locally persisted
state. This does not delete music, playlists, downloads, listening history, or
any client's local queue.

The hub state is intentionally not durable server storage. A server restart
also clears it; reconnecting clients establish the current state again.
