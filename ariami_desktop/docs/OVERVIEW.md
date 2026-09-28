# What Ariami Desktop Is

## In one line

Ariami Desktop is the **GUI music streaming server** for Ariami. Its own
package description in `ariami_desktop/pubspec.yaml` says so:

```yaml
name: ariami_desktop
description: "Ariami Desktop - Music streaming server with GUI"
version: 5.2.3+14
```

The app runs the Ariami server on your computer and gives you a graphical way
to configure it, watch it, and administer it. The listening interface (a "now
playing" screen, a queue, a library browser) lives in the client apps, which
connect to this server over the network.

## Who it's for

Anyone who wants to self-host a music library and stream it to their phone
without touching a command line. It targets the same self-hosting audience as
the headless `ariami_cli` server, and adds a native desktop app with a setup
wizard, a dashboard, a system-tray presence
(`ariami_desktop/lib/services/system_tray_service.dart`), and a window that
can stay resident in the background.

Concretely, that's someone who:

- Has a folder of music files (MP3/FLAC/etc.) they own and want to stream
  themselves rather than pay for a cloud subscription.
- Has a "home computer" (Mac, Windows PC, or Linux box) that can stay on, or
  is willing to leave running while they listen from their phone.
- Wants a graphical setup wizard, a dashboard, and a tray icon rather than
  managing a background daemon by hand.

## What it does

Reading `ariami_desktop/lib/main.dart` and the screens under
`ariami_desktop/lib/screens/`, the app's job is, in order:

1. **First-run setup wizard** (only shown once, gated by
   `DesktopStateService.isSetupComplete()` in
   `ariami_desktop/lib/services/desktop_state_service.dart`):
   - `welcome_screen.dart`: introduction.
   - `tailscale_check_screen.dart`: optional check for a Tailscale install,
     for remote access later.
   - `folder_selection_screen.dart`: pick the folder to scan for music,
     using `file_picker`.
   - `scanning_screen.dart`: runs the library scan via
     `AriamiHttpServer.libraryManager.scanMusicFolder(...)` (from
     `ariami_core`) and reports files scanned, albums, songs, and skipped
     files.
   - `owner_setup_screen.dart`: creates the first ("owner"/admin) account.
   - `connection_screen.dart`: starts the HTTP server and shows a QR code
     (via `qr_flutter`) plus a manual invite code for pairing a client.
2. **Dashboard** (`dashboard_screen.dart`, after setup): a four-tab admin
   console (Overview, Activity, Users, Server), described in
   [FEATURES.md](FEATURES.md).
3. **Runs the actual server in-process.** The app embeds
   `AriamiHttpServer` from `ariami_core` (see the `ariami_core` dependency
   pinned by relative path in `ariami_desktop/pubspec.yaml`:
   `ariami_core: { path: ../ariami_core }`) directly inside the Flutter
   process, so the server starts and stops with the app. Quitting from the
   tray, or choosing Quit in the window-close dialog, stops the server;
   hiding the window to the tray leaves it running.
4. **Stays resident via the system tray** so the server keeps running while
   the window is hidden (`ariami_desktop/lib/services/system_tray_service.dart`,
   `ariami_desktop/lib/main.dart` window-close interception).

## How it relates to `ariami_core`

`ariami_desktop` is a thin GUI shell around `ariami_core`. The HTTP server
(`AriamiHttpServer`), library scanning, auth (`AuthService`), transcoding
(`TranscodingService`), artwork (`ArtworkService`), download-limit policy,
port-fallback policy (`ServerPortPolicy`), and reset logic (`ResetService`)
are implemented once in `ariami_core`. Desktop-specific services under
`ariami_desktop/lib/services/` wire them up and display them, for example:

- `server_initialization_service.dart` configures the library cache, feature
  flags, transcoding/artwork services, and starts the listener.
- `desktop_server_lifecycle_service.dart` resolves the network address (LAN
  or Tailscale) and starts the server.
- `desktop_state_service.dart` is the desktop-specific persistence layer
  (`shared_preferences` + files under the platform's application-support
  directory) that `ariami_core`'s generic services read and write through.
- `desktop_download_limits_service.dart` resolves the per-platform download
  concurrency and queue limits (higher on macOS, and with higher per-user
  concurrency on Raspberry Pi 5).
- `desktop_transcode_slots_service.dart` persists the host's optional
  transcode-slot override.
- `desktop_tailscale_service.dart` detects a local Tailscale install and IP
  by shelling out to the `tailscale` CLI or scanning network interfaces.
  It is desktop-only because it deals with local processes and paths.

This mirrors what `ariami_cli` does for headless hosts (see the repo root
`README.md` and `GUIDE.md`): both packages are front ends over the same
`ariami_core` server engine, with different presentation layers (native
desktop UI here, a browser-based setup wizard for the CLI).

## How it relates to the mobile client

Ariami Desktop pairs with the Ariami mobile app, which handles all listening
and playback:

- The connection screen (`ariami_desktop/lib/screens/connection_screen.dart`)
  generates a QR code containing the server's address(es) and a short-lived
  registration token (`AriamiHttpServer.getServerInfo(includeRegistrationToken: true)`),
  which the mobile app scans to register or log in.
- A manual invite code (`AriamiHttpServer.createInviteCode()`) is offered as
  a fallback for phones that can't scan a QR code.
- Device/session management for connected phones (kick a device, see
  connected clients, manage accounts) happens from the desktop dashboard,
  documented in [FEATURES.md](FEATURES.md).

## Desktop platforms it builds for

Confirmed by the presence of platform runner projects in the package:

| Platform | Evidence |
| --- | --- |
| **macOS** | `ariami_desktop/macos/Runner/`: `Info.plist`, `Release.entitlements`, `DebugProfile.entitlements`; bundle id `com.example.ariamiDesktop` and app name `Ariami-Desktop` from `ariami_desktop/macos/Runner/Configs/AppInfo.xcconfig` |
| **Windows** | `ariami_desktop/windows/runner/`: `CMakeLists.txt`, `Runner.rc`, `resource.h`, `main.cpp` |
| **Linux** | `ariami_desktop/linux/runner/`: `CMakeLists.txt`, `main.cc`; top-level `ariami_desktop/linux/CMakeLists.txt` requires `gtk+-3.0` via `pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)` |

Standard build commands, from the existing `ariami_desktop/README.md` and
verified against `ariami_desktop/linux/CMakeLists.txt` and the platform
folders:

```bash
cd ariami_desktop
flutter pub get
flutter run -d macos        # or linux/windows
flutter build macos         # or linux/windows
```

See [BUILDING.md](BUILDING.md) for prerequisites and platform-specific
details, including the Rust-based Sonic transcoder library (required for
macOS builds and optional on Linux and Windows).

## Version note

`ariami_desktop/pubspec.yaml` pins `version: 5.2.3+14`. The sibling packages
`ariami_core` and `ariami_cli` both carry `5.2.3`, and `ariami_mobile`
carries `5.2.3+14`. Every Ariami component shares one version number, so a
package version that disagrees with its siblings should be treated as a
mistake rather than an expected difference.

The in-app "Update available" banner on the Overview tab
(`ariami_desktop/lib/widgets/dashboard/dashboard_overview_tab.dart`) displays
`kAriamiVersion` from `ariami_core/lib/app_version.dart`, **not** the
`ariami_desktop` package version above. The two agree today (`5.2.3`), but
they are still separate sources, so a version bump has to touch both.
