# Feature Walkthrough

A tour of `ariami_desktop`'s actual screens and dashboard tabs, grounded in
the widgets that render them. This is a **server admin console**, not a music
player — there is no playback UI anywhere in this package.

## First-run setup wizard

Shown once, until `DesktopStateService.markSetupComplete()` is called
(`ariami_desktop/lib/services/desktop_state_service.dart`). Routes are wired
in `ariami_desktop/lib/main.dart`.

1. **Welcome** (`lib/screens/welcome_screen.dart`) — introduces the app;
   copy pulled from `lib/onboarding/onboarding_copy.dart`.
2. **Tailscale check** (`lib/screens/tailscale_check_screen.dart`) — detects
   an existing Tailscale install (informational only; never blocks setup).
3. **Select Music Folder** (`lib/screens/folder_selection_screen.dart`) —
   native folder picker (`file_picker`); remembers the path via
   `shared_preferences`.
4. **Scanning Library** (`lib/screens/scanning_screen.dart`) — runs the scan
   and reports files scanned, album/song counts, and any skipped files.
5. **Owner Setup** (`lib/screens/owner_setup_screen.dart`) — creates the
   first ("owner") account, which becomes the server admin.
6. **Connect Mobile App** (`lib/screens/connection_screen.dart`) — starts the
   HTTP server, shows a QR code and a manual invite code for pairing a phone.

Every setup screen has a **contextual help topic** (the "?" affordance driven
by `lib/onboarding/setup_help.dart` and the topic content in
`onboarding_copy.dart`), so the in-app copy doubles as user documentation —
this walkthrough quotes some of it directly where useful.

## Dashboard

After setup, `lib/screens/dashboard_screen.dart` renders a four-tab admin
console via `lib/widgets/dashboard/dashboard_content.dart`:

```
Overview | Activity | Users | Server
```

### Overview tab

`lib/widgets/dashboard/dashboard_overview_tab.dart`. Shows, top to bottom:

- An **update-available banner** when a newer GitHub release exists
  (`UpdateCheckService.checkForUpdate()`, polled every 6 hours and once at
  startup — `dashboard_screen.dart`'s `_updateCheckTimer`), with a
  **View Release on GitHub** button.
- **Server Status**: Active/Stopped, and while running, live counts of
  connected clients, connected users, and active sessions
  (`httpServer.connectedUsers` / `httpServer.activeSessions`).
- A **Start Server / Stop Server** button (`onToggleServer`).
- An **owner-setup-pending** banner if no owner account exists yet, or an
  **"Owner authentication is enabled"** notice once one does.
- **Library Statistics**: album count, song count, and last-scan timestamp.
- **Listening Statistics**: an **Import Spotify listening stats** button
  (enabled only once there's an owner, the server is running, and the
  library has at least one song).

### Activity tab

`lib/widgets/dashboard/dashboard_activity_tab.dart`. Two live tables:

- **User Activity** (`lib/widgets/user_activity_table.dart`) — per-user
  listening/download activity, refreshed every 5 seconds
  (`dashboard_screen.dart`'s `_userActivityRefreshTimer`).
- **Connected Devices** (`lib/widgets/connected_users_table.dart`) — currently
  connected client devices, each with a **Kick** action
  (`onKick` → `POST /api/admin/kick-client`), refreshed every 15 seconds
  alongside the registered-users list.

### Users tab

`lib/widgets/dashboard/dashboard_users_tab.dart`. Shows the
**Registered Users** table (`lib/widgets/server_users_table.dart`) with:

- **Add User** (`lib/widgets/create_user_dialog.dart` →
  `POST /api/admin/create-user`)
- Per-row **Change Password** (`lib/widgets/change_password_dialog.dart` →
  `POST /api/admin/change-password`) and **Delete** (with a confirmation
  dialog, `lib/widgets/delete_user_dialog.dart` →
  `POST /api/admin/delete-user`)
- A toggle for the **TV account picker**
  (`DesktopStateService.isTvAccountPickerEnabled()` /
  `setTvAccountPickerEnabled()`) — off by default, since (per the code
  comment in `desktop_state_service.dart`) enabling it lets any device on the
  network list this server's usernames pre-authentication.

All of these actions require **Owner Sign-In**
(`lib/widgets/admin_credentials_dialog.dart`) the first time they're used in
a session — see `docs/TROUBLESHOOTING.md` for the exact behavior and error
messages.

### Server tab

`lib/widgets/dashboard/dashboard_server_tab.dart`. Configuration and
maintenance:

- **Configuration cards**: Music Folder, Transcode Slots (with an **Edit**
  dialog, `lib/widgets/transcode_slots_dialog.dart`), LAN Address, Tailscale
  IP, and **Start at Login** (`lib/widgets/autostart_card.dart`).
- **Refresh Addresses** button to re-detect LAN/Tailscale IPs without
  restarting the server.
- **Quick Actions**: **Change Folder** (re-runs folder selection),
  **Show QR** (re-opens the connection/pairing screen), and
  **Rescan Library**.
- **Danger Zone**: **Reset Ariami**
  (`lib/widgets/reset_ariami_dialog.dart`) — see
  `docs/TROUBLESHOOTING.md#resetting-and-reinstalling` for exactly what each
  reset scope does.

## Spotify listening-stats import

A native (non-web) import flow, triggered from the Overview tab and
implemented in `lib/services/spotify_import_service.dart` +
`lib/widgets/spotify_import_dialog.dart`. It reads a folder of Spotify
**Extended Streaming History** export files
(`Streaming_History_Audio_*.json`), matches each play against your scanned
library, previews matched vs. unmatched track counts, then uploads the
matched listening events in batches of 500
(`DesktopSpotifyImportService.uploadBatchSize`) to
`/api/v2/listening/events`. See `docs/TROUBLESHOOTING.md` for the exact
failure messages and what each one means.
