# Ariami Desktop

GUI music server for Ariami. Indexes your music library and streams to mobile clients.

## Features

- Automatic library scanning (MP3, FLAC, M4A, WAV, OGG, and more)
- Real-time folder monitoring
- System tray integration
- QR code for mobile pairing

## Building

```bash
cd ariami_desktop
flutter pub get
flutter run -d macos        # or linux/windows
flutter build macos         # or linux/windows
```

## Usage

1. Launch the app
2. Select your music folder
3. Wait for library scan
4. Scan the QR code with Ariami Mobile
