# Ariami Mobile

Mobile client for Ariami. Streams music from Ariami Desktop or CLI servers.

## Features

- Stream and download music for offline playback
- Background playback with lock screen controls
- Queue management, shuffle, repeat
- Playlist creation and management
- QR code scanning for easy server connection
- User authentication (login/register) when the server has auth enabled
- Automatic quality switching based on network type (WiFi vs mobile data)
- Option to prefer local/cached files when connected to the server
- Listening stats for songs, albums, and artists

## Building

```bash
cd ariami_mobile
flutter pub get
flutter run                 # Development
flutter build apk           # Android
flutter build ios           # iOS
```

## Usage

1. Launch the app
2. Scan the QR code from your Ariami server
3. If auth is required, create an account or log in
4. Browse and stream your music library
