# BMA Setup Guide

Welcome to **BMA (Basic Music App)** - a cross-platform personal music streaming system.

## What is BMA?

BMA lets you stream your personal music library from a server (your desktop or a headless server) to your mobile device. It consists of:

- **Desktop App** - A GUI server for macOS, Linux, or Windows
- **CLI App** - A headless server for Raspberry Pi or remote servers
- **Mobile App** - An Android/iOS client that connects to your server
- **Core Library** - Shared logic used by both server apps

## Prerequisites

Before you begin, ensure you have:

- **Dart SDK**: Version 3.9.2 or higher
  - Download from: https://dart.dev/get-dart
  - Verify installation: `dart --version`

- **Flutter SDK**: Latest stable version
  - Download from: https://flutter.dev/docs/get-started/install
  - Verify installation: `flutter --version`

- **Git** (to clone the repository)

- **A code editor** (VS Code, Android Studio, or IntelliJ recommended)

### Platform-Specific Requirements

**For Mobile Development:**
- Android Studio (for Android)
- Xcode (for iOS, macOS only)
- A physical device or emulator

**For Desktop Development:**
- macOS: Xcode command-line tools
- Linux: Development libraries (varies by distribution)
- Windows: Visual Studio 2022 or later

## Initial Setup

### 1. Clone or Navigate to the Project

```bash
cd /path/to/BMA
```

### 2. Install Dependencies

Run these commands from the project root to set up all packages:

```bash
# Core library (required by desktop and CLI)
cd bma_core && dart pub get && cd ..

# Mobile app
cd bma_mobile && flutter pub get && cd ..

# Desktop app
cd bma_desktop && flutter pub get && cd ..

# CLI app
cd bma_cli && flutter pub get && cd ..
```

### 3. Verify Your Setup

Check that Flutter detects your devices:

```bash
flutter devices
```

You should see available devices/emulators listed.

## Running the Apps

### Option 1: Run the Desktop Server

The desktop app provides a GUI for your music server.

```bash
cd bma_desktop

# On macOS
flutter run -d macos

# On Linux
flutter run -d linux

# On Windows
flutter run -d windows
```

**First-time setup:**
1. The app will guide you through initial setup
2. Select your music folder
3. Wait for the library to scan
4. A QR code will be displayed for mobile app connection

### Option 2: Run the CLI Server

The CLI app is ideal for headless servers or Raspberry Pi.

```bash
cd bma_cli

# Build the web UI (required first time)
flutter build web -t lib/web/main.dart

# Start the server
dart run bin/bma_cli.dart start
```

**First-time setup:**
1. Server runs in foreground and opens your browser
2. Navigate to http://localhost:8080
3. Complete the web-based setup
4. Select your music folder and wait for scanning
5. Save the QR code displayed

**Subsequent runs:**
```bash
dart run bin/bma_cli.dart start   # Runs in background
dart run bin/bma_cli.dart status  # Check server status
dart run bin/bma_cli.dart stop    # Stop the server
```

**Compile to executable (optional):**
```bash
cd bma_cli
dart compile exe bin/bma_cli.dart -o bma_cli

# Now you can run it directly
./bma_cli start
```

### Running the Mobile App

Once your server (desktop or CLI) is running:

```bash
cd bma_mobile

# Run on connected device/emulator
flutter run

# Or specify a device
flutter run -d <device-id>
```

**Connecting to server:**
1. Launch the mobile app
2. Tap "Scan QR Code"
3. Grant camera permissions
4. Scan the QR code from your server
5. You're connected! Browse and stream your music

## Building for Production

### Mobile App

**Android APK:**
```bash
cd bma_mobile
flutter build apk
# Output: build/app/outputs/flutter-apk/app-release.apk
```

**iOS:**
```bash
cd bma_mobile
flutter build ios
# Open in Xcode for signing and distribution
```

### Desktop App

**macOS:**
```bash
cd bma_desktop
flutter build macos
# Output: build/macos/Build/Products/Release/bma_desktop.app
```

**Linux:**
```bash
cd bma_desktop
flutter build linux
# Output: build/linux/x64/release/bundle/
```

**Windows:**
```bash
cd bma_desktop
flutter build windows
# Output: build/windows/x64/runner/Release/
```

### CLI App

```bash
cd bma_cli

# Build web UI first
flutter build web -t lib/web/main.dart

# Compile to executable
dart compile exe bin/bma_cli.dart -o bma_cli

# Optional: Install globally
sudo cp bma_cli /usr/local/bin/
chmod +x /usr/local/bin/bma_cli
```

## Common Workflows

### Development Workflow

1. **Make changes to code**
2. **For hot reload** (mobile/desktop during `flutter run`):
   - Press `r` in terminal for hot reload
   - Press `R` for hot restart
3. **For code analysis**:
   ```bash
   flutter analyze  # In Flutter packages
   dart analyze     # In bma_core
   ```

### Testing

**Run all tests:**
```bash
# In Flutter packages (mobile, desktop, CLI)
cd bma_mobile  # or bma_desktop or bma_cli
flutter test

# In Dart package (core)
cd bma_core
dart test
```

**Run specific test:**
```bash
flutter test test/widget_test.dart
dart test test/library_test.dart
```

### Cleaning Build Files

If you encounter build issues:

```bash
cd bma_mobile  # or any package
flutter clean
flutter pub get
```

## Project Structure

```
BMA/
├── bma_core/          # Shared library logic
│   ├── lib/
│   │   ├── services/  # Library & server services
│   │   └── models/    # Data models
│   └── test/
├── bma_mobile/        # Mobile client app
│   ├── lib/
│   │   ├── screens/   # UI screens
│   │   ├── services/  # API, audio, cache, etc.
│   │   └── widgets/   # Reusable components
│   └── test/
├── bma_desktop/       # Desktop server app
│   ├── lib/
│   │   ├── screens/   # Setup & dashboard UI
│   │   └── services/  # Desktop-specific services
│   └── test/
└── bma_cli/           # CLI server app
    ├── bin/           # CLI entry point
    ├── lib/
    │   ├── commands/  # start, stop, status
    │   ├── services/  # Daemon, state, etc.
    │   └── web/       # Web setup UI
    └── test/
```

## Troubleshooting

### Dependencies Won't Install

```bash
# Clear pub cache and reinstall
flutter pub cache clean
cd bma_mobile && flutter pub get
```

### "No devices detected"

```bash
# For Android
flutter doctor --android-licenses  # Accept licenses
flutter devices                    # Should show devices

# For iOS (macOS only)
open -a Simulator  # Launch iOS simulator
```

### Desktop App Won't Build

```bash
# Ensure platform is enabled
flutter config --enable-macos-desktop   # macOS
flutter config --enable-linux-desktop   # Linux
flutter config --enable-windows-desktop # Windows

flutter doctor  # Check for issues
```

### CLI Server Won't Start

```bash
# Ensure web UI is built
cd bma_cli
flutter build web -t lib/web/main.dart

# Check for port conflicts
lsof -i :8080  # See what's using port 8080

# Try a different port
dart run bin/bma_cli.dart start --port 8081
```

### Mobile App Can't Connect to Server

1. **Check server is running**:
   ```bash
   # For CLI
   dart run bin/bma_cli.dart status
   ```

2. **Verify network connectivity**:
   - Ensure mobile and server are on same network
   - Check firewall settings (allow port 8080)
   - Try accessing http://SERVER_IP:8080/api/ping in browser

3. **Re-scan QR code** from server setup screen

### Library Not Scanning

1. **Check folder permissions** - Server must have read access
2. **Verify supported formats** - MP3, M4A, FLAC, WAV, AIFF, OGG, Opus, WMA, AAC, ALAC
3. **Check server logs** - Look for file access errors

### Audio Won't Play on Mobile

1. **Check mobile logs**:
   ```bash
   cd bma_mobile
   flutter logs | grep "BMA:"
   ```

2. **Verify permissions** - Storage and network access
3. **Test with different song** - File might be corrupted
4. **Check server streaming** - Visit http://SERVER_IP:8080/api/stream/SONG_PATH in browser

## Getting Help

### Check Logs

**Mobile:**
```bash
cd bma_mobile
flutter run -v  # Verbose logging
```

**Desktop:**
```bash
cd bma_desktop
flutter run -v -d macos  # or linux/windows
```

**CLI:**
```bash
cd bma_cli
dart run bin/bma_cli.dart start  # Foreground mode to see logs
```

### Verify Installation

```bash
flutter doctor -v  # Detailed diagnostics
dart --version     # Check Dart version
```

### Check Dependencies

```bash
cd bma_mobile  # or any package
flutter pub outdated  # Check for outdated packages
```

## Next Steps

1. **Explore the codebase** - Start with CLAUDE.md for architecture details
2. **Run tests** - Ensure everything works: `flutter test` / `dart test`
3. **Customize** - Modify UI, add features, or extend functionality
4. **Deploy** - Build for your target platforms and distribute

## Additional Resources

- **Flutter Documentation**: https://flutter.dev/docs
- **Dart Documentation**: https://dart.dev/guides
- **Project Documentation**: See CLAUDE.md for detailed architecture and development workflow

---

**Happy Streaming!** 🎵
