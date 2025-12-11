# BMA CLI - Full Rebuild Commands

## Quick Rebuild (most cases)

```bash
cd /Users/alex/Desktop/BMA/bma_cli
flutter build web -t lib/web/main.dart
```

Then hard refresh browser: **Cmd+Shift+R** (Mac) or **Ctrl+Shift+R** (Windows/Linux)

---

## Full Clean Rebuild (when quick rebuild doesn't work)

```bash
cd /Users/alex/Desktop/BMA/bma_cli
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
cd /Users/alex/Desktop/BMA/bma_cli

# Stop any running server first (Ctrl+C or kill the process)

# Remove all build artifacts
flutter clean
rm -rf build/
rm -rf .dart_tool/

# Reinstall dependencies
flutter pub get

# Rebuild web UI
flutter build web -t lib/web/main.dart

# Restart the server
dart run bin/bma_cli.dart start
```

Then open a fresh **Incognito/Private window** to bypass all caching.

### Optional: Reset Config (start fresh setup)

```bash
# Remove CLI config files (will require re-running setup)
rm -rf ~/.bma_cli/
```

This removes:
- Saved music folder path
- Server settings
- PID file
- Any other CLI configuration

---

## One-Liner for Terminal

```bash
cd /Users/alex/Desktop/BMA/bma_cli && flutter clean && flutter pub get && flutter build web -t lib/web/main.dart
```

---

## Compile to Executable (for deployment)

Build a standalone binary that runs without Dart installed:

```bash
cd /Users/alex/Desktop/BMA/bma_cli

# Build web UI first
flutter build web -t lib/web/main.dart

# Compile CLI to native executable
dart compile exe bin/bma_cli.dart -o bma_cli

# Run it
./bma_cli start
```

To install globally:

```bash
dart compile exe bin/bma_cli.dart -o /usr/local/bin/bma_cli
chmod +x /usr/local/bin/bma_cli

# Then run from anywhere
bma_cli start
```

---

## Why This Is Needed

Flutter web compiles Dart to JavaScript. Unlike hot reload in debug mode, production web builds require:
1. **Recompilation** - `flutter build web` creates new JS bundles
2. **Cache busting** - Browsers aggressively cache JS files
3. **Server restart** - The CLI server serves the built files from `build/web/`

A simple browser refresh only reloads cached files - it doesn't trigger recompilation.
