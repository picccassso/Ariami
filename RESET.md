# Reset Ariami

The built-in reset is the easiest way to start over. It stops the server first,
asks you to type `RESET` to confirm (the CLI can skip that with `-y`), and
leaves your music folder untouched. The manual commands further down are a
fallback for developers and edge cases.

## Built-in reset (recommended)

Two scopes are offered everywhere:

- **Reset setup only** clears setup progress, server config, saved connection
  details and the transcode-slots override. It keeps the catalogue database and
  accounts, so the library does not need rescanning.
- **Factory reset** removes the catalogue database (the scanned library),
  accounts, sessions, setup state and the artwork and transcoded caches, and
  disables start-on-boot.

Your original music files stay untouched in both scopes.

A factory reset leaves some per-account stores in place, because they live in
separate databases and files beside the catalogue: listening stats, pins and
hidden items, playlist edits and cover images, artist photos, custom device
names, user avatars and the stored TV licence. Check the [Server data
directory](#server-data-directory) section below if you want those gone as
well.

**Desktop:** open the dashboard → **Server** tab → **Danger Zone** →
**Reset Ariami**, pick a scope, type `RESET`, confirm. The app closes when it
finishes; reopen it to start fresh.

**CLI (terminal):**

```bash
./ariami_cli reset              # interactive menu (setup-only / factory / cancel)
./ariami_cli reset --setup -y   # setup/config only, no prompts
./ariami_cli reset --factory -y # factory reset, no prompts
```

A reset stops a running server first. Both scopes ask you to type `RESET`
unless you pass `-y`.

**CLI web dashboard:** **Server** tab → **Danger zone** → **Reset
Ariami…**, pick a scope and type `RESET`. The server stops when the reset
finishes; start it again from the machine.

---

## Manual reset (fallback)

The rest of this file is a quick reference for developers and power users who
want to wipe local app preferences and saved server auth state by hand, for
example after renaming the app, debugging onboarding, or clearing logins. It
leaves your music files in place.

**Quit Ariami** (desktop app and/or CLI server) before running file-deletion
commands so nothing overwrites the files while you edit them.

---

## Flutter / macOS preferences (`defaults`)

Ariami Desktop stores setup state and the music folder path in `NSUserDefaults`.
Flutter prefixes keys with `flutter.` (for example `flutter.setup_completed`).
Replace the bundle id if yours differs (check the built `.app` or
`macos/Runner/Configs/AppInfo.xcconfig`).

```bash
# Wipe all defaults for the app (typical full prefs reset)
defaults delete com.example.ariamiDesktop
killall cfprefsd 2>/dev/null
```

Optional: delete only setup + saved music folder path, not every key:

```bash
defaults delete com.example.ariamiDesktop flutter.setup_completed
defaults delete com.example.ariamiDesktop flutter.music_folder_path
killall cfprefsd 2>/dev/null
```

---

## Windows and Linux preferences

On Windows and Linux the preferences live in a JSON file beside the app's data:

- Windows: `%APPDATA%\com.example\Ariami Desktop\shared_preferences.json`
- Linux: `~/.local/share/com.example.ariami_desktop/shared_preferences.json`
  (older installs may use `~/.local/share/ariami_desktop`)

Delete that file with the app quit to clear setup state and the saved music
folder path.

---

## Server data directory

The server keeps all of its data in one folder. Delete the folder to remove
the catalogue, accounts, sessions, stats, playlists, caches and the stored TV
licence in one go.

| Platform | Folder |
| --- | --- |
| macOS (Desktop Server) | `~/Library/Application Support/com.example.ariamiDesktop/` |
| Windows (Desktop Server) | `%APPDATA%\com.example\Ariami Desktop\` |
| Linux (Desktop Server) | `~/.local/share/com.example.ariami_desktop/` |
| CLI | `~/.ariami_cli/`, or `$ARIAMI_DATA_DIR` when set |

The server keeps its data outside your music folder, so deleting the data
folder never touches your music.

Well-known files inside it include `users.json`, `sessions.json`,
`catalog.db`, `metadata_cache.json`, `music_discovery.json`,
`listening_stats.db`, `pinned_items.db`, `hidden_items.db`,
`playlist_edits.db`, `playlist_images.db`, `artist_images.db`,
`device_names.json`, `client_license.txt`, `artwork_cache/` and
`transcoded_cache/`.

**Note:** deleting `users.json` permanently removes all registered accounts. On
the next server start Ariami acts like a fresh installation, and the first
person to register becomes the new admin.

CLI host commands for the default data directory:

```bash
rm -f ~/.ariami_cli/sessions.json ~/.ariami_cli/users.json
```

Desktop auth files on macOS:

```bash
rm -f "$HOME/Library/Application Support/com.example.ariamiDesktop/sessions.json"
rm -f "$HOME/Library/Application Support/com.example.ariamiDesktop/users.json"
```

---

## Mobile clients

Session data is on the device (secure storage). Use in-app logout or clear app
data. The desktop `defaults` commands above do not touch it. Clearing app data
also removes the local library copy and any downloaded tracks.
