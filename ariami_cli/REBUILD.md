# Ariami CLI - Full Rebuild Commands

## Quick Rebuild (most cases)

```bash
cd ariami_cli
flutter build web -t lib/web/main.dart
```

Then hard refresh browser: **Cmd+Shift+R** (Mac) or **Ctrl+Shift+R** (Windows/Linux)

---

## Full Clean Rebuild (when quick rebuild doesn't work)

```bash
cd ariami_cli
flutter clean
flutter pub get
flutter build web -t lib/web/main.dart
```

Then in browser:
1. Open DevTools (Cmd+Option+I / F12)
2. Right-click refresh button → **"Empty Cache and Hard Reload"**

---

## Nuclear Option (everything fresh)

```bash
cd ariami_cli

# Stop any running server first
dart run bin/ariami_cli.dart stop  # or Ctrl+C if running in foreground

# Remove all build artifacts
flutter clean
rm -rf build/
rm -rf .dart_tool/

# Reinstall dependencies
flutter pub get

# Rebuild web UI
flutter build web -t lib/web/main.dart

# Restart the server
dart run bin/ariami_cli.dart start
```

Then open a fresh **Incognito/Private window** to bypass all caching.

### Optional: Reset Config (start fresh setup)

```bash
# Remove the whole CLI data directory (will require re-running setup)
rm -rf ~/.ariami_cli/
```

This removes the saved music folder path, server settings, accounts,
sessions, catalogue database, caches, and the PID file. If `ARIAMI_DATA_DIR`
is set, delete that directory instead. `./ariami_cli reset --factory` is the
safer equivalent: it stops a running server first and never touches the music
folder.

---

## One-Liner for Terminal

```bash
cd ariami_cli && flutter clean && flutter pub get && flutter build web -t lib/web/main.dart
```

---

## Compile to Executable (for deployment)

Build a standalone binary that runs without Dart installed:

```bash
cd ariami_cli

# Build web UI first
flutter build web -t lib/web/main.dart

# Compile CLI to native executable
dart build cli -o build/cli-release

# Run the bundled executable
./build/cli-release/bundle/bin/ariami_cli start
```

Keep the generated `bundle/bin` and `bundle/lib` directories together when
deploying. The executable loads native assets (for example `libsqlite3.so` on
Linux, `libsqlite3.dylib` on macOS, and `sqlite3.dll` on Windows) from the
adjacent bundle library directory.

To install globally, preserve that layout:

```bash
dart build cli -o build/cli-release
sudo mkdir -p /opt/ariami-cli
sudo cp -R build/cli-release/bundle/. /opt/ariami-cli/
sudo ln -sf /opt/ariami-cli/bin/ariami_cli /usr/local/bin/ariami_cli

# Then run from anywhere
ariami_cli start
```

---

## Build a Linux Release (ARM64 or x64)

For building Linux releases from your Mac using Docker. The default target is
ARM64 for Raspberry Pi; `--arch amd64` builds the linux-x64 variant instead.

### Prerequisites
- Docker Desktop installed and running
- Flutter SDK installed on Mac
- The `sonic/` submodule checked out (the script packages `libsonic_transcoder.so`)
- SETUP.txt file must exist in ariami_cli/ directory

### First-Time Setup

Install Docker Desktop if not already installed:
1. Download from https://www.docker.com/products/docker-desktop
2. Install and start Docker Desktop
3. Verify with: `docker --version`

### Build Release Package

```bash
cd ariami_cli

# Make build script executable (first time only)
chmod +x build-pi-release-mac.sh

# Run the build script (ARM64 by default)
./build-pi-release-mac.sh

# Or build the linux-x64 variant
./build-pi-release-mac.sh --arch amd64
```

The script will:
1. Clean previous builds
2. Fetch dependencies and build the web UI natively on Mac
3. Compile the Linux binary in Docker (`--platform linux/arm64` or `linux/amd64`)
4. Build `libsonic_transcoder.so` for the same architecture in Docker
5. Create release directory structure
6. Copy all necessary files (binary, web UI, SQLite library, Sonic library, SETUP.txt)
7. Package everything into `ariami-cli-raspberry-pi-arm64-v<version>.zip` (or `ariami-cli-linux-x64-v<version>.zip`)
8. Verify the binary, SQLite library, and Sonic library architectures

### Why This Works on M2/M3 Macs

Apple Silicon (M1/M2/M3) is ARM64, same as Raspberry Pi. Docker runs the Linux ARM64 container natively, so compilation is fast.

On Intel Macs, Docker uses emulation (slower but still works). The same applies to `--arch amd64` builds on Apple Silicon.

### Output

The result is a ready-to-distribute zip file containing:
- `ariami_cli` - Launcher for the bundled Linux executable
- `bin/ariami_cli` - Compiled Linux executable (ARM64 or x64, depending on `--arch`)
- `web/` - Built Flutter web UI
- `lib/libsqlite3.so` - Bundled SQLite native library for the catalogue
- `lib/libsonic_transcoder.so` - Bundled Sonic library for low/medium transcoding
- `SETUP.txt` - User instructions

### Updating Version

The release builder reads the version from `ariami_cli/pubspec.yaml` and refuses to build if these three sources disagree:

1. `ariami_cli/pubspec.yaml`
2. `ariami_core/pubspec.yaml`
3. `ariami_core/lib/app_version.dart` (`kAriamiVersion`)

Update all three to the same value before running `./build-pi-release-mac.sh`.

### Troubleshooting

**"Docker is not running"**:
- Open Docker Desktop app
- Wait for it to fully start (whale icon in menu bar)

**"Cannot connect to Docker daemon"**:
- Restart Docker Desktop
- Check Docker Desktop → Preferences → Resources

**Build is slow**:
- First run downloads the Flutter/Dart Docker image (~500MB)
- Subsequent runs are much faster (image is cached)

---

## Why This Is Needed

Flutter web compiles Dart to JavaScript. A production web build is a fresh artifact, and browsers treat it as static files, so:
1. **Recompilation** - `flutter build web` creates new JS bundles
2. **Cache busting** - Browsers aggressively cache JS files
3. **Server restart** - The CLI resolves the web asset directory at startup and serves the built files from `build/web/`

A simple browser refresh only reloads cached files, so it cannot pick up a changed Dart source.
