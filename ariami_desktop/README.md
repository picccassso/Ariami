# Ariami Desktop

GUI music server for Ariami. Indexes your music library and streams to mobile clients.

## Features

- Automatic library scanning (MP3, FLAC, M4A, WAV, OGG, and more)
- Real-time folder monitoring
- System tray integration (minimizes to tray instead of quitting)
- QR code for mobile pairing
- Multi-user authentication
- Dashboard showing connected users and devices with admin controls (kick devices, change passwords)
- Server-side audio transcoding with quality presets

## Building

```bash
cd ariami_desktop
flutter pub get
flutter run -d macos        # or linux/windows
flutter build macos         # or linux/windows
```

## Usage

1. Launch the app and follow the first-run wizard (Tailscale optional)
2. Select your music folder and wait for the library scan
3. **Create the owner account** when prompted (first account = server admin)
4. Scan the QR code with Ariami Mobile and **register** or log in
5. Use the dashboard with **owner sign-in** for admin actions (users, kick device, passwords)

The owner account is created on the desktop during setup, not from the phone. After the owner exists, new phone accounts register using the token in the server's QR code.
