# Local reset (Ariami)

This file is a **quick reference** for developers and power users who want to wipe **local app preferences and server auth state** on a machine (for example after renaming the app, debugging onboarding, or clearing logins). It does **not** remove your music library folder from disk; it only affects preferences, optional auth JSON, and anything else you explicitly delete using the commands below.

**Quit Ariami** (desktop app and/or CLI server) before running file-deletion commands so nothing overwrites the files while you edit them.

---

## Flutter / macOS preferences (`defaults`)

Ariami Desktop stores setup and folder path in `NSUserDefaults`. Flutter prefixes keys with `flutter.` (for example `flutter.setup_completed`).

Replace the bundle id if yours differs (check the built `.app` or `macos/Runner/Configs/AppInfo.xcconfig`).

```bash
# Wipe all defaults for the app (typical “full prefs reset”)
defaults delete com.example.ariamiDesktop
killall cfprefsd 2>/dev/null
```

Legacy bundle id from before a rename (only if you still have leftovers):

```bash
defaults delete com.example.bmaDesktop
killall cfprefsd 2>/dev/null
```

Optional: delete only setup + saved music folder path, not every key:

```bash
defaults delete com.example.ariamiDesktop flutter.setup_completed
defaults delete com.example.ariamiDesktop flutter.music_folder_path
killall cfprefsd 2>/dev/null
```

---

## Server auth (sessions and users)

**Note:** Deleting the `users.json` file will permanently remove all registered accounts. The next time you start the Ariami server, it will act as if it's a fresh installation and the first person to register will become the new admin.

Desktop (default Application Support path for this bundle):

```bash
rm -f "$HOME/Library/Application Support/com.example.ariamiDesktop/sessions.json"
rm -f "$HOME/Library/Application Support/com.example.ariamiDesktop/users.json"
```

CLI host (`~/.ariami_cli`):

```bash
rm -f ~/.ariami_cli/sessions.json ~/.ariami_cli/users.json
```

---

## Sandboxed macOS build (if applicable)

If the app runs in a container, preferences may live under:

`~/Library/Containers/<BUNDLE_ID>/Data/Library/Preferences/<BUNDLE_ID>.plist`

Remove that plist with the app quit, then optionally `killall cfprefsd`.

---

## Mobile clients

Session data is on the device (secure storage). Use in-app logout or clear app data; it is not cleared by the desktop `defaults` commands above.
