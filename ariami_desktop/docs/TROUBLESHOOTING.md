# Troubleshooting Ariami Desktop

This guide is grounded in the actual `ariami_desktop` source: real error
strings, dialog text, exception handling, and file paths, each cited so you
can check it yourself. Most symptoms follow **Symptom → Likely cause → How to
confirm → Fix**.

If nothing here solves it, the safe fallback is the built-in **Reset Ariami**
(see [Resetting and reinstalling](#resetting-and-reinstalling)). It never
touches your music files.

---

## Table of contents

1. [App won't launch, or crashes on start](#app-wont-launch-or-crashes-on-start)
2. [Closing the window doesn't quit the app](#closing-the-window-doesnt-quit-the-app)
3. [Server won't start / "no network address available"](#server-wont-start--no-network-address-available)
4. [Port already in use / port fallback messages](#port-already-in-use--port-fallback-messages)
5. [Music folder can't be selected, or the scan finds nothing](#music-folder-cant-be-selected-or-the-scan-finds-nothing)
6. [Scan reports skipped files](#scan-reports-skipped-files)
7. [macOS file-access permissions, sandboxing, and entitlements](#macos-file-access-permissions-sandboxing-and-entitlements)
8. [Windows firewall / SmartScreen](#windows-firewall--smartscreen)
9. [Linux dependencies and missing libraries](#linux-dependencies-and-missing-libraries)
10. [Transcoding is disabled / low-medium quality unavailable](#transcoding-is-disabled--low-medium-quality-unavailable)
11. [Phone can't find or connect to the server](#phone-cant-find-or-connect-to-the-server)
12. [Tailscale shows "not installed" or remote access doesn't work](#tailscale-shows-not-installed-or-remote-access-doesnt-work)
13. [Pairing / QR code / invite code problems](#pairing--qr-code--invite-code-problems)
14. [Owner sign-in, account creation, and password errors](#owner-sign-in-account-creation-and-password-errors)
15. [Can't manage users, kick devices, or change passwords](#cant-manage-users-kick-devices-or-change-passwords)
16. [Login "locked out" / rate limited](#login-locked-out--rate-limited)
17. [Spotify listening-stats import fails](#spotify-listening-stats-import-fails)
18. [System tray icon missing or "Start at Login" fails](#system-tray-icon-missing-or-start-at-login-fails)
19. [Where logs and app data actually live](#where-logs-and-app-data-actually-live)
20. [Resetting and reinstalling](#resetting-and-reinstalling)

---

## App won't launch, or crashes on start

**Symptom:** Double-clicking the app does nothing, or it opens and immediately
closes.

**Likely cause / how to confirm:**

- `ariami_desktop/lib/main.dart` creates the window first: initialise
  `window_manager`, show and focus the window, then call `runApp`. The system
  tray is set up later, inside `_initializeApp()`, and that call sits in a
  `try/catch` because it "can fail when launched from Finder due to path
  resolution issues" (comment in `main.dart`). The catch logs
  `[Main] Warning: Failed to initialize system tray: ...` and startup carries
  on, so a missing tray icon is a different failure from the app not
  launching.
- If the app appears to open then vanish, it may have minimised to the tray
  instead. Look for the Ariami icon in your menu bar (macOS), system tray
  (Windows) or tray area (Linux).
- The first three seconds after launch are a "startup protection" window in
  `main.dart` (`Future.delayed(const Duration(seconds: 3), ...)`). During it,
  `onWindowClose()` ignores close events, which stops phantom events from
  Finder/Spotlight from hiding the window before it has finished appearing.

**Fix:**

- Click the tray icon to reopen the window (`SystemTrayService.showWindow()`
  in `ariami_desktop/lib/services/system_tray_service.dart`).
- For a genuine crash, launch from a terminal to read stderr. On macOS the
  shipped build is `Ariami-Desktop.app`:
  `/Applications/Ariami-Desktop.app/Contents/MacOS/Ariami-Desktop`.
- A force-quit while the server was bound to a port will not stop the app
  from launching. See
  [Port already in use](#port-already-in-use--port-fallback-messages) for
  that separate case.

## Closing the window doesn't quit the app

This is deliberate. `main.dart`'s `onWindowClose()` intercepts the close
event and shows a dialog:

> **Close Ariami Desktop?**
> "The server is running. What would you like to do?"
> **Cancel** / **Minimize to Tray** / **Quit**

**Minimize to Tray** hides the window and keeps the server running, so
connected phones stay connected. **Quit** stops the HTTP server
(`SystemTrayService.quitApp()`) and exits the process. Choose **Quit** when
you want the app gone.

## Server won't start / "no network address available"

**Symptom:** The connection screen shows:

> "No usable network address was found.
> Please connect to your local network and try again."

**Likely cause:** `_initializeServer()` in
`ariami_desktop/lib/screens/connection_screen.dart` asks
`DesktopTailscaleService` for a Tailscale IP and a LAN IP. When both come
back null, it sets that message and shows a **Retry** button. `getLanIp()`
(`ariami_desktop/lib/services/desktop_tailscale_service.dart`) accepts
addresses in `10.0.0.0/8`, `172.16.0.0/12` and `192.168.0.0/16`, and skips
loopback addresses and Tailscale's CGNAT range.

**Symptom (dashboard):** The dashboard's Start Server button shows:

> "Cannot start server: no network address available"

**Likely cause:** `_toggleServer()` in
`ariami_desktop/lib/screens/dashboard/dashboard_server_actions.dart` starts
the server through `DesktopServerLifecycleService.start()`
(`ariami_desktop/lib/services/desktop_server_lifecycle_service.dart`). That
method returns null when neither a Tailscale nor a LAN address exists.

**How to confirm:** The machine isn't on Wi-Fi or Ethernet, or the network
only hands out addresses the LAN check doesn't recognise. Some corporate VPNs
and virtual adapters fall into that second group.

**Fix:** Connect to a normal home or office network and retry. On the
connection screen press **Retry**; the dashboard checks again every 15
seconds while it is open (the periodic timer in
`ariami_desktop/lib/screens/dashboard_screen.dart` calls `_autoStartServer()`).

## Port already in use / port fallback messages

**Symptom:** A snackbar reads:

> "Port 8080 was in use, so Ariami started on 8081."

The server did start; only the port changed. `ServerPortPolicy` in
`ariami_core/lib/services/server/server_port_policy.dart` builds the message,
and `startListeningServer()` in
`ariami_desktop/lib/services/server_initialization_service.dart` saves the
port that actually bound through `DesktopStateService.setServerPort()`.

The candidate order is the previously saved port, then 8080, then every port
from 8080 to 8099 (`ServerPortPolicy.buildCandidates()`).

**Symptom (genuine failure):** An error appears reading:

> "Could not bind ports 8080-8099. Free a port or run: ariami_cli start --port 9000"

This is `PortBindingException.message`
(`ariami_core/lib/services/server/http_server_parts/lifecycle_and_config_part.dart`),
and it means every candidate port was unavailable.

**Fix:**

- Quit any other running copy of Ariami Desktop or `ariami_cli` first. The
  usual real cause is a previous instance that still holds its port.
- On macOS or Linux, check what owns a port with `lsof -i :8080`.
- The suggested `ariami_cli start --port 9000` command applies to the
  separate CLI package. The desktop app takes no `--port` flag; it always
  uses the automatic 8080 to 8099 fallback.

## Music folder can't be selected, or the scan finds nothing

**Symptom:** Clicking **Select Folder** on the folder-selection screen shows:

> "Error selecting folder: \<exception text\>"

`_selectFolder()` in `ariami_desktop/lib/screens/folder_selection_screen.dart`
wraps the `file_picker` package's `FilePicker.getDirectoryPath()` call. On
macOS this is also where a denied folder-access prompt can surface; see
[macOS file-access permissions](#macos-file-access-permissions-sandboxing-and-entitlements)
below.

**Known macOS path quirk (already handled):** picking a folder from a non-boot
volume labelled `Macintosh HD` can return a path prefixed with
`/Volumes/Macintosh HD`. The app strips that prefix when you select the
folder, then checks again on dashboard load (`_loadData()` in
`ariami_desktop/lib/screens/dashboard/dashboard_server_actions.dart`, which
logs `[Dashboard] Fixed bad music folder path: ...`). If a library still
won't scan after that, the path itself is probably wrong: the folder was
moved, renamed, or unmounted.

**Symptom:** The scan completes but the library shows 0 albums and 0 songs.

**Likely cause:** The folder contains no files with a recognised audio
extension. `FileScanner.supportedExtensions`
(`ariami_core/lib/services/library/file_scanner.dart`) is:

```
.mp3  .m4a  .mp4  .flac  .wav  .aiff  .ogg  .opus  .wma  .aac  .alac
```

**Fix:** Point the picker at the folder that contains your albums.
Sub-folders are scanned recursively, so the parent directory works. Check
that your files use one of the extensions above.

## Scan reports skipped files

**Symptom:** After scanning, the scanning screen shows an amber banner:

> "N file(s) could not be read and were skipped"

(`ariami_desktop/lib/screens/scanning_screen.dart`, driven by
`diagnostics.skippedFileCount` from `AriamiHttpServer.libraryManager`)

This is informational. The in-app help text (`OnboardingCopy.scanning` in
`ariami_desktop/lib/onboarding/onboarding_copy.dart`) explains: "it usually
means a file was unreadable, damaged, or not really an audio file. The rest
of your library is unaffected."

**How to confirm the reason (developer level):** the scanner isolate
(`ariami_core/lib/services/library/library_scanner_isolate.dart`) records a
reason string per skipped item. Examples include `directory unreadable: ...`,
`metadata extraction failed`, `M3U playlist ...` and
`M3U entry not found in library (...)`. The desktop UI only shows the
aggregate count, so if you need the exact files, look for corrupted or
zero-byte files and files without read permission.

**Symptom (genuine failure):** The scanning screen shows a red error icon
and:

> "Could Not Scan Library"
> "Scan failed: \<exception text\>"

with **Try again** and **Choose another folder** buttons
(`ariami_desktop/lib/screens/scanning_screen.dart`). This means the whole
scan threw, for example
because the folder disappeared mid-scan. Per the in-app help text: "Only a
message that the whole scan failed needs action: try again or choose a
different folder."

## macOS file-access permissions, sandboxing, and entitlements

The macOS build runs outside the App Sandbox. Both entitlements files set
`com.apple.security.app-sandbox` to `false`:

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

The Debug/Profile entitlements additionally set
`com.apple.security.cs.allow-jit` for the Dart VM in debug builds.

**What this means in practice:**

- `com.apple.security.network.server` lets the embedded HTTP server accept
  incoming connections. Without it, the server could not bind or accept
  clients.
- Because the app is not sandboxed, the file-access entitlements matter less
  than they would in a sandboxed app. macOS still runs its own TCC privacy
  prompts the first time the app or the `file_picker` dialog touches
  protected locations such as Downloads, Documents or Music. You may see
  "Ariami Desktop" would like to access files in one of those folders.
- If you denied a prompt by accident, open **System Settings → Privacy &
  Security → Files and Folders** (or **Full Disk Access** on some macOS
  versions), enable access for **Ariami Desktop**, then restart the app and
  re-select the music folder.
- The bundle identifier, useful in privacy settings and Console.app, is
  `com.example.ariamiDesktop`
  (`ariami_desktop/macos/Runner/Configs/AppInfo.xcconfig`).

**Gatekeeper and code signing:** the macOS target builds with ad-hoc signing
(`CODE_SIGN_IDENTITY = "-"` in
`ariami_desktop/macos/Runner.xcodeproj/project.pbxproj`), and
`.github/workflows/release.yml` builds the DMG with
`flutter build macos --release` and no notarisation step. macOS may therefore
warn that it cannot check the app for malicious software on first launch.
Control-click the app and choose **Open**, or clear the quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/Ariami-Desktop.app
```

**If a Finder launch leaves the tray uninitialised:** this is the handled
case from `main.dart`'s `_initializeApp()` comment. The failure is caught and
logged, the server still works, and the only effect is the missing tray icon.

## Windows firewall / SmartScreen

The repository ships no firewall rule installer and no code-signing
certificate configuration for `ariami_desktop`.

**Symptom:** On first launch, Windows Defender SmartScreen shows "Windows
protected your PC" or "Unknown publisher."

**Likely cause:** The build is not signed with a recognised publisher
certificate. `ariami_desktop/windows/runner/Runner.rc` sets `CompanyName` to
the literal `com.example`, not a verified publisher.

**Fix:** If you downloaded the build from the project's own releases, click
**More info → Run anyway**.

**Symptom:** Phones on the same network can't reach the server, and Windows
Firewall shows a prompt or silently blocks it.

**Likely cause:** The server binds `0.0.0.0` on a TCP port in the 8080 to
8099 range (see
[Port already in use](#port-already-in-use--port-fallback-messages) and
`ServerPortPolicy` in `ariami_core`). Windows Firewall treats that as a
normal inbound listener and shows its "Windows Defender Firewall has blocked
some features of this app" prompt the first time it runs.

**Fix:** Allow access for **Private networks** when the prompt appears
(leave **Public networks** unchecked on untrusted networks). If you dismissed
the prompt, add a manual rule under **Windows Defender Firewall → Advanced
Settings → Inbound Rules → New Rule**: the Ariami Desktop executable, TCP,
allow, private profile. Removing any existing block rule for the app and
restarting the server also re-triggers the prompt.

## Linux dependencies and missing libraries

**Symptom:** The app fails to launch or build with a GTK-related error.

`ariami_desktop/linux/CMakeLists.txt` requires GTK 3 at build time via
`pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)`; the Linux Flutter
embedder is GTK-based. Without `gtk+-3.0` visible to `pkg-config`, CMake
configuration fails. A prebuilt binary on a system missing the GTK 3 runtime
libraries fails to start.

**Fix:** Install the GTK 3 development packages before building. On
Debian/Ubuntu:

```bash
sudo apt install libgtk-3-dev
```

If you only run a prebuilt binary, install the GTK 3 runtime package instead.

**Symptom:** Transcoding to low/medium quality is unavailable on Linux, or
the build log shows:

> "Sonic source not found at .../sonic; low/medium transcoding will be disabled."

`ariami_desktop/linux/CMakeLists.txt` builds the bundled Rust Sonic
transcoder from the sibling `sonic/` directory (a git submodule) with
`cargo build --release`, and warns and skips it when the source is absent
instead of failing the build. Building Sonic also needs a working
**Rust/Cargo** toolchain. See
[Transcoding is disabled](#transcoding-is-disabled--low-medium-quality-unavailable)
for the runtime side.

**Raspberry Pi note:**
`ariami_desktop/lib/services/desktop_download_limits_service.dart` and
`TranscodeSlotsPolicy`
(`ariami_core/lib/services/transcoding/transcode_slots_policy.dart`) detect Pi
models by reading `/proc/device-tree/model`,
`/sys/firmware/devicetree/base/model`, or `/proc/cpuinfo`. A Pi 5 gets its
own per-user download concurrency (6 instead of 3) and transcode slots (5
instead of the desktop default of 6). A Pi 4 gets 4 slots, and a Pi 3 or
older board gets 3. All of this is automatic; nothing needs configuring.

## Transcoding is disabled / low-medium quality unavailable

**Symptom:** The console or log shows:

> "Warning: Sonic not available - transcoding will be disabled"

`_ensureTranscodingService()` in
`ariami_desktop/lib/services/server_initialization_service.dart` logs this
from `[ServerInit]` after checking `TranscodingService.isSonicAvailable()`.

**Likely cause:** The app resolves the bundled Sonic native library in
`_resolveBundledSonicLibraryPath()` and finds nothing:

- **macOS:** `<exeDir>/../../Frameworks/libsonic_transcoder.dylib` or
  `<exeDir>/../../../Frameworks/libsonic_transcoder.dylib`, which land in the
  app bundle's `Contents/Frameworks` folder.
- **Linux:** `lib/libsonic_transcoder.so` or `libsonic_transcoder.so` next to
  the executable.
- **Windows:** `sonic_transcoder.dll` next to the executable.

When none of the candidates exists, the method returns null and transcoding
degrades gracefully; the server keeps running.

**How to confirm:** This is expected on a from-source build where the
`sonic/` submodule wasn't fetched. Linux and Windows builds print the warning
above and continue. The macOS build script is stricter: it fails the build
with `error: Sonic source not found at ...`, and it also checks that `cargo`
is installed.

**Fix:** Fetch the submodule before building, from the repository root:

```bash
git submodule update --init --recursive
```

Official release builds check out submodules and bundle the library, so this
mainly affects builds from source.

## Phone can't find or connect to the server

**Symptom:** The mobile app can't scan the QR code, or scans it but can't
reach the server.

**Likely causes, in order of frequency:**

1. **Phone and computer on different networks.** The advertised LAN address
   (`DesktopTailscaleService.getLanIp()`) is reachable only from the same
   local network. Cellular data or a guest Wi-Fi network counts as a
   different network.
2. **A VPN on either device** routes traffic away from the LAN. Temporarily
   disable a general-purpose VPN (not Tailscale) if pairing fails.
3. **Router client isolation** (also called AP isolation) blocks
   device-to-device traffic, even on the same SSID. It is common on guest
   networks.
4. **A firewall is blocking the port.** See
   [Windows firewall](#windows-firewall--smartscreen). macOS and Linux
   usually don't prompt for a locally built app, but a hardened firewall
   configuration can still block it.
5. **The shown IP is stale.** The dashboard's **Server** tab has a
   **Refresh Addresses** button
   (`ariami_desktop/lib/widgets/dashboard/dashboard_server_tab.dart`, backed
   by `_refreshServerAddresses()` in
   `ariami_desktop/lib/screens/dashboard/dashboard_server_actions.dart`). It
   warns "Start the server before refreshing addresses." when the server is
   down, and on success calls `httpServer.refreshAdvertisedEndpoints()` and
   shows "Server addresses refreshed."

**Fix:** Put both devices on the same Wi-Fi network with client isolation
off, disable any conflicting VPN, press **Refresh Addresses**, and rescan the
QR code. Each QR carries a fresh, time-limited registration token (see
[Pairing / QR code / invite code problems](#pairing--qr-code--invite-code-problems)).

## Tailscale shows "not installed" or remote access doesn't work

**Symptom:** The onboarding Tailscale check shows:

> "Tailscale is not installed.
> You can continue with local setup now and install Tailscale later for remote access."

**How detection works:** `ariami_desktop/lib/screens/tailscale_check_screen.dart`
and `ariami_desktop/lib/services/desktop_tailscale_service.dart` share the
same logic. They check a fixed list of install paths:

```
/opt/homebrew/bin/tailscale        (macOS Homebrew, Apple Silicon)
/usr/local/bin/tailscale           (macOS Homebrew, Intel)
/usr/bin/tailscale                 (Linux)
/usr/sbin/tailscale                (Linux, some distributions)
C:\Program Files\Tailscale\tailscale.exe
C:\Program Files (x86)\Tailscale\tailscale.exe
```

Then they fall back to `which tailscale` (macOS/Linux) or `where tailscale`
(Windows). If Tailscale lives somewhere else and isn't on `PATH`, the app
reports it as not installed even though it works.

**This is informational.** Local setup always works without Tailscale; the
check only decides whether a Tailscale address is advertised for remote
pairing.

**Symptom:** Tailscale is installed and running, but the desktop app doesn't
advertise its IP.

**How the IP is found:** `DesktopTailscaleService.getTailscaleIp()` first
runs `tailscale ip -4` (or `tailscale.exe` on Windows) and checks the result
is in Tailscale's CGNAT range `100.64.0.0/10` (second octet 64 to 127). If
the CLI call fails or isn't on `PATH`, it scans local network interfaces for
an address in that range.

**Fix:** Check that `tailscale ip -4` succeeds in a terminal and that
Tailscale is connected (`tailscale status`). Then press **Refresh Addresses**
on the dashboard's Server tab. The server also re-probes endpoints
automatically every 30 seconds through its endpoint monitor, so a connected
Tailscale client is usually picked up without any action.

## Pairing / QR code / invite code problems

**Symptom:** The QR code area is blank.

**Cause:** `ConnectionScreen._generateQRData()`
(`ariami_desktop/lib/screens/connection_screen.dart`) returns an empty string
when the server isn't started yet, or when the advertised server address from
`getServerInfo()['server']` is null or empty. In practice the screen sends
you to Owner Setup before this point when no owner account exists, so a blank
QR usually means the server hasn't started. Fix
[the network address problem](#server-wont-start--no-network-address-available)
first.

**Symptom:** The phone says the QR or invite code is invalid or expired.

**Cause:** Registration tokens and invite codes are single-use with a
10-minute time-to-live (`AriamiHttpServer._registrationTokenTtl = Duration(minutes: 10)`
in `ariami_core/lib/services/server/http_server.dart`; both the QR token and
manual invite codes are minted through the same map). The invite code panel
on the connection screen shows a live countdown, and once the code expires
the label tells you to generate a new one.

**Fix:** Press **Generate new code**, or reopen the connection screen so the
QR is rendered with a fresh token.

**About manual entry:** **Generate Invite Code** mints an 8-character code,
displayed as two groups of four with a copy button (`_formatInviteCode` and
`_copyInviteCode` in `connection_screen.dart`). Type it into the mobile app's
Manual entry screen along with one of the addresses shown.

## Owner sign-in, account creation, and password errors

**Symptom:** Creating the owner account fails with:

> "Password must be at least 10 characters"

even though the on-screen form only required 4.

**This is a real inconsistency between client-side and server-side
validation:**

- The owner-setup form validator (`ariami_desktop/lib/screens/owner_setup_screen.dart`)
  only enforces 4 characters: `Password must be at least 4 characters.`
- The account is created through `AuthService().register(...)` in
  `ariami_core/lib/services/auth/auth_service.dart`, whose real minimum is
  `minPasswordLength = 10`. A password of 4 to 9 characters passes the form,
  reaches the server, and throws an `AuthException` with the message above,
  which the screen's `on AuthException` handler shows inline under the form.
- The same 10-character minimum applies to `/api/admin/create-user` and
  `/api/admin/change-password`. The dashboard's **Create User** and
  **Change Password** dialogs (`ariami_desktop/lib/widgets/create_user_dialog.dart`,
  `ariami_desktop/lib/widgets/change_password_dialog.dart`) have no
  minimum-length check at all, so a short password is accepted by the dialog
  and then rejected by the server in a red snackbar.

**Fix:** Use a password of 10 characters or more for every account.

**Symptom:** "That username is already taken." when creating the owner or a
new user.

**Cause:** `UserExistsException` from
`ariami_core/lib/services/auth/user_store.dart`. The username already exists
in `users.json`. Owner Setup maps this exception to the friendly message; the
Create User dialog shows the server's own message instead.

**Symptom:** "Owner sign-in failed" or "Invalid username or password" during
owner sign-in for admin actions (kick device, change password, and so on).

**Cause:** `DashboardAdminApiService.ensureAdminSessionToken()`
(`ariami_desktop/lib/services/dashboard_admin_api_service.dart`) asks for
owner credentials through the dialog in
`ariami_desktop/lib/widgets/admin_credentials_dialog.dart` and calls
`/api/auth/login`. On failure it shows the server's
`response.errorMessage`, or "Owner sign-in failed" when the response had no
message. The server's message for wrong credentials is "Invalid username or
password" (`AuthService.login()`).

**Forgot the owner password?** The **Forgot owner password?** link opens a
recovery dialog (`_showOwnerRecoveryDialog()` in
`ariami_desktop/lib/widgets/admin_credentials_dialog.dart`) that says: "If
you forgot the Owner password, stop Ariami and remove local auth files. Then
restart and create a new Owner account." It prints the exact `rm -f` commands
for your installation's `sessions.json` and `users.json`, read live from
`DesktopStateService.getSessionsFilePath()` and `getUsersFilePath()`, and
points to the repository root `RESET.md` for a full reset guide. This deletes
every account on the server, not just the owner's; the next person to
register becomes the new owner.

## Can't manage users, kick devices, or change passwords

**Symptom:** A snackbar reads one of:

> "Set up the Owner account first to manage connected devices."
> "Set up the Owner account first to add users."
> "Set up the Owner account first to change passwords."
> "Set up the Owner account first to manage users."

**Cause:** Every admin action in
`ariami_desktop/lib/screens/dashboard/dashboard_user_actions.dart`
(`_kickClient`, `_promptCreateUser`, `_promptChangePassword`, `_deleteUser`)
checks `_hasOwnerAccount` first, shows one of these messages, then opens
Owner Setup for you.

**Fix:** Complete Owner Setup from the prompt, or use Dashboard → Overview →
**Set Up Owner Account**.

**Symptom:** An action fails with a red snackbar showing a generic message
such as "Failed to disconnect device", "Failed to create user", "Failed to
change password" or "Failed to delete user".

**Cause:** These are fallback strings used when the server's JSON error has
no `error.message` field (`DashboardHttpResponse.errorMessage` in
`ariami_desktop/lib/models/dashboard_http_response.dart`). Seeing one of
these rather than a specific message means the HTTP call to
`/api/admin/kick-client`, `/api/admin/create-user`,
`/api/admin/change-password` or `/api/admin/delete-user` failed without a
structured reason, which is unusual for an in-process server.

**Symptom:** The admin session stops working after a while, and the next
admin action asks for owner credentials again.

**Expected behaviour:** `DashboardAdminApiService.sendAdminHeartbeat()` pings
`/api/me` every 20 seconds (the timer in
`ariami_desktop/lib/screens/dashboard_screen.dart`). On a `401` it clears the
cached token, unregisters the dashboard's own admin device, and refreshes the
dashboard. The next owner-authenticated action prompts for sign-in again;
`sendAuthenticatedRequest()` retries once automatically.

## Login "locked out" / rate limited

**Symptom:** "Too many failed login attempts. Try again in N minute(s)."

**Cause:** `AuthService.login()`
(`ariami_core/lib/services/auth/auth_service.dart`) locks the bucket after
**5 failed attempts** (`maxLoginAttempts = 5`) for **15 minutes**
(`rateLimitCooldown = Duration(minutes: 15)`). The bucket key combines the
username with the client address (or a supplied rate-limit key). Dashboard
owner sign-in goes through the same service, so it is rate limited the same
way as phone logins.

**Fix:** Wait out the cooldown; the message tells you how many minutes
remain. Attempts during the lock are rejected before the credentials are
checked and don't extend it. A successful login resets the counter for that
bucket.

## Spotify listening-stats import fails

The **Import Spotify listening stats** button on the dashboard's Overview tab
(`ariami_desktop/lib/widgets/dashboard/dashboard_overview_tab.dart`) is
enabled only when an owner account exists, the server is running, and the
library has at least one song (the condition in
`ariami_desktop/lib/screens/dashboard_screen.dart`). A disabled button means
one of those three is missing.

A **Remove Spotify listening stats** button sits next to it. It needs an
owner account and a running server, not a scanned library, and calls
`/api/v2/listening/reset` with `source: spotify`.

Real failure messages, from
`ariami_desktop/lib/services/spotify_import_service.dart`:

| Message | Cause |
| --- | --- |
| "No Spotify history files were found. Choose the folder containing Streaming_History_Audio_\*.json files." | The selected folder has no files matching that exact naming pattern (`_isAudioHistoryFile`), which is what Spotify's "Extended streaming history" export uses. |
| "\<filename\> is not valid JSON." | One of the matched files failed to parse as JSON, so it is corrupted or was edited by hand. |
| "\<filename\> does not contain a Spotify history list." | The file parsed as JSON but wasn't a JSON array, so it isn't the expected export format. |
| "The Spotify history files in this folder are empty." | Files matched and parsed, but contained zero records combined. |
| "Your Ariami library is empty. Scan the library before importing Spotify stats." | There is no scanned library to match Spotify tracks against. |
| "No eligible audio plays were found in this Spotify export." | Every record was dropped by the parser's eligibility rules: the play rule (`ms_played >= 30000` or a natural `trackdone` end with positive play time), or exclusion as a podcast, audiobook, private-session or identity-less record. Unmatched tracks do *not* cause this; they still import. See [Core's LISTENING_STATS.md](../../ariami_core/docs/LISTENING_STATS.md#which-plays-are-eligible). |
| "The signed-in owner changed. Start the import again." | Between analysing and uploading, `/api/me` returned a different username than the one the preview was built for (thrown from `upload()`). |
| "The owner account could not be confirmed. Sign in again and restart the import." | `/api/me` failed or returned no username while confirming identity. |
| "Update Ariami before importing Spotify stats." | The upload endpoint (`/api/v2/listening/events`) returned HTTP 404, so the running server is too old for this feature. |
| "Upload failed on batch N. Plays already uploaded are saved; retrying is safe." | A batch upload failed for another reason. Retrying is safe because earlier successful batches are not re-sent as duplicates. |

The remove action has its own two failures: "Update Ariami before removing
Spotify stats." (HTTP 404) and "Could not remove the imported Spotify stats.
Please try again."

**Fix for the common case:** point the import at the folder from Spotify's
**Extended Streaming History** data export (not the "Account Data" export,
which uses different filenames), make sure your Ariami library has been
scanned first, and retry on transient upload failures. The tool is designed
so retries don't double-count history.

## System tray icon missing or "Start at Login" fails

**Symptom:** No tray icon appears at all, but the app otherwise works fine
(server runs, dashboard works).

**Cause:** `SystemTrayService.initialize()`
(`ariami_desktop/lib/services/system_tray_service.dart`) computes the tray
icon path relative to `Platform.resolvedExecutable`, with different paths for
debug and release builds on each platform. When the icon file isn't at the
computed path, it logs `Warning: Tray icon not found at: <path>` and continues
without a tray icon. The code comment calls this deliberate: "Continue
without tray icon - app will still work". It happens most often with a
non-standard build layout, such as a manually copied executable outside its
bundle.

**Fix:** Reinstall or rebuild so the executable sits where the bundle expects
it. The missing icon is cosmetic; the server is unaffected.

**Symptom:** Toggling **Start at Login** on the Server tab shows:

> "Could not enable start at login. Please try again."
> (or "Could not disable start at login. Please try again.")

(`ariami_desktop/lib/widgets/autostart_card.dart`)

**Cause:** `AutostartCard` wraps `AutostartService`
(`ariami_desktop/lib/services/autostart_service.dart`), which uses the
`launch_at_startup` package with a native mechanism per platform:

- **macOS:** `SMAppService` on macOS 13 and later (shown under Login Items),
  with a per-user LaunchAgent fallback on older versions
  (`ariami_desktop/macos/Runner/MainFlutterWindow.swift`)
- **Windows:** the `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
  registry key
- **Linux:** a `.desktop` entry under `~/.config/autostart/`

Failures usually come from OS permissions, such as a managed profile that
blocks Login Items or registry writes, not from an Ariami bug.
`AutostartCard` renders nothing at all on platforms outside macOS, Windows
and Linux.

**Fix:** Retry once. If it still fails, check OS-level login-item or startup
permissions (macOS: **System Settings → General → Login Items**; Windows: use
a non-restricted account).

## Where logs and app data actually live

Diagnostic messages go to **stdout/stderr** through `print()` calls across
the services, with prefixes such as `[ServerInit]`, `[Dashboard]`, `[Tray]`,
`[Main]`, `[Window]` and `[Reset]`. There is no dedicated log file, so launch
the app from a terminal to read them, or use your OS console tooling
(Console.app on macOS, `journalctl` or a terminal on Linux). On Windows a
terminal launch is the practical option, since the app doesn't write to Event
Viewer.

**Persistent app data**, from `DesktopStateService`
(`ariami_desktop/lib/services/desktop_state_service.dart`), lives in the
platform's `path_provider` "application support directory":

| File / directory | Purpose | Getter |
| --- | --- | --- |
| `users.json` | Registered accounts | `getUsersFilePath()` |
| `sessions.json` | Active login sessions | `getSessionsFilePath()` |
| `catalog.db` | SQLite catalogue database | `getCatalogDbFilePath()` |
| `metadata_cache.json` | Cached scanned-file metadata (speeds up re-scans) | `getMetadataCacheFilePath()` |
| `artwork_cache/` | Processed cover art cache | `getArtworkCacheDirPath()` |
| `transcoded_cache/` | Transcoded audio cache | `getTranscodedCacheDirPath()` |

Setup and config preferences (`setup_completed`, `music_folder_path`,
`server_port`, `transcode_slots`, `owner_setup_skipped`,
`tv_account_picker_enabled`) are stored through `shared_preferences`. On
macOS they land in `NSUserDefaults` under bundle id
`com.example.ariamiDesktop` with Flutter's `flutter.` key prefix
(`flutter.setup_completed`, for example). The repository root `RESET.md` has
the exact `defaults` commands, the per-platform locations of the
application-support directory, and the
`~/Library/Containers/<BUNDLE_ID>/...` path a sandboxed macOS build would use
(the current build is not sandboxed).

## Resetting and reinstalling

The built-in **Reset Ariami** dialog is the supported way to start over. It
lives on the dashboard's **Server** tab under **Danger Zone**
(`ariami_desktop/lib/widgets/reset_ariami_dialog.dart`, wired up by
`_resetAriami()` in
`ariami_desktop/lib/screens/dashboard/dashboard_server_actions.dart`). It
asks you to type `RESET` and offers two scopes:

- **Reset setup only** ("Clears server config, pairing state, remembered
  addresses, and setup progress. Keeps your music files.").
  `DesktopStateService.clearSetupPreferences()`
  (`ariami_desktop/lib/services/desktop_state_service.dart`) removes
  `setup_completed`, `owner_setup_skipped`, `server_port`, `music_folder_path`
  and `transcode_slots`. The catalogue database, accounts and caches stay.
- **Factory reset Ariami** ("Clears Ariami database, users, sessions, stats,
  playlists, cache, and setup state. Keeps your original music files.").
  `DesktopResetService.reset()`
  (`ariami_desktop/lib/services/desktop_reset_service.dart`) stops the server
  first to release the catalogue database handle, clears every preference, then
  deletes `metadata_cache.json`, `users.json`, `sessions.json`, `catalog.db`,
  `artwork_cache/` and `transcoded_cache/`. It passes your current music
  folder path as an explicit guard so it is never touched, and disables
  **Start at Login** when the platform supports it
  (`AutostartService.setEnabled(false)`).

Both scopes stop the server first, then show a confirmation dialog afterwards
("Reset complete" or "Reset failed"). On success the app quits deliberately
so no stale in-memory catalogue or open database handle is left around; reopen
it to start fresh.

**If the reset dialog itself fails** ("Reset failed" with an exception
message), it lists every path that could not be removed
(`ResetResult.failures`), each shown as `• <path>`. Check filesystem
permissions on those paths.

**For a clean reinstall**, or when the in-app reset is unavailable, the
repository root `RESET.md` documents the manual equivalent: quit the app,
delete the `NSUserDefaults`/registry preferences for
`com.example.ariamiDesktop`, and remove `sessions.json` and `users.json` from
the application-support directory by hand. None of these steps touch your
music folder. `RESET.md` also notes that mobile-client sessions live on the
device in secure storage, so they survive any desktop-side reset; use in-app
logout or clear app data on the phone if needed.
