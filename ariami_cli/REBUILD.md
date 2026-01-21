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
# Remove CLI config files (will require re-running setup)
rm -rf ~/.ariami_cli/
```

This removes:
- Saved music folder path
- Server settings
- PID file
- Any other CLI configuration

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
dart compile exe bin/ariami_cli.dart -o ariami_cli

# Run it
./ariami_cli start
```

To install globally:

```bash
dart compile exe bin/ariami_cli.dart -o /usr/local/bin/ariami_cli
chmod +x /usr/local/bin/ariami_cli

# Then run from anywhere
ariami_cli start
```

---

## Build Raspberry Pi Release (ARM64)

For building ARM64 releases for Raspberry Pi directly from your Mac using Docker:

### Prerequisites
- Docker Desktop installed and running
- Flutter SDK installed on Mac
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

# Run the build script
./build-pi-release-mac.sh
```

The script will:
1. Clean previous builds
2. Build the web UI natively on Mac
3. Pull Dart dependencies in Docker container
4. Compile ARM64 Linux binary using Docker (--platform linux/arm64)
5. Create release directory structure
6. Copy all necessary files (binary, web UI, SETUP.txt)
7. Package everything into `ariami-cli-raspberry-pi-arm64-v1.9.0_testing.zip`
8. Verify the binary is correct architecture

### Why This Works on M2/M3 Macs

Apple Silicon (M1/M2/M3) is ARM64, same as Raspberry Pi. Docker runs the Linux ARM64 container natively - no emulation needed. This makes compilation fast.

On Intel Macs, Docker will use emulation (slower but still works).

### Output

Same as Pi build - a ready-to-distribute zip file containing:
- `ariami_cli` - Compiled ARM64 Linux executable
- `web/` - Built Flutter web UI
- `SETUP.txt` - User instructions

### Updating Version

To change the version number, edit `build-pi-release-mac.sh`:
```bash
VERSION="1.9.0_testing"  # Change this line
```

### Troubleshooting

**"Docker is not running"**:
- Open Docker Desktop app
- Wait for it to fully start (whale icon in menu bar)

**"Cannot connect to Docker daemon"**:
- Restart Docker Desktop
- Check Docker Desktop → Preferences → Resources

**Build is slow**:
- First run downloads the Dart Docker image (~500MB)
- Subsequent runs are much faster (image is cached)

---

## Why This Is Needed

Flutter web compiles Dart to JavaScript. Unlike hot reload in debug mode, production web builds require:
1. **Recompilation** - `flutter build web` creates new JS bundles
2. **Cache busting** - Browsers aggressively cache JS files
3. **Server restart** - The CLI server serves the built files from `build/web/`

A simple browser refresh only reloads cached files - it doesn't trigger recompilation.
