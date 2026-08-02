# Gotchas

Things that look optional and are not. Roughly ordered by how badly they break.

## Ownership and audio

**1. An audible owner must never reconnect voluntarily.**
Failover is immediate, so a deliberate reconnect looks identical to death. The
hub hands the session away and pauses you as the former owner — silencing the
playback you were trying to protect. Gate any refresh on "connected AND active
AND locally playing". Mirroring clients may reconnect freely.

**2. Never publish a paused snapshot on the way out.**
Freeze publication → stop the engine → close the socket. The retained *playing*
snapshot is the continuation intent the hub hands to the replacement. Publish
the pause and the session dies with you instead of continuing elsewhere.

**3. Losing ownership must pause before adopting the mirror, and must await it.**
Not "start a pause and continue". If the pause fails, reject the message
entirely. Idempotent per epoch, or a commit plus a devices broadcast pauses you
twice.

**4. An equal epoch with a different owner is a rejection, not an update.**
An owner cannot change without the epoch advancing. Accepting it lets two
devices both believe they own the session.

**5. Commands routed *to* you must never bounce back out.**
A transfer commit marks you active before your controller layer has cleared the
previous mirror. Clear the stale mirror inside the command handler, first thing,
or the hub's own command gets re-routed to the old owner.

**6. Don't re-run the pause the epoch transition already did.**
The hub sends a synthetic former-owner pause *and* the epoch fence pauses you.
Answer the command; don't pause twice.

## Takeover

**7. Register your playback listener before any async startup await.**
A user pressing play during startup must have that intent stashed and flushed
once the client exists. Otherwise the welcome's stale remote snapshot wins and
their music stops.

**8. A cancelled takeover must stay cancelled.**
Play-then-pause during startup, then a reconnect — the intent must not
resurrect. And if the activation already crossed the wire, republish the current
paused state in the confirmed epoch, or the hub keeps your stale playing
snapshot forever.

**9. Suppress the mirror the instant the user presses play.**
Bounded window, ahead of hub confirmation. Without it, round-trip latency shows
the old owner's state flashing back over the user's own music. Defer a mirror
arriving inside the window with a timer rather than dropping it.

**10. Mirror suppression must also key on "pending takeover" and "applying
remote state", not just "am I active".**

## Queue and ordering

**11. `backingOrder` is positional, never id-keyed.**
Queues legitimately contain the same track id twice. An id-keyed unshuffle
collapses the two occurrences into one. This is what the shared fixture exists
to catch, and it is the bug every client has written at least once.

**12. `index` means "position in the published resolved play order".**
Not an index into any backing or unshuffled list. Always send the `id` guard
with `remove_queue_index`.

**13. Use atomic `clear_queue`, never N sequential removes.**
Sequential removes race against the owner's own position ticks and re-indexing.

**14. Compact your backing queue when removing.**
Otherwise a later shuffle/unshuffle resurrects the removed track.

**15. Canonicalise your queue fingerprint with sorted keys.**
A different JSON key insertion order otherwise looks like a queue change and
churns the counter on every publish.

**16. Never resend a v3 queue while awaiting its echo — except a takeover.**
Takeovers must resend, because the hub commits ownership from the queue message
itself.

**17. Repeat-one widens to repeat-all on an explicit track change.**
Apply on both send and receive of `play_context`.

**18. Out-of-range queue edits are silent no-ops that send nothing.**

## Protocol

**19. Absent `supportedCommands` means "everything". Empty means "nothing".**
Invert this and you either mute your client or make it silently swallow commands
it advertised.

**20. Never assume v3.**
The server can disable v3 negotiation at runtime. Accept whatever the welcome
names, and reset your negotiated version on every disconnect.

**21. Reset `lastRevision` to `-1` on disconnect.**
Keeping the high-water mark across a hub restart silently freezes every remote
mirror, because the fresh hub counts from zero. This one is invisible in testing
and obvious in production.

**22. Read `stateRevision` on v3 and `revision` on v2.**
A transfer commit carries both. Reading only one strands your high-water mark.

**23. A queue-counter regression is legal across an epoch change, illegal within
one.**

**24. Validate raw message size before decoding.**
8 MiB, on the encoded byte length. Not after `jsonDecode`.

**25. Tolerate malformed queue items individually.**
Skip an unparseable entry. One item serialised by a newer client must not blank
the whole mirrored session.

**26. Never close the socket over a malformed message.** Ignore it and continue.

**27. The "active device is offline" failure carries no error code.**
Every other failure has one. Synthesise your own.

**28. `connect_rename` has no success ack.** The `connect_devices` broadcast that
follows is your confirmation.

**29. The envelope `timestamp` is ignored and not reliably UTC.** Don't use it.

## Transport

**30. Rearm the liveness watchdog on every inbound message, including malformed
ones.** The rearm is about the socket being alive.

**31. Guard every callback by socket identity.**
An old socket's late `onDone` must never tear down its replacement. You need
*two* fences — socket identity and a connection generation counter — because a
refresh bumps the generation without emitting a close event.

**32. Process inbound messages strictly in order, through one serialised chain.**
A naive per-message async handler reorders `prepare` and `commit`, or lets a slow
pause be overtaken by the state message behind it. A throw in one message must
not poison the chain.

**33. Time-box every close.**
A transport that never completes its close must not block its replacement.
1 second is the reference budget.

**34. Backoff resets only after 60 s of a connection that received traffic.**
A socket that opens and delivers nothing has not earned a reset.

**35. Don't retry commands against a hub that can't dedupe.**
Below protocol v2, drop the command. Replaying `next` twice is worse than
failing once.

**36. There is no jitter in the backoff.**
Many clients plus a server restart equals a synchronised herd at 1 s, 2 s, 4 s.
The fault tests assert the exact unjittered sequence, so this is deliberate —
but know it's there.

## Engine and platform

**37. Don't await your engine's `play()` inside a Connect handler.**
just_audio and friends return a future that completes when playback *ends*.
Awaiting it pins you in "applying remote state" for the whole track and
suppresses every publication.

**38. Preserve object identity for an unchanged mirrored queue.**
Position ticks arrive every second. Rebuilding your song objects recreates every
list row and re-fetches artwork on each tick.

**39. `detached` is not process death on Android.**
Flutter reports detached on activity recreation too. The Connect socket is the
authoritative signal. Pausing on `detached` kills backgrounded playback.

**40. Mirror artwork must come from an on-device cache.**
Notification and lock-screen artwork loaders can't send session headers, and a
mirrored track has no stream ticket of yours.

**41. Apple ATS blocks plain http to Tailscale 100.64/10 addresses.**
LAN ranges are exempt; CGNAT is not. AVPlayer fails with -1022.

**42. The hub is not durable storage.**
A restart, or 30 idle peerless minutes, clears the retained session. Re-establish
from your own persisted local state.

## When clients disagree

Shipped clients do not all behave identically at the edges — the no-welcome
timeout, the exact precondition for resetting reconnect backoff, and whether a
transient reconnect sets an error code all vary in practice.

Where behaviour differs, `ariami_core` is normative: the fault matrix in
`ariami_core/test/fixtures/connect/fault_matrix.json` is what the test suite
actually exercises. Build against that rather than against any single client's
observed behaviour.
