# Troubleshooting Ariami Desktop

This guide is grounded in the actual `ariami_desktop` source: real error
strings, dialog text, exception handling, and file paths, each cited so you
can check it yourself. Every symptom follows **Symptom → Likely cause → How
to confirm → Fix**.

If nothing here solves it, the safe fallback is always the built-in
**Reset Ariami** (see [Resetting and reinstalling](#resetting-and-reinstalling)) —
it never touches your music files.

---

## Table of contents

1. [App won't launch, or crashes on start](#app-wont-launch-or-crashes-on-start)
2. [Server won't start / "no network address available"](#server-wont-start--no-network-address-available)
3. [Port already in use / port fallback messages](#port-already-in-use--port-fallback-messages)
4. [Music folder can't be selected, or the scan finds nothing](#music-folder-cant-be-selected-or-the-scan-finds-nothing)
5. [Scan reports skipped files](#scan-reports-skipped-files)
6. [macOS file-access permissions, sandboxing, and entitlements](#macos-file-access-permissions-sandboxing-and-entitlements)
7. [Windows firewall / SmartScreen](#windows-firewall--smartscreen)
8. [Linux dependencies and missing libraries](#linux-dependencies-and-missing-libraries)
9. [Transcoding is disabled / low-medium quality unavailable](#transcoding-is-disabled--low-medium-quality-unavailable)
10. [Phone can't find or connect to the server](#phone-cant-find-or-connect-to-the-server)
11. [Tailscale shows "not installed" or remote access doesn't work](#tailscale-shows-not-installed-or-remote-access-doesnt-work)
12. [Pairing / QR code / invite code problems](#pairing--qr-code--invite-code-problems)
13. [Owner sign-in, account creation, and password errors](#owner-sign-in-account-creation-and-password-errors)
14. [Can't manage users, kick devices, or change passwords](#cant-manage-users-kick-devices-or-change-passwords)
15. [Login "locked out" / rate limited](#login-locked-out--rate-limited)
16. [Spotify listening-stats import fails](#spotify-listening-stats-import-fails)
17. [System tray icon missing or "Start at Login" fails](#system-tray-icon-missing-or-start-at-login-fails)
18. [Where logs and app data actually live](#where-logs-and-app-data-actually-live)
19. [Resetting and reinstalling](#resetting-and-reinstalling)

---

## App won't launch, or crashes on start

**Symptom:** Double-clicking the app does nothing, or it opens and immediately
closes.

**Likely cause / how to confirm:**

- The window is created via `window_manager` in
  `ariami_desktop/lib/main.dart`. Startup order is: initialize the window
  manager → show the window → **then** initialize the system tray. Tray
  initialization is wrapped in `try/catch` specifically because it "can fail
  when launched from Finder due to path resolution issues" (comment in
  `main.dart`, `_initializeApp()`), and the catch logs but does not stop
  startup — so a *missing tray icon* is not the same failure as *the app not
  launching at all*.
- If the app appears to open then vanish, it may actually have minimized to
  the system tray rather than crashed — check for an Ariami icon in your
  menu bar (macOS) / system tray (Windows) / tray area (Linux). A 3-second
  "startup protection" window in `main.dart`
  (`Future.delayed(const Duration(seconds: 3), ...)`) exists specifically to
  stop *phantom* close events from Finder/Spotlight from hiding the window
  before it's even fully shown — so a hide-to-tray in the first 1–2 seconds
  after launch would be unexpected, but shortly after is normal if you
  clicked the close button (see below).

**Fix:**

- Look for the tray icon before assuming a crash; click it to reopen the
  window (`SystemTrayService.showWindow()` in
  `ariami_desktop/lib/services/system_tray_service.dart`).
- If it's a genuine crash, launch from a terminal to see stderr, e.g. on
  macOS: `/Applications/Ariami\ Desktop.app/Contents/MacOS/Ariami\ Desktop`.
- If the app was previously force-quit while the server was bound to a port,
  that alone will not stop the app from launching — see
  [Port already in use](#port-already-in-use--port-fallback-messages).

## Closing the window doesn't quit the app

**Not a bug** — this is deliberate. `main.dart`'s `onWindowClose()` intercepts
the window-close event and shows a dialog:

> **Close Ariami Desktop?**
> "The server is running. What would you like to do?"
> **Cancel** / **Minimize to Tray** / **Quit**

Choosing **Minimize to Tray** hides the window but keeps the server (and any
connected phones) running; only **Quit** actually stops the server process
(`SystemTrayService.quitApp()`). If you want the app gone entirely, use
**Quit**, not the window's close button plus "Minimize."

## Server won't start / "no network address available"

**Symptom:** The connection/dashboard screen shows:

> "No usable network address was found.
> Please connect to your local network and try again."

(`ariami_desktop/lib/screens/connection_screen.dart`, `_initializeServer()`)
or the dashboard's **Start Server** button shows:

> "Cannot start server: no network address available"

(`ariami_desktop/lib/screens/dashboard/dashboard_server_actions.dart`,
`_toggleServer()`)

**Likely cause:** `DesktopServerLifecycleService.start()`
(`ariami_desktop/lib/services/desktop_server_lifecycle_service.dart`) requires
either a Tailscale IP or a LAN IP before it will start listening — if
**neither** is found, it returns `null` and the caller shows this message. A
LAN IP is looked up by `DesktopTailscaleService.getLanIp()`
(`ariami_desktop/lib/services/desktop_tailscale_service.dart`), which only
recognizes private ranges `10.0.0.0/8`, `172.16.0.0/12`, and `192.168.0.0/16`.

**How to confirm:** You're not connected to Wi-Fi/Ethernet at all, or you're
on a network type the LAN check doesn't recognize (for example, some
corporate VPNs or virtual adapters that don't hand out a standard private
IPv4 address).

**Fix:** Connect to a normal home/office Wi-Fi or Ethernet network, then
retry (the connection screen has a **Retry** button when
`_errorMessage` is set; the dashboard auto-retries the server start every 15
seconds via the periodic timer in
`ariami_desktop/lib/screens/dashboard_screen.dart`'s `initState()`).

## Port already in use / port fallback messages

**Symptom:** A snackbar reads:

> "Port 8080 was in use, so Ariami started on 8081."

**This is not an error** — it's `ServerPortPolicy.formatFallbackMessage()`
(`ariami_core/lib/services/server/server_port_policy.dart`) informing you
the server *did* start, just on a different port than last time. The port
policy tries, in order: the previously-saved port, then 8080, then every port
from 8080–8099 (`ServerPortPolicy.fallbackRangeStart`/`fallbackRangeEnd`), and
persists whichever one actually binds
(`DesktopStateService.setServerPort()`).

**Symptom (genuine failure):** An error box or snackbar shows:

> "Could not bind ports 8080-8099. Free a port or run: ariami_cli start --port 9000"

This is `PortBindingException.message`
(`ariami_core/lib/services/server/http_server_parts/lifecycle_and_config_part.dart`)
— it means *every* port from 8080 through 8099 is unavailable.

**How to confirm:** Another process (possibly a previous, still-running copy
of Ariami, or an unrelated app) is holding all 20 candidate ports — extremely
unlikely unless something is systematically scanning/binding that range.

**Fix:**

- Quit any other running copy of Ariami Desktop or `ariami_cli` first (the
  most common real cause: a previous instance's server never released its
  port because the app was force-quit).
- On macOS/Linux, find what's using a given port: `lsof -i :8080`.
- The suggested `ariami_cli start --port 9000` command line in the error text
  applies to the separate `ariami_cli` package, not the desktop app itself —
  the desktop app has no `--port` flag; it always uses the automatic
  8080–8099 fallback.

## Music folder can't be selected, or the scan finds nothing

**Symptom:** Clicking **Select Folder** on the folder-selection screen shows:

> "Error selecting folder: \<exception text\>"

(`ariami_desktop/lib/screens/folder_selection_screen.dart`, `_selectFolder()`)

**Likely cause / how to confirm:** This wraps the `file_picker` package's
`FilePicker.getDirectoryPath()` call. On macOS this is also where the app
must be granted folder access — see
[macOS file-access permissions](#macos-file-access-permissions-sandboxing-and-entitlements)
below, since a sandboxed macOS build with insufficient entitlements would
surface here as a picker error or as an empty/failed scan afterward.

**Known macOS path quirk (already handled):** if you pick a folder from a
non-boot volume labeled `Macintosh HD`, the raw path returned by the OS picker
can be prefixed with `/Volumes/Macintosh HD`. The app detects and strips this
prefix automatically both at selection time (`folder_selection_screen.dart`)
and again defensively on dashboard load
(`ariami_desktop/lib/screens/dashboard/dashboard_server_actions.dart`,
`_loadData()`, which logs `'[Dashboard] Fixed bad music folder path: ...'`).
If your library still won't scan after this fix was applied, the path is
probably genuinely wrong (folder was moved/renamed/unmounted) rather than a
picker artifact.

**Symptom:** The scan completes but the library shows 0 albums / 0 songs.

**Likely cause:** The folder contains no files with a recognized audio
extension. The scanner's supported extensions
(`ariami_core/lib/services/library/file_scanner.dart`,
`FileScanner.supportedExtensions`) are:

```
.mp3  .m4a  .mp4  .flac  .wav  .aiff  .ogg  .opus  .wma  .aac  .alac
```

Anything else (e.g. `.aif` without the extra `f`, playlists in unsupported
formats, or a folder of non-audio files) will not be picked up.

**Fix:** Point the folder selector at the actual parent directory containing
your albums (sub-folders are scanned recursively), and confirm your files use
one of the extensions above.

## Scan reports skipped files

**Symptom:** After scanning, the scanning screen shows an amber banner:

> "N file(s) could not be read and were skipped"

(`ariami_desktop/lib/screens/scanning_screen.dart`, driven by
`diagnostics.skippedFileCount` from `AriamiHttpServer.libraryManager`)

**This is informational, not an error.** The in-app help text for this step
(`ariami_desktop/lib/onboarding/onboarding_copy.dart`, `OnboardingCopy.scanning`)
explicitly says: *"it usually means a file was unreadable, damaged, or not
really an audio file. The rest of your library is unaffected."*

**How to confirm the real reason (developer-level):** the scanner isolate
(`ariami_core/lib/services/library/library_scanner_isolate.dart`) records a
short reason string per skipped item, among them: `'directory unreadable: ...'`,
`'metadata extraction failed'`, and malformed M3U playlist reasons. These
per-file reasons aren't currently surfaced in the desktop UI beyond the
aggregate count — if you need to know exactly which files failed and why,
check for corrupted/zero-byte files or files with missing read permission in
that folder.

**Symptom (genuine failure, not just skips):** the scanning screen shows a
red error icon and:

> "Could Not Scan Library"
> "Scan failed: \<exception text\>"

with **Try again** and **Choose another folder** buttons
(`scanning_screen.dart`). This happens when the whole scan throws (for
example the folder disappeared mid-scan), not just individual files — per the
in-app help text, *"Only a message that the whole scan failed needs action:
try again or choose a different folder."*

## macOS file-access permissions, sandboxing, and entitlements

Ariami Desktop's macOS build is **not sandboxed**. Both entitlements files
set `com.apple.security.app-sandbox` to `false`:

- `ariami_desktop/macos/Runner/Release.entitlements`
- `ariami_desktop/macos/Runner/DebugProfile.entitlements`

Both also declare:

```xml
<key>com.apple.security.network.server</key><true/>
<key>com.apple.security.files.user-selected.read-only</key><true/>
<key>com.apple.security.files.user-selected.read-write</key><true/>
<key>com.apple.security.files.downloads.read-write</key><true/>
<key>com.apple.security.assets.music.read-write</key><true/>
```

(the Debug/Profile entitlements additionally set
`com.apple.security.cs.allow-jit` for the Dart VM in debug builds)

**What this means in practice:**

- **`com.apple.security.network.server`** — required for the embedded HTTP
  server to accept incoming connections at all. If a future build ever
  removed this, the server would fail to bind/accept connections outright.
- **`com.apple.security.files.user-selected.read-only/read-write`** — because
  the app is not sandboxed, these are less load-bearing than they'd be in a
  sandboxed app, but macOS still shows its own **"Ariami Desktop" would like
  to access files in your Downloads folder / Documents folder / Music
  folder** system permission prompts the first time the app (or the
  `file_picker` folder dialog) touches those specific *protected* locations —
  this is macOS's TCC (privacy) system, separate from sandboxing entitlements.
- **If you denied a folder-access prompt** by accident: go to **System
  Settings → Privacy & Security → Files and Folders** (or **Full Disk
  Access**, depending on macOS version) and enable access for
  **Ariami Desktop**, then restart the app and re-select the music folder.
- **Bundle identifier** for locating the app in privacy settings or
  `defaults`/Console.app logs: `com.example.ariamiDesktop`
  (`ariami_desktop/macos/Runner/Configs/AppInfo.xcconfig`).

**If the app was launched from Finder and the tray failed to initialize:**
this is the specific, already-handled case described in
`main.dart`'s `_initializeApp()` comment — it is caught and logged, and does
not prevent the rest of the app (including the server) from working. It is
cosmetic (no tray icon), not a functional failure.

## Windows firewall / SmartScreen

The repository does not ship a firewall rule installer or a SmartScreen
code-signing certificate configuration for `ariami_desktop`, so:

**Symptom:** On first launch, Windows Defender SmartScreen shows "Windows
protected your PC" / "Unknown publisher."

**Likely cause:** The build is not code-signed with a recognized publisher
certificate (nothing in `ariami_desktop/windows/` configures signing — see
`ariami_desktop/windows/runner/Runner.rc`, which only sets `CompanyName` to
literal `com.example`, not a verified publisher).

**Fix:** Click **More info → Run anyway** if you obtained the build from a
trusted source (the project's own releases).

**Symptom:** Phones on the same network can't reach the server; Windows
Firewall shows a prompt (or silently blocks) when the server starts
listening.

**Likely cause:** The server binds `0.0.0.0` on a TCP port in the 8080–8099
range (see [Port already in use](#port-already-in-use--port-fallback-messages)
above and `ServerPortPolicy` in `ariami_core`), which is a normal inbound
listener from Windows Firewall's perspective and will trigger the standard
"Windows Defender Firewall has blocked some features of this app" prompt the
first time it runs.

**Fix:** When the prompt appears, allow access on **Private networks**
(you generally do not need **Public networks** access, and should leave that
unchecked on an untrusted network). If you dismissed the prompt without
allowing it, add a manual rule: **Windows Defender Firewall → Advanced
Settings → Inbound Rules → New Rule** for the Ariami Desktop executable, TCP,
allow, private profile only — or simply re-trigger the OS prompt by removing
any existing block rule for the app and restarting the server.

## Linux dependencies and missing libraries

**Symptom:** The app fails to launch, or fails to build, with a
GTK-related error.

**Confirmed dependency:** `ariami_desktop/linux/CMakeLists.txt` requires GTK 3
at build time via `pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)`
— the Linux Flutter embedder is GTK-based. If `gtk+-3.0` (via `pkg-config`)
isn't installed, the build itself fails at the CMake configure step, and a
prebuilt binary run on a system without the GTK 3 runtime libraries will fail
to start.

**Fix:** Install GTK 3 development/runtime packages for your distribution
before building, e.g. on Debian/Ubuntu: `sudo apt install libgtk-3-dev`
(and the equivalent runtime package if only running a prebuilt binary).

**Symptom:** Transcoding to low/medium quality is unavailable on Linux, or
the build log shows:

> "Sonic source not found at .../sonic; low/medium transcoding will be disabled."

See [Transcoding is disabled](#transcoding-is-disabled--low-medium-quality-unavailable)
below — on Linux this is driven by the same `ariami_desktop/linux/CMakeLists.txt`,
which builds the bundled Rust "Sonic" transcoder from the sibling `sonic/`
directory (a git submodule) via `cargo build --release`, and simply warns and
skips it if that source isn't present rather than failing the whole build.
Building the Sonic library therefore also requires a working **Rust/Cargo**
toolchain on Linux.

**Raspberry Pi note:** `ariami_desktop/lib/services/desktop_download_limits_service.dart`
and `ariami_core`'s `TranscodeSlotsPolicy`
(`ariami_core/lib/services/transcoding/transcode_slots_policy.dart`) both
special-case Raspberry Pi 5 (detected by reading
`/proc/device-tree/model`, `/sys/firmware/devicetree/base/model`, or
`/proc/cpuinfo` for `"raspberry pi 5"`) with different default download and
transcode-slot limits than generic Linux desktops — if performance seems
different than expected on a Pi, this is why, and it is automatic (no
configuration needed).

## Transcoding is disabled / low-medium quality unavailable

**Symptom:** The console/log shows:

> "Warning: Sonic not available - transcoding will be disabled"

(`ariami_desktop/lib/services/server_initialization_service.dart`,
`_ensureTranscodingService()`, checking `TranscodingService.isSonicAvailable()`)

**Likely cause:** The app resolves the bundled Sonic transcoder native
library path per-platform in
`server_initialization_service.dart`'s `_resolveBundledSonicLibraryPath()`:

- **macOS:** looks for `Frameworks/libsonic_transcoder.dylib` next to the app
  bundle.
- **Linux:** looks for `lib/libsonic_transcoder.so` or
  `libsonic_transcoder.so` next to the executable.
- **Windows:** looks for `sonic_transcoder.dll` next to the executable.

If none of the candidate paths exist, the method returns `null` and
transcoding degrades gracefully rather than crashing the server.

**How to confirm:** This is expected on a from-source Linux build if the
`sonic/` git submodule wasn't fetched before building — the top-level
`ariami_desktop/linux/CMakeLists.txt` explicitly checks
`EXISTS "${SONIC_DIR}/Cargo.toml"` and prints
`"Sonic source not found at ${SONIC_DIR}; low/medium transcoding will be disabled."`
if it's missing, then skips building/bundling it (it does **not** fail the
Linux build).

**Fix:** Make sure the `sonic` submodule is checked out
(`git submodule update --init --recursive` from the repository root) before
building, so `ariami_desktop/linux/CMakeLists.txt` can build and bundle
`libsonic_transcoder.so` alongside the app. Prebuilt official releases should
already include this; this mainly affects from-source builds.

## Phone can't find or connect to the server

**Symptom:** The mobile app can't scan the QR code, or scans it but can't
reach the server.

**Likely causes, in order of frequency:**

1. **Phone and computer are on different networks** (e.g. phone on cellular
   data, or on a guest Wi-Fi network isolated from the main LAN). The LAN
   address advertised (`DesktopTailscaleService.getLanIp()`) is only reachable
   from the *same* local network.
2. **VPN on the phone or computer** routes traffic away from the LAN
   entirely, hiding the server or making the advertised LAN IP unreachable —
   temporarily disable a general-purpose VPN (not Tailscale) if pairing
   fails.
3. **Router client isolation / "AP isolation"** on some routers (common on
   guest networks) blocks device-to-device traffic even on the same SSID.
4. **A firewall is blocking the port** — see the
   [Windows firewall](#windows-firewall--smartscreen) section above (macOS
   and Linux typically don't prompt for a fresh unsigned dev build the same
   way, but a hardened firewall configuration could still block it).
5. **Wrong/stale IP shown.** The dashboard's **Server** tab has a
   **Refresh Addresses** button
   (`ariami_desktop/lib/widgets/dashboard/dashboard_server_tab.dart`,
   backed by `_refreshServerAddresses()` in
   `dashboard_server_actions.dart`) — it explicitly guards with *"Start the
   server before refreshing addresses."* if the server isn't running, and
   otherwise calls `httpServer.refreshAdvertisedEndpoints()` and shows
   *"Server addresses refreshed."* / *"Failed to refresh addresses: \<e\>"*.
   Use it if you've changed networks since the server started.

**Fix:** Put both devices on the same Wi-Fi network with client isolation
disabled, disable any conflicting VPN, hit **Refresh Addresses** on the
dashboard, and re-scan the QR code (each QR includes a fresh, time-limited
registration token — see
[Pairing / QR code / invite code problems](#pairing--qr-code--invite-code-problems)).

## Tailscale shows "not installed" or remote access doesn't work

**Symptom:** The onboarding Tailscale check shows:

> "Tailscale is not installed.
> You can continue with local setup now and install Tailscale later for
> remote access."

(`ariami_desktop/lib/screens/tailscale_check_screen.dart`)

**How detection actually works** (same logic in both
`tailscale_check_screen.dart` and
`ariami_desktop/lib/services/desktop_tailscale_service.dart`): the app checks
a fixed list of common install paths —

```
/opt/homebrew/bin/tailscale        (macOS Homebrew, Apple Silicon)
/usr/local/bin/tailscale           (macOS Homebrew, Intel)
/usr/bin/tailscale                 (Linux)
/usr/sbin/tailscale                (Linux, some distros)
C:\Program Files\Tailscale\tailscale.exe
C:\Program Files (x86)\Tailscale\tailscale.exe
```

then falls back to running `which tailscale` (macOS/Linux) or
`where tailscale` (Windows). **If Tailscale is installed somewhere not on
this list and not on `PATH`**, the app will incorrectly report it as "not
installed" even though it works.

**This is not blocking** — you can always continue with local setup; Tailscale
detection only affects whether the Tailscale IP is advertised for remote
pairing, not whether local/LAN streaming works.

**Symptom:** Tailscale is installed and running, but the desktop app doesn't
pick up its IP.

**How the IP is actually found**
(`DesktopTailscaleService.getTailscaleIp()`): first tries running
`tailscale ip -4` (or `tailscale.exe` on Windows) and validates the result is
in Tailscale's CGNAT range `100.64.0.0/10` (second octet 64–127); if that CLI
call fails or isn't on `PATH`, it falls back to scanning local network
interfaces for an address in that same CGNAT range.

**Fix:** Confirm `tailscale ip -4` succeeds in a terminal on the same
machine; if the CLI isn't on `PATH` but Tailscale is running, the network
interface fallback should still find it — if neither works, check that
Tailscale itself is actually connected (`tailscale status`), not just
installed. Also try **Refresh Addresses** on the dashboard's Server tab after
connecting Tailscale, since the address is cached until refreshed or the
server restarts.

## Pairing / QR code / invite code problems

**Symptom:** QR code area is blank / doesn't render.

**Cause (verified in code):** `ConnectionScreen._generateQRData()`
(`ariami_desktop/lib/screens/connection_screen.dart`) returns an **empty
string** — which `qr_flutter` renders as nothing — whenever the server isn't
started yet, or whenever `getServerInfo()['server']` (the advertised IP) is
null/empty. This matches the "no network address" case above; fix that first.

**Symptom:** Phone says the QR/invite code is invalid or expired.

**Cause:** Registration tokens and invite codes are single-use with a
**10-minute time-to-live**
(`ariami_core/lib/services/server/http_server.dart`,
`_registrationTokenTtl = Duration(minutes: 10)`, shared by both the QR token
and manually-generated invite codes per that file's comments). The
connection screen's invite-code UI
(`_buildManualEntrySection()` in `connection_screen.dart`) shows a live
countdown and, once past expiry, the label switches to *"Expired — generate a
new code"*.

**Fix:** Generate a fresh code (**Generate new code** button) or re-open/
re-scan the connection screen's QR, which mints a new token each time the
screen is shown with a running server.

**Symptom:** "Owner setup is still pending" banner blocks pairing actions.

**Cause:** `connection_screen.dart` shows this exact banner text —
*"Owner setup is still pending. Owner-only actions in Dashboard remain locked
until you create the first account."* — whenever no owner account exists yet
but setup was explicitly skipped
(`DesktopStateService.isOwnerSetupSkipped()`). New phone registrations can
still work without an owner in some flows, but admin actions on the
dashboard require an owner.

**Fix:** Click **Set Up Owner** in that banner, or go through **Owner Setup**
from the dashboard.

## Owner sign-in, account creation, and password errors

**Symptom:** Creating the owner account fails with:

> "Password must be at least 10 characters"

even though the on-screen form only required 4.

**This is a real, verified inconsistency between client-side and
server-side validation** — worth knowing about explicitly:

- The owner-setup form's own validator
  (`ariami_desktop/lib/screens/owner_setup_screen.dart`, the password
  `TextFormField`'s `validator`) only enforces **4 characters minimum**:
  `'Password must be at least 4 characters.'`
- But the account is actually created via `AuthService().register(...)`
  in `ariami_core`
  (`ariami_core/lib/services/auth/auth_service.dart`), whose real minimum is
  `minPasswordLength = 10`. If the password is 4–9 characters, the form
  passes client-side validation, the request is sent, and it throws an
  `AuthException` with message `'Password must be at least 10 characters'`,
  which `owner_setup_screen.dart`'s `catch (e)` block surfaces verbatim as
  the inline error under the form.
- The same real minimum (10 characters) applies to
  `/api/admin/create-user` and `/api/admin/change-password` requests sent
  from the dashboard's **Create User** / **Change Password** dialogs
  (`ariami_desktop/lib/widgets/create_user_dialog.dart`,
  `ariami_desktop/lib/widgets/change_password_dialog.dart`), which have **no**
  client-side minimum-length check at all — so a too-short password there
  will look like it's accepted by the dialog, then fail with the same server
  message shown in a red snackbar.

**Fix:** Use a password of **10 characters or more** for every account
(owner or otherwise), regardless of what the form itself claims is required.

**Symptom:** "That username is already taken." when creating the owner or a
new user.

**Cause:** `UserExistsException` from `ariami_core`'s user store
(`ariami_core/lib/services/auth/user_store.dart`) — the username already
exists in `users.json`. Owner setup's screen maps this specific exception to
that friendlier message; the dashboard's Create User dialog instead shows
whatever `errorMessage` the server API returned.

**Symptom:** "Owner sign-in failed" / "Invalid username or password" when
using **Owner Sign-In** for admin actions (kick device, change password,
etc.).

**Cause:** The dashboard's admin API client
(`ariami_desktop/lib/services/dashboard_admin_api_service.dart`,
`ensureAdminSessionToken()`) prompts for owner credentials
(`admin_credentials_dialog.dart`) and calls `/api/auth/login`; on failure it
surfaces `response.errorMessage` (server-provided) or a generic
`'Owner sign-in failed'` if the response had no message. The real server-side
message for wrong credentials is `'Invalid username or password'`
(`ariami_core/lib/services/auth/auth_service.dart`, `login()`).

**Forgot the owner password?** The **"Forgot owner password?"** link on the
Owner Sign-In dialog itself
(`ariami_desktop/lib/widgets/admin_credentials_dialog.dart`,
`_showOwnerRecoveryDialog()`) opens a recovery dialog that tells you, in the
app's own words: *"If you forgot the Owner password, stop Ariami and remove
local auth files. Then restart and create a new Owner account,"* and prints
the exact `rm -f` commands for **your** installation's real
`sessions.json` / `users.json` paths (it reads them live from
`DesktopStateService.getSessionsFilePath()` /
`getUsersFilePath()`). It also points to this repository's root `RESET.md`
for a full reset guide. Note this deletes **every** account on the server,
not just the owner's — the next person to register becomes the new owner.

## Can't manage users, kick devices, or change passwords

**Symptom:** Snackbar reads: *"Set up the Owner account first to manage
connected devices."* / *"...to add users."* / *"...to change passwords."* /
*"...to manage users."*

**Cause:** Every admin action in
`ariami_desktop/lib/screens/dashboard/dashboard_user_actions.dart`
(`_kickClient`, `_promptCreateUser`, `_promptChangePassword`, `_deleteUser`)
checks `_hasOwnerAccount` first and refuses with one of these exact messages,
then opens Owner Setup for you automatically.

**Fix:** Complete Owner Setup (from the banner's action button, or Dashboard
→ Overview → **Set Up Owner Account**).

**Symptom:** Kick/create/change-password/delete actions fail with a red
snackbar showing a specific server message (e.g. *"Failed to disconnect
device"*, *"Failed to create user"*, *"Failed to change password"*, *"Failed
to delete user"*).

**Cause:** These are the **fallback** messages used only when the server's
JSON error response had no `error.message` field
(`ariami_desktop/lib/models/dashboard_http_response.dart`,
`errorMessage` getter) — if you see one of these generic strings rather than
a more specific message, the underlying HTTP call to
`/api/admin/kick-client`, `/api/admin/create-user`,
`/api/admin/change-password`, or `/api/admin/delete-user` failed without
returning a structured reason (e.g. a network/timeout issue talking to its
own embedded server, which would be unusual since it's in-process).

**Symptom:** Admin session silently stops working after a while, and the
next kick/create/etc. action re-prompts for owner credentials.

**Expected behavior:** `DashboardAdminApiService.sendAdminHeartbeat()`
pings `/api/me` every 20 seconds
(`ariami_desktop/lib/screens/dashboard_screen.dart`, `_adminHeartbeatTimer`);
on a `401` it clears the cached session token and unregisters the dashboard's
own admin "device" from the connection manager, then calls
`onSessionInvalidated` to refresh the dashboard's data. The next
owner-authenticated action will simply prompt you to sign in again
(`ensureAdminSessionToken(forcePrompt: true)` is retried automatically once
inside `sendAuthenticatedRequest()`).

## Login "locked out" / rate limited

**Symptom:** *"Too many failed login attempts. Try again in N minute(s)."*

**Cause:** `ariami_core`'s `AuthService.login()`
(`ariami_core/lib/services/auth/auth_service.dart`) locks out a
username+key combination after **5 failed attempts**
(`maxLoginAttempts = 5`) for a cooldown of **15 minutes**
(`rateLimitCooldown = Duration(minutes: 15)`). This applies to owner sign-in
from the dashboard exactly the same as to phone logins, since both go through
the same embedded auth service.

**Fix:** Wait out the cooldown (the message tells you exactly how long is
left), or confirm you have the right username/password before retrying —
repeated wrong attempts extend nothing further, but each attempt is still
tracked and won't reset until the cooldown window fully elapses since the
last failure.

## Spotify listening-stats import fails

The **Import Spotify listening stats** button on the dashboard's Overview
tab (`ariami_desktop/lib/widgets/dashboard/dashboard_overview_tab.dart`) is
only enabled when there's an owner account, the server is running, and the
library has at least one song
(`ariami_desktop/lib/screens/dashboard_screen.dart`, the
`onImportSpotifyStats` callback's condition). If the button is disabled/greyed
out, one of those three is missing.

Real failure messages, from
`ariami_desktop/lib/services/spotify_import_service.dart`:

| Message | Cause |
| --- | --- |
| "No Spotify history files were found. Choose the folder containing Streaming_History_Audio_\*.json files." | The selected folder has no files matching that exact naming pattern (`_isAudioHistoryFile`), which is what Spotify's "Extended streaming history" export uses. |
| "\<filename\> is not valid JSON." | One of the matched files failed to parse as JSON — likely corrupted or manually edited. |
| "\<filename\> does not contain a Spotify history list." | The file parsed as JSON but wasn't a JSON array/list, i.e. not the expected export format. |
| "The Spotify history files in this folder are empty." | Files matched and parsed, but contained zero records combined. |
| "Your Ariami library is empty. Scan the library before importing Spotify stats." | No scanned library to match Spotify tracks against. |
| "No eligible audio plays were found in this Spotify export." | Matching ran, but nothing in the export corresponded to a playable audio event. |
| "The signed-in owner changed. Start the import again." | Between analyzing and uploading, `/api/me` returned a different username than the one the preview was built for (thrown from `upload()`). |
| "The owner account could not be confirmed. Sign in again and restart the import." | `/api/me` failed or returned no username while confirming identity. |
| "Update Ariami before importing Spotify stats." | The upload endpoint (`/api/v2/listening/events`) returned HTTP 404 — the running server is too old to support this feature. |
| "Upload failed on batch N. Plays already uploaded are saved; retrying is safe." | A batch upload failed for another reason; the message explicitly documents that retrying is safe because earlier successful batches are not re-sent as duplicates. |

**Fix for the common case:** point the import at the folder from Spotify's
**Extended Streaming History** data export (not the "Account Data" export,
which uses different filenames), make sure your Ariami library has been
scanned first, and retry on transient upload failures — the tool is designed
so retries don't double-count history.

## System tray icon missing or "Start at Login" fails

**Symptom:** No tray icon appears at all, but the app otherwise works fine
(server runs, dashboard works).

**Cause:** `SystemTrayService.initialize()`
(`ariami_desktop/lib/services/system_tray_service.dart`) looks for the tray
icon file at a platform- and build-mode-specific path computed relative to
`Platform.resolvedExecutable` (different logic for debug vs. release, and for
macOS/Windows/Linux). If the icon file isn't found at the computed path, it
logs `'Warning: Tray icon not found at: <path>'` and continues **without** a
tray icon rather than failing — this is deliberate
(*"Continue without tray icon - app will still work"*). It's most likely to
happen with a non-standard build layout (e.g. running a manually copied
executable outside its normal bundle structure).

**Fix:** Reinstall/rebuild the app normally so the executable sits at its
expected bundle-relative location; this is cosmetic only and doesn't affect
server functionality.

**Symptom:** Toggling **Start at Login** on the Server tab shows:

> "Could not enable start at login. Please try again."
> (or "Could not disable start at login. Please try again.")

(`ariami_desktop/lib/widgets/autostart_card.dart`)

**Cause:** This wraps the `launch_at_startup` package
(`ariami_desktop/lib/services/autostart_service.dart`), which uses a
different native mechanism per platform:

- **macOS:** `SMAppService` (Login Items, requires macOS 13+)
- **Windows:** the `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
  registry key
- **Linux:** a `~/.config/autostart/<app>.desktop` file

Failures are typically OS permission issues (e.g. a restricted/managed
profile blocking Login Items or registry writes) rather than an Ariami-side
bug. `AutostartService` isn't shown at all (`AutostartCard` returns an empty
widget) on platforms where `Platform.isMacOS || Platform.isWindows ||
Platform.isLinux` is false — not a realistic case for this app's supported
targets, but documented for completeness.

**Fix:** Retry once; if it persists, check OS-level permissions for
login-item/startup management (e.g. macOS **System Settings → General →
Login Items**, or run as a non-restricted Windows user account).

## Where logs and app data actually live

Ariami Desktop has no dedicated log file of its own — diagnostic messages go
to **stdout/stderr** via `print()` calls throughout the services (e.g.
`[ServerInit]`, `[Dashboard]`, `[Tray]`, `[Main]`, `[Window]`, `[Reset]`
prefixes), visible when the app is launched from a terminal, or in the OS's
own console tooling (Console.app on macOS, `journalctl`/terminal on Linux,
Event Viewer is not used — nothing in this codebase writes to it — so a
terminal launch is the only reliable way to see these on Windows too).

**Persistent app data**, from `DesktopStateService`
(`ariami_desktop/lib/services/desktop_state_service.dart`), lives in the
platform's `path_provider` "application support directory":

| File / directory | Purpose | Getter |
| --- | --- | --- |
| `users.json` | Registered accounts | `getUsersFilePath()` |
| `sessions.json` | Active login sessions | `getSessionsFilePath()` |
| `catalog.db` | SQLite catalog database | `getCatalogDbFilePath()` |
| `metadata_cache.json` | Cached scanned-file metadata (speeds up re-scans) | `getMetadataCacheFilePath()` |
| `artwork_cache/` | Processed cover art cache | `getArtworkCacheDirPath()` |
| `transcoded_cache/` | Transcoded audio cache | `getTranscodedCacheDirPath()` |

Setup/config preferences (`setup_completed`, `music_folder_path`,
`server_port`, `transcode_slots`, `owner_setup_skipped`,
`tv_account_picker_enabled`) are stored via `shared_preferences`, which on
macOS lands in `NSUserDefaults` under bundle id `com.example.ariamiDesktop`
with Flutter's `flutter.` key prefix (e.g. `flutter.setup_completed`) — see
the repository root `RESET.md` for the exact `defaults` commands and
per-platform locations of the application-support directory. `RESET.md` also
covers where a **sandboxed** macOS build's preferences would live
(`~/Library/Containers/<BUNDLE_ID>/...`), for completeness, even though the
current build (per the entitlements above) is not sandboxed.

## Resetting and reinstalling

The built-in **Reset Ariami** dialog is the supported way to start over — it
is on the dashboard's **Server tab → Danger Zone**
(`ariami_desktop/lib/widgets/reset_ariami_dialog.dart`, wired up in
`ariami_desktop/lib/screens/dashboard/dashboard_server_actions.dart`,
`_resetAriami()`). It requires literally typing `RESET` to confirm and offers
two scopes:

- **Reset setup only** — *"Clears server config, pairing state, remembered
  addresses, and setup progress. Keeps your music files."* Implemented by
  `DesktopStateService.clearSetupPreferences()`
  (`ariami_desktop/lib/services/desktop_state_service.dart`): removes
  `setup_completed`, `owner_setup_skipped`, `server_port`,
  `music_folder_path`, and `transcode_slots` preferences. Leaves the catalog
  database, accounts, and caches intact.
- **Factory reset Ariami** — *"Clears Ariami database, users, sessions,
  stats, playlists, cache, and setup state. Keeps your original music
  files."* Implemented by `DesktopResetService.reset()`
  (`ariami_desktop/lib/services/desktop_reset_service.dart`): stops the
  server first (to release the catalog DB file handle), clears **every**
  preference, then deletes `metadata_cache.json`, `users.json`,
  `sessions.json`, `catalog.db`, `artwork_cache/`, and `transcoded_cache/` —
  passing your current music folder path as an explicit guard so it is never
  touched. It also disables **Start at Login** if it was enabled
  (`AutostartService.setEnabled(false)`).

Both scopes always show a confirmation dialog afterward
(*"Reset complete"* / *"Reset failed"*) and, on success, **quit the app**
deliberately — *"Ariami will now close — reopen it to start fresh"* — so
there's no stale in-memory catalog or open database handle left around; you
must relaunch the app yourself.

**If the reset dialog itself fails** (shows *"Reset failed"* with an
exception message), the dialog lists exactly which file paths could not be
removed (`ResetResult.failures`), each shown as `• <path>` — check filesystem
permissions on those specific paths.

**For a clean reinstall**, or if the in-app reset is unavailable for some
reason, the repository root `RESET.md` documents the manual equivalent:
quitting the app, deleting the `NSUserDefaults`/registry preferences for
`com.example.ariamiDesktop`, and removing `sessions.json`/`users.json` from
the application-support directory by hand — with the same guarantee that your
music folder is never touched by any of these steps. `RESET.md` also notes
that mobile-client session data lives on the device itself (secure storage)
and isn't affected by any desktop-side reset — use in-app logout or clear app
data on the phone separately if needed.
