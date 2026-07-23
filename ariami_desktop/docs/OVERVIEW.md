# What Ariami Desktop Is

## In one line

Ariami Desktop is the **GUI music streaming server** for Ariami — confirmed by its
own package description in `ariami_desktop/pubspec.yaml`:

```yaml
name: ariami_desktop
description: "Ariami Desktop - Music streaming server with GUI"
version: 4.4.0+8
```

It is **not** a playback client. It does not have a "now playing" screen, a
queue, or a library browser for listening. Its job is to run the Ariami server
process on your computer and give you a graphical way to configure it, watch
it, and administer it — the actual listening happens in the Ariami mobile app,
which connects to this server over the network.

## Who it's for

Anyone who wants to self-host their own music library and stream it to their
phone, without touching a command line. It targets the same audience as the
headless `ariami_cli` server, but trades the CLI's browser-based setup wizard
for a native desktop app with a system-tray presence
(`ariami_desktop/lib/services/system_tray_service.dart`) and a window that can
stay resident in the background.

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
   - `welcome_screen.dart` — introduction.
   - `tailscale_check_screen.dart` — optional check for a Tailscale install,
     for remote access later.
   - `folder_selection_screen.dart` — pick the folder to scan for music,
     using `file_picker`.
   - `scanning_screen.dart` — runs the library scan via
     `AriamiHttpServer.libraryManager.scanMusicFolder(...)` (from
     `ariami_core`) and reports files scanned / albums / songs / skipped
     files.
   - `owner_setup_screen.dart` — creates the first ("owner"/admin) account.
   - `connection_screen.dart` — starts the HTTP server and shows a QR code
     (via `qr_flutter`) and a manual invite code for pairing the mobile app.
2. **Dashboard** (`dashboard_screen.dart`, after setup): a four-tab admin
   console — Overview, Activity, Users, Server — described in
   [FEATURES.md](FEATURES.md).
3. **Runs the actual server in-process.** The app embeds
   `AriamiHttpServer` from `ariami_core` (see the `ariami_core` dependency
   pinned by relative path in `ariami_desktop/pubspec.yaml`:
   `ariami_core: { path: ../ariami_core }`) directly inside the Flutter
   process — there is no separate server binary. Stopping the app's window
   (or quitting from the tray) stops the server.
4. **Stays resident via the system tray** so the server keeps running while
   the window is hidden (`ariami_desktop/lib/services/system_tray_service.dart`,
   `ariami_desktop/lib/main.dart` window-close interception).

## How it relates to `ariami_core`

`ariami_desktop` is a thin GUI shell around `ariami_core`. Nearly every
capability — the HTTP server (`AriamiHttpServer`), library scanning, auth
(`AuthService`), transcoding (`TranscodingService`), artwork
(`ArtworkService`), download-limit policy, port-fallback policy
(`ServerPortPolicy`), and reset logic (`ResetService`) — is implemented once in
`ariami_core` and simply wired up and displayed by desktop-specific services
under `ariami_desktop/lib/services/`, for example:

- `server_initialization_service.dart` configures the library cache, feature
  flags, transcoding/artwork services, and starts the listener.
- `desktop_server_lifecycle_service.dart` resolves the network address (LAN
  or Tailscale) and starts the server.
- `desktop_state_service.dart` is the desktop-specific persistence layer
  (`shared_preferences` + files under the platform's application-support
  directory) that `ariami_core`'s generic services read and write through.
- `desktop_tailscale_service.dart` detects a local Tailscale install and IP
  by shelling out to the `tailscale` CLI or scanning network interfaces —
  desktop-only, because it deals with local processes/paths.

This mirrors what `ariami_cli` does for headless hosts (see the repo root
`README.md` and `GUIDE.md`): both packages are GUI/CLI front ends over the
same `ariami_core` server engine, just with different presentation layers
(native desktop UI here vs. a browser-based setup wizard for the CLI).

## How it relates to the mobile client

Ariami Desktop never plays audio itself and has no listening UI. It exists to
be **paired with** the Ariami mobile app:

- The connection screen (`ariami_desktop/lib/screens/connection_screen.dart`)
  generates a QR code containing the server's address(es) and a short-lived
  registration token (`AriamiHttpServer.getServerInfo(includeRegistrationToken: true)`),
  which the mobile app scans to register or log in.
- A manual invite code (`AriamiHttpServer.createInviteCode()`) is offered as
  a fallback for phones that can't scan a QR code.
- Device/session management for connected phones (kick a device, see
  connected clients, manage accounts) happens from the desktop dashboard,
  documented in [FEATURES.md](FEATURES.md).

This document describes `ariami_desktop`, the GUI **server** app in this
repository.

## Desktop platforms it builds for

Confirmed by the presence of platform runner projects in the package:

| Platform | Evidence |
| --- | --- |
| **macOS** | `ariami_desktop/macos/Runner/` — `Info.plist`, `Release.entitlements`, `DebugProfile.entitlements`; bundle id `com.example.ariamiDesktop` from `ariami_desktop/macos/Runner/Configs/AppInfo.xcconfig` |
| **Windows** | `ariami_desktop/windows/runner/` — `CMakeLists.txt`, `Runner.rc`, `resource.h`, `main.cpp` |
| **Linux** | `ariami_desktop/linux/runner/` — `CMakeLists.txt`, `main.cc`; top-level `ariami_desktop/linux/CMakeLists.txt` requires `gtk+-3.0` via `pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)` |

Standard build commands, from the existing `ariami_desktop/README.md` and
verified against `ariami_desktop/linux/CMakeLists.txt` / the platform folders:

```bash
cd ariami_desktop
flutter pub get
flutter run -d macos        # or linux/windows
flutter build macos         # or linux/windows
```

See [BUILDING.md](BUILDING.md) for prerequisites and platform-specific
details (including the optional Sonic transcoder native library on
Linux/macOS).

## Version note

`ariami_desktop/pubspec.yaml` currently pins `version: 4.4.0+8`. This is
lower than the sibling packages `ariami_core` and `ariami_cli`
(`version: 5.0.0` in their respective `pubspec.yaml` files) — per this
project's documentation rules, that discrepancy is reported as-is rather than
"corrected." Note also that the in-app "Update available" banner on the
Overview tab (`ariami_desktop/lib/widgets/dashboard/dashboard_overview_tab.dart`)
displays `kAriamiVersion` from `ariami_core/lib/app_version.dart` (currently
`5.0.0`), **not** the `ariami_desktop` package version above — so the version
string shown inside the running app and the version in this package's
`pubspec.yaml` can legitimately differ.
