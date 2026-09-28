# Feature Walkthrough

A tour of `ariami_desktop`'s actual screens and dashboard tabs, grounded in
the widgets that render them. This is a **server admin console**; the music
player lives in the client apps.

## First-run setup wizard

Shown once, until `DesktopStateService.markSetupComplete()` is called
(`ariami_desktop/lib/services/desktop_state_service.dart`). Routes are wired
in `ariami_desktop/lib/main.dart`.

1. **Welcome** (`lib/screens/welcome_screen.dart`): introduces the app; copy
   pulled from `lib/onboarding/onboarding_copy.dart`.
2. **Tailscale check** (`lib/screens/tailscale_check_screen.dart`): detects
   an existing Tailscale install. Informational only; setup continues either
   way.
3. **Select Music Folder** (`lib/screens/folder_selection_screen.dart`):
   native folder picker (`file_picker`); remembers the path via
   `shared_preferences`.
4. **Scanning Library** (`lib/screens/scanning_screen.dart`): runs the scan
   and reports files scanned, album/song counts, and any skipped files.
5. **Owner Setup** (`lib/screens/owner_setup_screen.dart`): creates the
   first ("owner") account, which becomes the server admin.
6. **Connect Mobile App** (`lib/screens/connection_screen.dart`): starts the
   HTTP server, shows a QR code and a manual invite code for pairing a phone,
   and offers **Continue to Dashboard**. The app marks setup complete and
   navigates to the dashboard on its own as soon as a client connects.

Every setup screen has a **contextual help topic**: an info button in the
header, driven by `lib/onboarding/setup_help.dart` with the topic content in
`onboarding_copy.dart`. The in-app help doubles as user documentation, and
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
  (`UpdateCheckService.checkForUpdate()`, polled once at startup and then
  every 6 hours via `dashboard_screen.dart`'s `_updateCheckTimer`), with a
  **View Release on GitHub** button.
- **Server Status**: Active/Stopped, and while running, live counts of
  connected clients (`connectionManager.clientCount`), connected users, and
  active sessions
  (`httpServer.connectedUsers` / `httpServer.activeSessions`).
- A **Start Server / Stop Server** button (`onToggleServer`).
- An **owner-setup-pending** banner if no owner account exists yet, or an
  **"Owner authentication is enabled"** notice once one does.
- **Library Statistics**: album count, song count, and last-scan timestamp.
- **Listening Statistics**: a summary of the owner account's Spotify import,
  an **Import Spotify listening stats** button (enabled only once there's an
  owner, the server is running, and the library has at least one song), and a
  **Remove Spotify listening stats** button.

### Activity tab

`lib/widgets/dashboard/dashboard_activity_tab.dart`. Two live tables:

- **User Activity** (`lib/widgets/user_activity_table.dart`): per-user
  download and transcode activity (active downloads, queued downloads, and
  in-flight transcodes), refreshed every 5 seconds
  (`dashboard_screen.dart`'s `_userActivityRefreshTimer`).
- **Connected Users & Devices** (`lib/widgets/connected_users_table.dart`):
  currently connected client devices with their user, connect time, last
  heartbeat, and a **Kick** action
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

Below the table, a **Sign-in Privacy** switch for the **TV account picker**
(`DesktopStateService.isTvAccountPickerEnabled()` /
`setTvAccountPickerEnabled()`) controls whether Ariami TV may list this
server's accounts on its sign-in screen. It is off by default; while it is
enabled, any device on the network can see the account names and photos
(passwords are always required).

Owner-only actions across the dashboard (kick, add user, change password,
delete user) prompt for **Owner Sign-In**
(`lib/widgets/admin_credentials_dialog.dart`) the first time they are used in
a session, and again if the session expires. See
[TROUBLESHOOTING.md](TROUBLESHOOTING.md) for the exact behaviour and error
messages.

### Server tab

`lib/widgets/dashboard/dashboard_server_tab.dart`. Configuration and
maintenance:

- **Configuration cards**: Music Folder, Transcode Slots (with an **Edit**
  dialog, `lib/widgets/transcode_slots_dialog.dart`), LAN Address, Tailscale
  IP, and **Start at Login** (`lib/widgets/autostart_card.dart`).
- **Refresh Addresses** button to re-detect LAN/Tailscale IPs without
  restarting the server.
- **Ariami TV**: the **Activate TV License** card
  (`lib/widgets/dashboard/tv_license_card.dart`). Paste a TV licence key and
  the card exchanges it for a signed licence file stored on the embedded
  server, so every TV in the household picks it up and verifies it on its
  next connect.
- **Quick Actions**: **Change Folder** (re-runs folder selection),
  **Show QR** (re-opens the connection/pairing screen), and
  **Rescan Library** (disabled until a music folder is configured).
- **Danger Zone**: **Reset Ariami**
  (`lib/widgets/reset_ariami_dialog.dart`) with two scopes, "Reset setup
  only" and "Factory reset Ariami". See
  [TROUBLESHOOTING.md](TROUBLESHOOTING.md#resetting-and-reinstalling) for
  exactly what each scope does.

## Spotify listening-stats import

A native (non-web) import flow, triggered from the Overview tab and
implemented in `lib/services/spotify_import_service.dart` +
`lib/widgets/spotify_import_dialog.dart`. It reads a folder of Spotify
**Extended Streaming History** export files
(`Streaming_History_Audio_*.json`), matches each play against your scanned
library, previews eligible plays and matched vs. unmatched track counts, then
uploads the matched listening events in batches of 500
(`DesktopSpotifyImportService.uploadBatchSize`) to
`/api/v2/listening/events`. See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for
the exact failure messages and what each one means.

For what actually gets imported and why (which plays are eligible, how tracks
are matched to your library, why re-importing is safe, and how imported stats
differ from live-tracked ones), see
[Core's LISTENING_STATS.md](../../ariami_core/docs/LISTENING_STATS.md).

The Overview tab's **Listening Statistics** section also reports what the
owner account's import currently holds (play count, when plays last landed,
and the span of history they cover) and offers **Remove Spotify listening
stats** (`lib/widgets/spotify_remove_dialog.dart`). The dialog confirms and
then posts `{"source": "spotify"}` to `/api/v2/listening/reset`, deleting only
imported plays and leaving live-tracked history intact. The status line is
read in-process (`AriamiHttpServer.getSpotifyImportStatus`) so it never
prompts for the owner password, and the remove button is disabled when there
is nothing to remove.
