# Architecture Note: How the GUI Drives `ariami_core`

`ariami_desktop` contains almost no server logic of its own. It is a Flutter
desktop app that instantiates and drives `AriamiHttpServer` — the actual HTTP
server, library manager, auth service, and transcoding/artwork services all
live in the sibling `ariami_core` package
(`ariami_desktop/pubspec.yaml`: `ariami_core: { path: ../ariami_core }`).
There is no separate server process to launch or connect to: the server runs
**in the same Dart isolate/process as the Flutter UI**.

## Layering

```
┌─────────────────────────────────────────────────────────────┐
│ Flutter UI (screens/, widgets/)                              │
│   - onboarding wizard, dashboard tabs, dialogs                │
└───────────────┬─────────────────────────────────────────────┘
                │ calls
┌───────────────▼─────────────────────────────────────────────┐
│ Desktop services (lib/services/)                              │
│   - desktop_state_service.dart        (local prefs/paths)     │
│   - server_initialization_service.dart (wires core services)  │
│   - desktop_server_lifecycle_service.dart (start orchestration)│
│   - desktop_tailscale_service.dart    (local network/IP detect)│
│   - desktop_reset_service.dart        (reset orchestration)    │
│   - dashboard_admin_api_service.dart  (owner-authed HTTP calls)│
│   - autostart_service.dart, system_tray_service.dart, ...      │
└───────────────┬─────────────────────────────────────────────┘
                │ uses
┌───────────────▼─────────────────────────────────────────────┐
│ ariami_core (../ariami_core)                                  │
│   - AriamiHttpServer (services/server/http_server.dart + parts)│
│   - LibraryManager / FileScanner / library scanner isolate     │
│   - AuthService / UserStore / SessionStore                     │
│   - TranscodingService / ArtworkService                        │
│   - ServerPortPolicy, TranscodeSlotsPolicy, ResetService        │
└─────────────────────────────────────────────────────────────┘
```

## What the desktop layer actually adds

Everything under `ariami_desktop/lib/services/` exists to supply
**desktop-specific** concerns that `ariami_core`'s services need but don't
implement themselves, because `ariami_core` is meant to be host-agnostic
(the same engine backs `ariami_cli` too — see the repository root `GUIDE.md`):

- **Where things are stored.** `DesktopStateService`
  (`lib/services/desktop_state_service.dart`) is the only place that knows
  about `shared_preferences` and the platform's `path_provider`
  application-support directory. It hands `ariami_core` concrete file paths
  (`users.json`, `sessions.json`, `catalog.db`, etc.) rather than `ariami_core`
  assuming any particular storage location itself.
- **Network address discovery.** `DesktopTailscaleService`
  (`lib/services/desktop_tailscale_service.dart`) shells out to the
  `tailscale` CLI / scans OS network interfaces — something that only makes
  sense to do from a full desktop OS process, not from `ariami_core` itself.
- **Orchestration order.** `ServerInitializationService`
  (`lib/services/server_initialization_service.dart`) and
  `DesktopServerLifecycleService`
  (`lib/services/desktop_server_lifecycle_service.dart`) sequence the
  several `ariami_core` setup calls a working server needs (feature flags →
  cache path → transcoding/artwork services → auth → download limits →
  listen), so every desktop screen that needs to (re)start the server calls
  one small, consistent entry point instead of re-deriving that order.
- **Presentation-only state.** System tray behavior
  (`lib/services/system_tray_service.dart`), window-close interception
  (`lib/main.dart`), launch-at-login
  (`lib/services/autostart_service.dart`), and update-check
  (`lib/services/update_check_service.dart`) have nothing to do with the
  server itself — they're desktop-app conventions layered on top.

## The dashboard talks to its own embedded server over HTTP

Notably, the dashboard's admin actions (kick device, create user, change
password, delete user, Spotify stats upload) don't call `ariami_core` Dart
APIs directly — they go through `DashboardAdminApiService`
(`lib/services/dashboard_admin_api_service.dart`), which makes real HTTP
requests (via `dart:io`'s `HttpClient`) to the server's own REST API
(`/api/admin/...`, `/api/auth/login`, `/api/me`, `/api/v2/listening/events`)
at `http://<advertised-ip>:<port>`, exactly as a mobile client would,
authenticating with a bearer session token from `/api/auth/login`. This means
the dashboard is, functionally, just another authenticated API client of the
same server a phone talks to — not a privileged back-door. The one
convenience it uses is minting its own device identity
(`DashboardClientIds.dashboardAdminDeviceId` /
`dashboardAdminDeviceName`) so it shows up in connected-clients lists as
recognizably "the dashboard" rather than an anonymous device.

## Feature flags

`lib/utils/feature_flags_loader.dart` reads `AriamiFeatureFlags` from process
environment variables (`ARIAMI_ENABLE_V2_API`, `ARIAMI_ENABLE_CATALOG_WRITE`,
`ARIAMI_ENABLE_CATALOG_READ`, `ARIAMI_ENABLE_ARTWORK_PRECOMPUTE`,
`ARIAMI_ENABLE_DOWNLOAD_JOBS`, `ARIAMI_ENABLE_API_SCOPED_AUTH_FOR_CLI_WEB`),
each defaulting to a fixed value if unset, and validates one invariant before
starting the server: `enableDownloadJobs` requires `enableV2Api`
(`validateFeatureFlagInvariantsOrThrow`) — otherwise
`ServerInitializationService.configureLibraryCacheAndFeatureFlags()` throws a
`StateError` and server startup fails. This is the same environment-driven
mechanism `ariami_cli` uses; the desktop app doesn't expose these as UI
settings, only as environment variables for whoever launches the process.
