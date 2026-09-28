# Architecture Note: How the GUI Drives `ariami_core`

`ariami_desktop` is a Flutter desktop app that instantiates and drives
`AriamiHttpServer`. The HTTP server, library manager, auth service, and
transcoding/artwork services all live in the sibling `ariami_core` package
(`ariami_desktop/pubspec.yaml`: `ariami_core: { path: ../ariami_core }`).
The server runs **in the same Dart isolate/process as the Flutter UI**, so it
starts and stops with the app.

## Layering

```
┌─────────────────────────────────────────────────────────────┐
│ Flutter UI (screens/, widgets/)                             │
│   - onboarding wizard, dashboard tabs, dialogs              │
└───────────────┬─────────────────────────────────────────────┘
                │ calls
┌───────────────▼─────────────────────────────────────────────┐
│ Desktop services (lib/services/)                            │
│   - desktop_state_service.dart          (prefs/paths)       │
│   - server_initialization_service.dart  (wires core)        │
│   - desktop_server_lifecycle_service.dart (start)           │
│   - desktop_download_limits_service.dart (limits)           │
│   - desktop_transcode_slots_service.dart (slots)            │
│   - desktop_tailscale_service.dart      (network/IP)        │
│   - desktop_reset_service.dart          (reset)             │
│   - dashboard_admin_api_service.dart    (HTTP admin)        │
│   - autostart_service.dart, system_tray_service.dart, ...   │
└───────────────┬─────────────────────────────────────────────┘
                │ uses
┌───────────────▼─────────────────────────────────────────────┐
│ ariami_core (../ariami_core)                                │
│   - AriamiHttpServer (http_server.dart + parts)             │
│   - LibraryManager / FileScanner / scanner isolate          │
│   - AuthService / UserStore / SessionStore                  │
│   - TranscodingService / ArtworkService                     │
│   - ServerPortPolicy, TranscodeSlotsPolicy, ResetService    │
└─────────────────────────────────────────────────────────────┘
```

## What the desktop layer actually adds

Everything under `ariami_desktop/lib/services/` handles concerns specific to a
desktop host, which keeps `ariami_core` host-agnostic (the same engine backs
`ariami_cli` too, see the repository root `GUIDE.md`):

- **Where things are stored.** `DesktopStateService`
  (`lib/services/desktop_state_service.dart`) is the only place that knows
  about `shared_preferences` and the platform's `path_provider`
  application-support directory. It hands `ariami_core` concrete file paths
  (`users.json`, `sessions.json`, `catalog.db`, `metadata_cache.json`, the
  artwork and transcode cache directories), so the shared engine never needs
  to know the platform layout.
- **Network address discovery.** `DesktopTailscaleService`
  (`lib/services/desktop_tailscale_service.dart`) shells out to the
  `tailscale` CLI and scans OS network interfaces, work that only makes sense
  from a full desktop OS process.
- **Orchestration order.** `ServerInitializationService`
  (`lib/services/server_initialization_service.dart`) and
  `DesktopServerLifecycleService`
  (`lib/services/desktop_server_lifecycle_service.dart`) sequence the several
  `ariami_core` setup calls a working server needs (feature flags → cache path
  → transcoding/artwork services → auth → download limits → listen), so every
  desktop screen that needs to (re)start the server calls one small,
  consistent entry point instead of re-deriving that order.
- **Presentation-only state.** System tray behaviour
  (`lib/services/system_tray_service.dart`), window-close interception
  (`lib/main.dart`), launch-at-login
  (`lib/services/autostart_service.dart`), and update-check
  (`lib/services/update_check_service.dart`) are desktop-app conventions
  layered on top of the server.

## The dashboard talks to its own embedded server over HTTP

The dashboard's admin actions (kick device, create user, change password,
delete user, Spotify stats upload) go through `DashboardAdminApiService`
(`lib/services/dashboard_admin_api_service.dart`). That service makes real
HTTP requests (via `dart:io`'s `HttpClient`) to the server's own REST API
(`/api/admin/...`, `/api/auth/login`, `/api/me`, `/api/v2/listening/events`)
at `http://<advertised-ip>:<port>`, exactly as a mobile client would, and
authenticates with a bearer session token from `/api/auth/login`. The
dashboard is therefore just another authenticated API client of the same
server a phone talks to. Its one convenience is minting a device identity
(`DashboardClientIds.dashboardAdminDeviceId` /
`dashboardAdminDeviceName` in `lib/models/connected_client_row.dart`) so it
shows up in connected-clients lists as recognizably "the dashboard" rather
than as an anonymous device.

## Feature flags

`lib/utils/feature_flags_loader.dart` reads `AriamiFeatureFlags` from process
environment variables and validates one invariant before starting the server.
Each flag accepts `1`, `true`, `yes`, or `on` (case-insensitive) and falls
back to its default when unset:

| Variable | Default |
| --- | --- |
| `ARIAMI_ENABLE_V2_API` | on |
| `ARIAMI_ENABLE_CATALOG_WRITE` | off |
| `ARIAMI_ENABLE_CATALOG_READ` | off |
| `ARIAMI_ENABLE_ARTWORK_PRECOMPUTE` | off |
| `ARIAMI_ENABLE_DOWNLOAD_JOBS` | on |
| `ARIAMI_ENABLE_API_SCOPED_AUTH_FOR_CLI_WEB` | on |
| `ARIAMI_ENABLE_CONNECT_PROTOCOL_V3` | on |

`enableDownloadJobs` requires `enableV2Api`
(`validateFeatureFlagInvariantsOrThrow`), otherwise
`ServerInitializationService.configureLibraryCacheAndFeatureFlags()` throws a
`StateError` and server startup fails. The same method also throws when
`enableV2Api` is on but the catalogue repository cannot be initialised. This is
the same environment-driven mechanism `ariami_cli` uses, and the desktop app
reads the flags from the process environment at launch.
