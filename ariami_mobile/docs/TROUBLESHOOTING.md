# Troubleshooting

This guide is grounded in the actual client code under `lib/`,
`ios/Runner/Info.plist`, and `android/app/src/main/AndroidManifest.xml`, so
every fix references the file and behaviour it's based on. Where the app's
own messages are quoted, the wording matches the source so you can grep for
it; a few of the longest strings are shortened here.

Jump to a section:

- [Setup and pairing](#setup-and-pairing)
  - [App can't find / connect to the server](#app-cant-find--connect-to-the-server)
  - [Manual IP/port entry fails](#manual-ipport-entry-fails)
  - [QR code won't scan / "isn't an Ariami pairing code"](#qr-code-wont-scan--isnt-an-ariami-pairing-code)
  - [Login / registration / invite code failures](#login--registration--invite-code-failures)
- [Staying connected](#staying-connected)
  - [Connection drops on Wi‑Fi sleep, screen lock, or cellular handoff](#connection-drops-on-wifi-sleep-screen-lock-or-cellular-handoff)
  - [iOS: "Local Network" permission and streaming over Wi‑Fi](#ios-local-network-permission-and-streaming-over-wifi)
  - [Android: cleartext HTTP / network security](#android-cleartext-http--network-security)
  - [VPN or router client isolation ("AP isolation")](#vpn-or-router-client-isolation-ap-isolation)
  - [Which address is the app actually using?](#which-address-is-the-app-actually-using)
- [Playback](#playback)
  - [Playback stalls or won't start](#playback-stalls-or-wont-start)
  - [A song gets skipped automatically](#a-song-gets-skipped-automatically)
  - [No lock-screen/notification controls, or playback stops in the background](#no-lock-screennotification-controls-or-playback-stops-in-the-background)
  - [Playback is interrupted by calls, other apps, or headphone unplug](#playback-is-interrupted-by-calls-other-apps-or-headphone-unplug)
- [Downloads and offline mode](#downloads-and-offline-mode)
  - [Downloads fail, pause themselves, or won't finish](#downloads-fail-pause-themselves-or-wont-finish)
  - [Downloads stop when the app is backgrounded (Android)](#downloads-stop-when-the-app-is-backgrounded-android)
  - [Storage keeps filling up](#storage-keeps-filling-up)
  - [Offline mode won't turn off / stuck showing "will auto-reconnect"](#offline-mode-wont-turn-off--stuck-showing-will-auto-reconnect)
- [Library and content](#library-and-content)
  - [Artwork missing](#artwork-missing)
  - [Library looks out of sync after a server rescan](#library-looks-out-of-sync-after-a-server-rescan)
  - [Playlists show songs that won't play](#playlists-show-songs-that-wont-play)
- [Gathering logs and resetting app state](#gathering-logs-and-resetting-app-state)

---

## Setup and pairing

### App can't find / connect to the server

**Likely causes, in order of how common they are:**

1. The phone and server aren't on the same network, and Tailscale isn't set
   up (or isn't connected).
2. The server isn't running, or you have the wrong port.
3. Something in the network path (router isolation, VPN split-tunnelling)
   blocks the phone from reaching the server's LAN IP.

**How to confirm:** Every setup failure is caught and mapped to a specific
message by `lib/utils/setup_error_messages.dart`
(`describeSetupConnectError`), so read what's shown on screen; it's chosen to
be actionable:

- *"Connecting to `<address>` timed out..."* followed by advice to check
  WiFi/Tailscale and try again. The socket connect attempt (via
  `dart:io Socket`) didn't get a response in time. This is a
  `TimeoutException`.
- *"Nothing is listening at `<address>`. Check the port and that the Ariami
  server is running."* The OS returned `Connection refused`: something is
  reachable at that IP but nothing is listening on that port.
- *"Couldn't reach `<address>`. Check the address and that this phone is on
  the same network or VPN as the server."* A `SocketException`, "Network is
  unreachable", "No route to host", or DNS failure (`Failed host lookup`).
  This is the generic "can't get there at all" case, usually different
  networks or a firewall in between.
- *"Something answered at `<address>`, but it doesn't look like an Ariami
  server. Double-check the address and port."* Something responded, but not
  with Ariami's JSON API, for example a router's admin page on that IP and
  port.

**Fix:**

- Confirm the phone is on the same Wi‑Fi as the server, or that Tailscale is
  installed and connected on **both** devices
  (`lib/screens/setup/tailscale_check_screen.dart` walks through this and can
  re-check status with "Check Again").
- Double check the port. The desktop/CLI server's default port is `8080`
  (`ParsedServerAddress.defaultPort` in `lib/utils/server_address_parser.dart`);
  secure/HTTPS deployments default to `443`.
- If using Tailscale, use the Tailscale (`100.x.y.z`) address rather than the
  LAN IP when off the home network.
- Retry. The underlying reachability check
  (`ConnectionLifecycleManager.isServerReachable`) uses a short 1.5s TCP
  probe, so a momentarily slow network can legitimately need a second try.

### Manual IP/port entry fails

`lib/screens/setup/manual_server_entry_screen.dart` accepts `host[:port]`,
with or without a `http://`/`https://` scheme, validated by
`lib/utils/server_address_parser.dart`. Notes on what it accepts and
rejects:

- The scheme is optional; if you omit it, `http://` is assumed.
- The port is optional; it defaults to `8080` for `http`, `443` for `https`.
- An address with a path, query string, userinfo, or fragment is rejected
  outright (only a bare `scheme://host:port` or `host:port` is accepted, with
  an optional trailing slash). If you pasted a URL with a trailing path like
  `/dashboard`, strip it.
- An empty field shows *"Please enter the server address"*; an unparseable
  one shows *"Enter a valid address like 192.168.1.50:8080"*.
- After you enter the address, the app calls the server's public
  `/api/server-info` endpoint to learn its name/version/auth mode before
  connecting. If that call fails, you'll see the same
  `describeSetupConnectError` messages as above.
- The optional **invite code** field (behind the "Have an invite code?"
  toggle) only matters when the server already has an owner account and
  registration isn't open. See below.

### QR code won't scan / "isn't an Ariami pairing code"

The scanner (`lib/screens/setup/qr_scanner_screen.dart`) uses `mobile_scanner`
and strictly validates the decoded payload in
`lib/utils/qr_payload_parser.dart` before accepting it. If validation fails
for *any* reason (wrong host format, out-of-range port, mistyped boolean
flags, or a code that isn't JSON at all, such as a WiFi-sharing QR code, a
URL, or a random image), you'll see the generic message:

> *"This isn't an Ariami pairing code. Scan the QR shown by your desktop
> server."*

This message is intentionally generic (it never echoes back what was
scanned, since a real payload can carry a registration token). If you're
sure you're pointing at the right QR code and this keeps happening:

- Make sure the whole QR code is inside the frame and in focus; use the
  torch button (top-right) in low light.
- Regenerate the QR from the server. An expired registration token in an
  otherwise-valid payload will fail differently (see login/registration
  below), not with this message; this message specifically means the code's
  *shape* didn't match.
- If scanning repeatedly fails on the exact same code, the app enforces a
  4-second cooldown before re-processing that identical code
  (`_failedScanCooldown` in `qr_scanner_screen.dart`) so it doesn't loop.
  That's expected, not a bug.
- Use **Manual entry** instead (button at the bottom of the scanner screen).

If the scanner shows **"Camera access needed"** instead, camera permission
was denied. Tap **Open Settings** to grant it, or use Manual entry. If it
shows **"Camera unavailable"**, the camera failed to start for a
device-specific reason; **Try camera again** recreates the scanner
controller, which also re-runs the permission check (useful right after
granting permission in Settings).

### Login / registration / invite code failures

Errors from `/auth/login` and `/auth/register` are mapped to specific text
in `lib/screens/login_screen.dart` and `lib/screens/register_screen.dart`:

- **"Invalid username or password"**: the server returned
  `INVALID_CREDENTIALS`.
- **"Username already taken"**: the server returned `USER_EXISTS` during
  registration.
- **"That invite code is invalid or expired. Ask the server owner for a
  fresh code (or QR) and try again."**: registration was rejected as
  closed/disabled (matched against error codes `REGISTRATION_CLOSED`,
  `REGISTRATION_DISABLED`, `PUBLIC_REGISTRATION_DISABLED`, or a message
  containing "registration" plus "closed"/"disabled"/"not accepting" via
  `_isRegistrationClosed` in `register_screen.dart`). Get a fresh invite
  code or QR from the server owner; invite codes are normalised to uppercase
  alphanumerics, so case doesn't matter.
- **"Registration is closed for this server. Scan the owner QR code or ask
  the server owner for an account."**: shown in place of the "Create
  Account" link when `ServerInfo.canRegister` is false (no legacy mode and
  no invite token attached).
- **"Already signed in elsewhere"** dialog: the account is active on another
  device. Choosing **Sign in here** retries the login with
  `allowOtherDeviceTakeover: true`, which signs the other device out. The
  dialog explicitly warns that on-device data (playlists, stats) stays on the
  other device and doesn't transfer automatically. If you need it here,
  export it via **Settings → Import / Export** (the Backup & Restore screen)
  on the other device first.
- Any other connection-level failure during login/register (timeout,
  refused, unreachable) falls back to the same
  `describeSetupConnectError` messages as initial setup.

---

## Staying connected

### Connection drops on Wi‑Fi sleep, screen lock, or cellular handoff

The app treats a dropped connection as **recoverable by design**, so in most
cases it doesn't need a force quit or a manual reconnect:

- A **heartbeat** pings the server every 30 seconds
  (`lib/services/api/connection/heartbeat_manager.dart`). It tolerates up to
  3 consecutive failures before it declares the connection lost and switches
  to **auto-offline** mode, so a single missed ping (a phone waking from
  Wi‑Fi sleep) doesn't disconnect you. It can take up to about 90 seconds of
  real unreachability before the app gives up.
- Once in auto-offline, the heartbeat itself keeps calling
  `tryRestoreConnection()` on its own 30-second cadence. A
  **connectivity-change listener** in `lib/main.dart` also fires a debounced
  (500ms) reconnect attempt as soon as the OS reports Wi‑Fi or mobile data
  becoming available again, and returning to the foreground triggers
  `_triggerResumeReconnectIfNeeded()` for an immediate attempt.
- The WebSocket connection (`lib/services/api/websocket_service.dart`) pings
  separately every 30 seconds and reconnects 5 seconds after any drop,
  independent of the HTTP heartbeat, unless manual offline mode is on.
- If your account signs out from elsewhere or the server invalidates the
  session, the WebSocket close code (4001/4002) is treated as **session
  invalidated** rather than a network blip, and you're taken straight to the
  sign-in screen instead of endlessly retrying.

**If it seems stuck offline longer than that:** open **Settings →
Connection Status**. The Connection screen shows live connection status, and
when offline mode is off but the connection is still down it offers a
**Retry Connection** button. The **Offline Mode** switch itself lives on the
main Settings screen; while it's on, that's a manual disconnect, and the
Connection screen hides the retry button and reminds you to turn Offline
Mode off. The auto-reconnect loop above only runs when offline mode is *not*
manually enabled.

**On cellular handoff specifically:** a Tailscale address should keep
working across Wi‑Fi and cellular as long as Tailscale itself reconnects; a
bare LAN IP will not be reachable from cellular data at all (see below).

### iOS: "Local Network" permission and streaming over Wi‑Fi

`ios/Runner/Info.plist` declares:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Ariami uses your local network to discover Chromecast devices on your Wi-Fi network.</string>
<key>NSBonjourServices</key>
<array>
  <string>_CC1AD845._googlecast._tcp</string>
  <string>_googlecast._tcp</string>
</array>
```

iOS shows its system **"Ariami" would like to find and connect to devices on
your local network** prompt (using this description text) the *first time*
the app makes any connection to a device on your LAN (a private IP or
`.local` address), not only for Chromecast. That includes connecting
directly to your Ariami server's LAN IP. If you tapped **Don't Allow** on
this prompt:

- LAN streaming/setup can fail even though the server is reachable and
  correctly configured, because iOS itself is blocking the local connection
  at the OS level, before your app-level "can't reach the server" errors
  even come into play.
- **Fix:** Settings app → Ariami → **Local Network** → enable it. Then
  retry connecting (Settings → Connection Status → Retry Connection, or
  reopen the app). There's no dedicated in-app button for this toggle, so
  use the Settings app.

Separately, `Info.plist` sets:

```xml
<key>NSAllowsArbitraryLoads</key>
<true/>
```

This disables App Transport Security globally. The comment in the file
explains why: ATS normally exempts plain private LAN addresses
(`192.168.x.x`) automatically, but **not** Tailscale's CGNAT range
(`100.64.0.0/10`) or MagicDNS hostnames. Without this override, `AVPlayer`
(used for actual audio streaming) would refuse Tailscale stream URLs with
error `-1022`, even though ordinary HTTP calls (login, library, artwork)
still worked. If you're troubleshooting an iOS build where songs never
start playing but everything else (browsing, login) works fine over
Tailscale, check that this key hasn't been removed from a custom Info.plist.

### Android: cleartext HTTP / network security

`android/app/src/main/AndroidManifest.xml` sets, at the `<application>`
level:

```xml
android:usesCleartextTraffic="true"
```

This allows plain HTTP to any host app-wide (there is no separate
`network_security_config.xml` restricting it further). Ariami servers speak
plain HTTP by default, so this is required for the app to work at all. If
you've forked/rebuilt the app and streaming or connecting fails with a
cleartext-related error, check that this flag (or an equivalent
`networkSecurityConfig`) is still present.

### VPN or router client isolation ("AP isolation")

If the phone shows Wi‑Fi connected, the server is definitely running, and
you still get "Couldn't reach `<address>`" / connection-refused errors:

- **Router client (AP) isolation**, common on guest networks and some
  mesh/eero-style routers, stops devices on the same Wi‑Fi from talking to
  each other at the IP level. From the app's point of view this looks
  identical to being on a different network: the TCP socket connect in
  `ConnectionLifecycleManager.isServerReachable` simply times out or is
  refused. Check the router's admin settings for "AP/client isolation" or
  "guest network isolation" and disable it for the network the server and
  phone share, or move both onto the same non-isolated network.
- **A VPN with split-tunnelling or a "block LAN access" option** on the
  phone can prevent LAN traffic while it's active, even though Wi‑Fi shows
  connected. Try toggling the VPN off to confirm before assuming the server
  is unreachable. Tailscale is designed to coexist with LAN access; a
  *different*, general-purpose VPN is more likely to cause this.
- If you rely on Tailscale for remote access, confirm it's actually
  connected on both ends via **Settings → Connection Status**, which shows
  whether the active route is "Local Network", "Tailscale", or "Secure
  Internet" (see next section). If it says something unexpected, that tells
  you which path is actually being tried.

### Which address is the app actually using?

Open **Settings → Connection Status**
(`lib/screens/settings/connection_settings_screen.dart`). While connected
and not in offline mode, it shows a **Server Information** section with:

- **Route**: `Local Network`, `Tailscale`, or `Secure Internet` (an explicit
  HTTPS `publicOrigin`, if the server was set up with one).
- **Active Address**, plus (if known) separate **LAN Address** and
  **Tailscale Address** fields.
- **Port** and server **Version**.

Behind the scenes, `lib/services/api/endpoint_resolver.dart` automatically
prefers the LAN address whenever a quick 500ms TCP probe says it's
reachable, checked every 15 seconds and on every network-type change, and
falls back to Tailscale/primary otherwise. This is why the **Active
Address** can silently change, for example when you get home and Wi‑Fi
becomes reachable. That's expected: the app is switching to the faster local
path. A server reachable only over HTTPS (`publicOrigin` set) never gets
swapped to a cleartext LAN/Tailscale address, which is a deliberate
trust-boundary rule in `ServerInfoManager.resolvePreferredServerInfo`.

---

## Playback

### Playback stalls or won't start

If a song has an on-device copy (downloaded or previously cached), the app
gives a stream at most **8 seconds** to start
(`_streamStartStallTimeout` in `lib/services/playback_manager_streaming_impl.dart`)
before it automatically falls back to playing the local/cached copy instead.
You'll see it start playing, but from the on-device file rather than a fresh
stream. This is deliberate: a phone whose Wi‑Fi "looks" connected but has no
real internet (walking out the door) would otherwise hang far longer before
the 30-second heartbeat even notices anything is wrong.

If a song has **no** on-device copy and the stream request fails outright
with `SONG_NOT_FOUND` (the server no longer has it, for example because it
was removed in a rescan), the app auto-skips it and shows a snack bar saying
*Skipped "<title>"*, then *it is no longer on the server.* (or *Skipped a
song that is missing from the library* when the title isn't known; see
`lib/main.dart`, `_listenToUnplayableSongs`).

**If playback stalls with no fallback available at all** (no download, no
cache, genuinely unreachable server): confirm the connection is actually up
in Settings → Connection Status, and see the connection sections above. A
stalled stream very often has the same root cause as a stalled setup
connection (wrong network, AP isolation, VPN).

### A song gets skipped automatically

See directly above: this happens specifically when a queued/playlist song no
longer exists on the server (its ID returns `SONG_NOT_FOUND`) and there's no
local copy to fall back to. Use **Settings → Clean Up Playlists**
(`lib/screens/main/settings_screen.dart`) to remove these stale entries from
your playlists in one step. It requires a fully-synced online library first
(you'll see *"Connect to your server first"* when cleanup needs a fresh
library, or *"Library has not finished syncing yet."* if you try too early),
then reports what it removed, for example *"Removed 3 songs from 1
playlist."*, or a "playlists are clean" message if there was nothing to do.

### No lock-screen/notification controls, or playback stops in the background

- Background playback is provided by `audio_service`
  (`AudioServiceConfig` in `lib/main.dart`), which requires the
  **notification permission** to show its media controls, requested during
  first-run setup (`lib/screens/setup/permissions_screen.dart`,
  `lib/services/permissions_service.dart`). If you tapped **Skip** there (the
  app warns: *"Without notifications, you won't see playback controls in
  your notification panel."*) or later denied it, re-grant it. The app can't
  deep-link directly to the notification setting, but a permanently-denied
  notification permission triggers an **"Open Settings"** dialog the next
  time the app asks (`_showPermanentlyDeniedDialog` in
  `permissions_screen.dart`). You can also enable it manually via the OS
  notification settings for Ariami.
- Android also declares `android:name="com.ryanheise.audioservice.AudioService"`
  as a `mediaPlayback` foreground service and a
  `MediaButtonReceiver` for hardware media-key events
  (`android/app/src/main/AndroidManifest.xml`). If your device has
  aggressive battery optimization ("Don't optimize"/"Unrestricted" battery
  settings for apps, common on some Android OEM skins), whitelist Ariami
  from battery optimization so the OS doesn't kill the foreground service
  during playback.
- `lib/main.dart` explicitly configures an `AudioSessionConfiguration.music()`
  on startup so the OS grants `AUDIOFOCUS_GAIN` and routes
  hardware/Bluetooth (AVRCP) play/pause/skip button presses to Ariami's media
  session. If that configuration step fails (logged as *"⚠️ Failed to
  configure AudioSession"*), notification controls still work (they fire
  through the app directly), but a Bluetooth headset's own buttons may
  control whichever app *did* get audio focus instead.

### Playback is interrupted by calls, other apps, or headphone unplug

The app configures a standard `AudioSessionConfiguration.music()` audio
session (`lib/main.dart`) so it participates properly in system audio-focus
handling: pausing for calls or other media, and the OS's normal
"unplug-headphones-pauses-audio" behaviour. The app relies on these platform
behaviours rather than overriding them, so if audio doesn't resume after an
interruption, try the in-app play button first (a resume tap re-requests
focus) before assuming something is broken.

---

## Downloads and offline mode

### Downloads fail, pause themselves, or won't finish

Open **Settings → Manage Downloads** (the Downloads screen): failed items are
grouped with a per-song error and both **Retry** and **"Retry all"** actions
(`lib/screens/settings/downloads/widgets/failed_album_card.dart`). A few
concrete behaviours worth knowing:

- **Automatic retry**: a failed download is retried automatically up to 3
  times (`DownloadTask.maxRetries` in `lib/models/download_task.dart`)
  before being marked permanently failed. The retry delay depends on the
  failure: an HTTP 429/503 backs off exponentially (2s, 4s, 8s, and so on,
  capped at 30s, plus jitter); a 500 waits about 3s; anything else (including
  plain timeouts) waits a flat 5s (`_calculateRetryDelay` in
  `lib/services/download/download_manager_transfer_impl.dart`). Some
  failures are terminal and skip retries entirely, with their own message:
  400, 403, 404, and 410 (`_terminalDownloadFailureMessage`).
- **Connection-loss pausing**: if a download fails because of a network
  interruption specifically (timeout, connection error, or no response at
  all) rather than a server error, the app pauses *all* in-flight downloads
  for that reason rather than retrying blindly, with the reason recorded as
  *"Paused because server connection was lost"*
  (`interruptedDownloadPauseMessage` in `lib/services/download/download_helpers.dart`).
  When the connection comes back, a **"Connection Restored"** dialog offers
  **Resume All**; if you'd rather not be asked every time, **Settings →
  Manage Downloads → Auto-Resume On Launch** resumes them automatically
  instead.
- **Background and closure pausing**: on iOS (and on Android when nothing is
  actively downloading), leaving the app pauses in-progress downloads with
  the reason *"Paused because app was interrupted"*, and swiping the app
  away records *"Paused because app was closed"* (`lib/main.dart`,
  `didChangeAppLifecycleState`). A brief backgrounding (notification shade,
  a permission dialog, an app-switcher peek) does *not* touch downloads;
  only a real transition to the backgrounded or detached lifecycle state
  does. On next launch you're prompted **"Continue Downloads?"** if any were
  interrupted.
- **File-size mismatch**: if a completed download's file size doesn't match
  what the server reported, it's treated as a failure ("Downloaded file size
  mismatch: expected X got Y") rather than silently keeping a truncated
  file. This triggers the same retry path above.

If a download is permanently failed after retries, check:

1. Storage space (see below).
2. Whether the song still exists on the server (a rescan can remove it).
3. Whether you're connected at all (Settings → Connection Status).

### Downloads stop when the app is backgrounded (Android)

On Android, backgrounding the app while downloads are active hands active
transfers to a native WorkManager-backed background service
(`lib/services/download/native_download_service.dart`,
`AriamiDownloadNotificationService` in
`android/app/src/main/AndroidManifest.xml`, `foregroundServiceType="dataSync"`),
with a single persistent notification for the whole batch rather than one
per song. If the connection drops while backgrounded, that notification
keeps the process alive for up to **10 minutes**
(`_waitingForConnectionTimeout` in
`lib/services/download/background_download_notifier.dart`) waiting for the
heartbeat to reconnect and resume automatically; past that it gives up and
the interrupted-download recovery flow above takes over on next launch.
This background hand-off is **Android only**: on iOS, backgrounding always
pauses in-progress downloads (`_canContinueDownloadsInBackground` in
`lib/main.dart` gates it to `Platform.isAndroid`).

If downloads reliably stop the moment you leave the app on Android:
whitelist Ariami from battery optimization (same as the background-playback
note above), because an OEM battery manager can kill the WorkManager service
before it gets a chance to start.

### Storage keeps filling up

Two separate stores use storage differently:

- **Downloads** (explicit) are never automatically deleted once they
  complete. Manage them from **Settings → Manage Downloads**: delete a single
  album
  (confirmation: *"Are you sure you want to delete N downloaded songs from
  "<album>"? This action cannot be undone."*) or **Clear All Downloads**
  (*"Are you sure you want to delete all downloaded songs? This action
  cannot be undone."*, the trash icon in the Downloads app bar).
- **Song cache** (automatic, built up from regular streaming) is capped at a
  configurable limit, **500 MB by default**
  (`lib/database/cache_database.dart`), adjustable from 100 to 2000 MB on the
  Downloads screen, and evicted least-recently-used automatically once it's
  exceeded (`lib/services/cache/cache_manager.dart`). You can also clear it
  manually with **Clear Song Cache** in Settings → Manage Downloads
  (*"This will remove cached songs used for streaming. Artwork and explicitly
  downloaded songs will not be affected."*), which never touches your
  explicit downloads or artwork.
- **Artwork cache** is separate from the song cache and doesn't count
  against its size limit (`cache_manager.dart` notes artwork is not
  constrained by the song cache limit). It stays small in practice
  (thumbnails), and the full **Disconnect Server** reset in Settings is what
  clears it, not the song-cache limit or Clear Song Cache.

If storage is tight, check which of the two is actually large: Downloads are
usually the bigger of the two on a phone used for offline listening.

### Offline mode won't turn off / stuck showing "will auto-reconnect"

- **"Manually disconnected"** (the Offline Mode switch in Settings is ON)
  means you turned it on yourself; the app will not attempt any reconnection
  while it's on. Turn the switch off to reconnect.
- **"Connection lost - will auto-reconnect"** is the automatic state
  (`OfflineMode.autoOffline` in `lib/services/offline/offline_playback_service.dart`).
  The app is actively retrying via the heartbeat and connectivity listeners
  described above. If this persists, the underlying reachability problem
  hasn't actually resolved yet, so work through the "Staying connected"
  section; the app's offline handling itself is working as designed.
- Toggling offline mode off calls `reconnectFromManualOffline()`
  (`lib/services/offline/offline_manual_reconnect.dart`). If the reconnect
  attempt fails because the *server* is unreachable, offline mode is
  silently re-enabled, with no error dialog on that path. If it fails
  specifically because of an **auth** problem, offline mode is left *off*
  and you may be routed to sign in again. If toggling off seems to do
  nothing, the server was still unreachable; once offline mode is off, the
  Connection screen's **Retry Connection** button lets you try again
  immediately.

---

## Library and content

### Artwork missing

Album/song artwork requests fall back to a coloured placeholder tile with a
generic icon (`Icons.album` by default; see
`lib/widgets/common/cached_artwork.dart`) whenever the image request errors
out. There's no error dialog, just the generic cover. If artwork is
consistently missing for content that has it on the server:

- Confirm you're actually connected (a broken connection silently fails
  every image load the same way it fails other requests).
- Artwork URLs are built from either an explicit `coverArt` value or a
  deterministic `/api/artwork/{albumId}` endpoint fallback
  (`lib/utils/artwork_url.dart`). A song/album with no `albumId` at all (a
  standalone, unmatched track) has no way to resolve artwork and will always
  show the placeholder.
- Artwork isn't subject to the 500 MB song-cache eviction limit, so it
  shouldn't disappear due to storage pressure. If it vanished after being
  visible before, it's more likely a connection or server-side issue than a
  local cache eviction.

### Library looks out of sync after a server rescan

The library refreshes itself automatically in three ways
(`lib/screens/main/library/library_controller_sync.dart`):

1. **Live WebSocket push**: the server notifies connected clients of library
   updates, playlist-edit changes, artist-image changes, and pin changes as
   they happen, with no manual action needed while connected.
2. **On reconnect**: the moment the connection is restored, the library
   reloads automatically.
3. **Pull-to-refresh**: swipe down on the Library tab to call the same
   `refreshLibrary()` path used on reconnect, or tap **Retry** on the
   library's error state.

If the library still looks stale after all three:

- Confirm you're actually connected (Settings → Connection Status). A stale
  library while *disconnected* is expected: you're seeing the last synced
  snapshot, which is the point of offline mode.
- Pull-to-refresh is the most reliable manual fix and exercises the same
  reconnect and reload path used everywhere else in the app.
- If songs that were removed on the server still appear in a *playlist*
  specifically (not just the library list), that's expected until you run
  **Clean Up Playlists** (see above). Library refresh and playlist cleanup
  are deliberately separate so a rescan never silently deletes playlist
  entries on your behalf.

### Playlists show songs that won't play

This is the same "song no longer on the server" situation covered under
[A song gets skipped automatically](#a-song-gets-skipped-automatically) and
is resolved the same way, with **Settings → Clean Up Playlists**.

---

## Gathering logs and resetting app state

**Logs:** this build prints extensively to the platform log with tagged
prefixes you can filter on: `[Main]` (startup/audio-service init),
`[AriamiAudioHandler]` (playback), `[DownloadManager]` (downloads),
`[CacheManager]` (cache/eviction), `[NetworkMonitorService]`
(connectivity changes), `[OfflinePlaybackService]` (offline-mode
transitions), and `[LibraryController]`. Capture these with:

- **Android:** `adb logcat` while the app is running (filter with
  `adb logcat | grep -i ariami` or one of the tags above), or `flutter run`
  from source for combined Dart and platform output.
- **iOS:** Xcode's device console (Window → Devices and Simulators → select
  device → Open Console), or `flutter run` from source, which is by far the
  easiest way to see the same `[Tag]` prefixed output live.

**Resetting app state:** the most complete reset built into the app is
**Disconnect Server** (available on the Connection settings screen and on
the login screen). Its confirmation is explicit about scope:

> *"This will forget this server, sign you out, and remove downloaded music
> and cached server data from this phone. You will need to scan the QR code
> again to reconnect."*

Under the hood (`lib/utils/app_local_data_reset.dart`,
`clearAllLocalUserData`) this is a genuinely full local reset. It disconnects
from and forgets the server, stops playback and clears the queue, deletes all
downloads and all cache, wipes the local library-sync database, clears all
local playlist data and pending sync actions, resets local listening stats
(account-wide server stats for other devices are *not* touched; only this
device's local copy is cleared), clears the profile image and playlist image
cache, clears saved playback position/state, clears all `SharedPreferences`,
and resets theme/quality/offline settings to defaults. Each step runs
independently, so if one local store fails to clear (a locked file, say), the
rest still run rather than aborting the whole reset. This is the right tool
when the app is in a confusing state and you want to start completely clean,
short of uninstalling.

If you only want to clear caches/downloads without fully forgetting the
server and signing out, use the narrower **Settings → Manage Downloads →
Clear All Downloads** / **Clear Song Cache** actions instead (see
[Storage keeps filling up](#storage-keeps-filling-up)).
