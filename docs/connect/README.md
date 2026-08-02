# Ariami Connect

Ariami Connect moves playback between your signed-in devices. Start an album on
your phone, push it to the TV, keep controlling it from the desktop — one
session, one device making sound, every other device acting as a remote.

This folder is the complete reference: how it works, what crosses the wire, and
how to write a client that speaks it.

## Read this first

Connect is **not** audio streaming between devices. The server never proxies
audio and clients never talk to each other. Every device keeps its own playback
engine and its own local queue; the server only brokers *who is playing* and
*what they are playing*. Each device fetches its own audio from the server
directly.

That topology is the whole point: a TV on the LAN and a phone on Tailscale can
share a session, because both routes terminate at the same server-side hub.

## The docs

| File | What's in it |
|---|---|
| [01-architecture.md](01-architecture.md) | Topology, session rules, the mental model |
| [02-connecting.md](02-connecting.md) | Auth, the WebSocket, handshake, reconnect, liveness |
| [03-protocol.md](03-protocol.md) | Every message, every field, v2 vs v3 |
| [04-commands.md](04-commands.md) | Remote commands, delivery guarantees, failures |
| [05-ownership.md](05-ownership.md) | Owner epochs, takeover, handoff, failover |
| [06-third-party-clients.md](06-third-party-clients.md) | Build a client from scratch |
| [07-gotchas.md](07-gotchas.md) | The traps. Read before shipping |
| [08-reference.md](08-reference.md) | Constants, close codes, error codes, endpoints |

## The short version

1. Log in over HTTP, get a session token.
2. Open a WebSocket to `/api/ws`.
3. Send `connect_hello` (capability offer), then `identify` (auth).
4. Wait for `connect_welcome`. It names your protocol version, the current
   owner, and the session's fencing counters.
5. If you can play audio, publish `connect_state` when your playback changes.
   If you can't, or aren't the owner, mirror what the owner publishes.
6. Send `connect_command` to control whoever is playing.

## Where the code lives

| Piece | Path |
|---|---|
| Wire models, validation, limits | `ariami_core/lib/models/connect_models.dart` |
| Server-side hub | `ariami_core/lib/services/connect/connect_hub.dart` |
| Reference client | `ariami_core/lib/services/connect/connect_client.dart` |
| Mirror playback shim | `ariami_core/lib/services/connect/remote_playback.dart` |
| Cross-client contract fixture | `ariami_core/test/fixtures/connect/v2_contract.json` |
| Fault coverage matrix | `ariami_core/test/fixtures/connect/fault_matrix.json` |

The two fixtures are the contract. Decode them with your own decoder and the
rest of the protocol follows.
