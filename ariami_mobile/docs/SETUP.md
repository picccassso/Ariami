# First-run setup guide

Step-by-step walkthrough of connecting Ariami Mobile to a server for the
first time, matching the actual screen sequence in `lib/screens/`. If
anything here doesn't go as described, jump to
[TROUBLESHOOTING.md](TROUBLESHOOTING.md).

Before you start, you need a running Ariami server (Desktop app/server or
CLI/headless server) that has already been through its own setup — this
guide only covers the mobile side. See the top-level repository `README.md`
for server setup.

## 1. Welcome screen

The app opens to a welcome screen (`lib/screens/welcome_screen.dart`) with a
single **Connect to Desktop** button. Tap it to begin.

## 2. Network check

Next is a screen explaining the two ways the app can reach a server
(`lib/screens/setup/tailscale_check_screen.dart`):

- **Local network** — phone and server on the same Wi‑Fi, no extra setup.
- **Remote access** — install and connect [Tailscale](https://tailscale.com)
  on both the phone and the server to reach it away from home.

The screen auto-checks for an active VPN interface and shows one of three
states: **Tailscale Ready**, **Tailscale Optional** (not detected — you can
still continue with local setup), or **Tailscale Not Connected** (installed
but inactive). None of these block you — every state has a **Continue**
button — this step is informational, not a hard requirement.

## 3. Pairing

Tap through to the QR scanner (`lib/screens/setup/qr_scanner_screen.dart`).
Point the camera at the QR code your Ariami server shows on its connection
screen (desktop) or web setup UI (CLI). If the camera can't be used, tap
**Manual entry** at the bottom instead and type the server's address
directly — see `lib/screens/setup/manual_server_entry_screen.dart`, and
[TROUBLESHOOTING.md](TROUBLESHOOTING.md#manual-ipport-entry-fails) for the
exact address formats it accepts.

## 4. Sign in or create an account

What happens next depends on the server's current state
(`lib/screens/setup/server_connection_router.dart`):

- **Server has no accounts yet** → you're taken to account creation
  (`lib/screens/register_screen.dart`) to become the server's first
  (owner) user.
- **Server already has accounts** (auth required) → you're taken to sign-in
  (`lib/screens/login_screen.dart`). If registration is still open, there's
  a **Create Account** link; otherwise you'll need an invite code or the
  owner's QR code (entered via Manual entry's optional invite-code field).
- **Server has no authentication enabled at all** → the app connects
  directly and skips straight to the next step.

## 5. Permissions

`lib/screens/setup/permissions_screen.dart` requests, in order:

1. **Notifications** — needed to show playback controls in the
   notification panel / lock screen. You can **Skip**, with a warning that
   you'll lose those controls.
2. **Storage / media access** (Android only — iOS doesn't need this, since
   the app's own sandbox is sufficient) — needed to download music for
   offline playback. You can **Skip**, with a warning that offline downloads
   won't work.

Both can be granted later from the OS Settings app if you skip them here —
see [TROUBLESHOOTING.md](TROUBLESHOOTING.md#no-lock-screennotification-controls-or-playback-stops-in-the-background).

## 6. You're in

Setup finishes at the main library screen. The server connection, session,
and device identity are saved on-device, so you won't need to repeat this
flow on future launches — the app reconnects automatically. To fully undo
setup (forget the server, sign out, and clear local data), use
**Disconnect Server** — see
[TROUBLESHOOTING.md](TROUBLESHOOTING.md#gathering-logs-and-resetting-app-state).
