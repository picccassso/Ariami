# Ariami Developer Guide

Guide for building Ariami from source.

## Prerequisites

- **Dart SDK**: 3.5.0+
- **Flutter SDK**: Latest stable
- **Platform tools**:
  - Android: Android Studio
  - iOS: Xcode (macOS only)
  - Desktop: Platform-specific build tools

## Setup

```bash
# Install dependencies for all packages
cd ariami_core && dart pub get && cd ..
cd ariami_mobile && flutter pub get && cd ..
cd ariami_desktop && flutter pub get && cd ..
cd ariami_cli && flutter pub get && cd ..
```

## Running

### Desktop Server

```bash
cd ariami_desktop
flutter run -d macos    # or linux/windows
```

### CLI Server

```bash
cd ariami_cli
flutter build web -t lib/web/main.dart  # Build web UI first
dart run bin/ariami_cli.dart start
```

### Mobile App

```bash
cd ariami_mobile
flutter run
```

## Building

### Mobile

```bash
cd ariami_mobile
flutter build apk       # Android
flutter build ios       # iOS
```

### Desktop

```bash
cd ariami_desktop
flutter build macos     # or linux/windows
```

### CLI

```bash
cd ariami_cli
flutter build web -t lib/web/main.dart
dart compile exe bin/ariami_cli.dart -o ariami_cli
```

## Troubleshooting

### Build issues
```bash
flutter clean && flutter pub get
```

### Port conflicts
```bash
lsof -i :8080
dart run bin/ariami_cli.dart start --port 8081
```

### Desktop not building
```bash
flutter config --enable-macos-desktop   # or linux/windows
flutter doctor
```

## Raspberry Pi Performance Testing

### Test Environment Setup

**Supported Pi Models:**
- Raspberry Pi 4 (2GB+ RAM recommended)
- Raspberry Pi 5 (all configurations)

**Prerequisites:**
- Raspberry Pi OS (64-bit recommended)
- Dart SDK installed
- Compiled CLI binary (`dart compile exe bin/ariami_cli.dart -o ariami_cli`)

### Performance Test Checklist

Run these tests to validate multi-user performance on Pi:

#### 1. Basic Functionality
- [ ] Server starts without errors
- [ ] Web UI loads in browser
- [ ] QR code generates correctly
- [ ] Mobile app connects via QR scan

#### 2. Single User Tests
- [ ] User registration completes in <2 seconds
- [ ] User login completes in <1 second
- [ ] Library scan completes (note time for your library size)
- [ ] Single stream plays without buffering
- [ ] Transcoding works (if FFmpeg installed)

#### 3. Multi-User Concurrent Tests
- [ ] 2 users can register simultaneously
- [ ] 2 users can login simultaneously
- [ ] 2 users can stream different songs concurrently
- [ ] No audio dropouts during concurrent streaming
- [ ] Dashboard shows correct connected/streaming counts

#### 4. Load Tests
- [ ] 5 concurrent streams (same or different users)
- [ ] Server remains responsive during streaming
- [ ] Memory usage stays stable (check with `htop`)
- [ ] CPU usage acceptable (<80% sustained)

#### 5. Stress Tests
- [ ] Rapid login/logout cycles (10x)
- [ ] Multiple stream ticket requests in quick succession
- [ ] Server recovers gracefully after high load

### Expected Performance Benchmarks

| Operation | Pi 4 (4GB) | Pi 5 |
|-----------|------------|------|
| User registration (bcrypt) | <2s | <1s |
| User login (bcrypt verify) | <1s | <0.5s |
| Session creation | <50ms | <30ms |
| Stream ticket issuance | <10ms | <5ms |
| Concurrent streams (stable) | 3-5 | 5-10 |

### Performance Tips

1. **Bcrypt cost factor**: Default is 10. If registration/login is too slow, consider reducing to 8 (less secure but faster).

2. **Memory management**: JSON stores are kept in-memory. With many users/sessions, monitor RAM usage.

3. **Transcoding**: Disable or use lower quality presets on Pi 4 to reduce CPU load.

4. **Storage**: Use fast storage (USB SSD) for music library to improve scan times.

5. **Network**: Wired ethernet recommended for multiple concurrent streams.

### Monitoring Commands

```bash
# CPU and memory usage
htop

# Disk I/O
iotop

# Network connections
ss -tuln | grep 8080

# Server process stats
ps aux | grep ariami

# Check server logs (foreground mode)
./ariami_cli start  # First run shows logs
```

### Known Limitations

- **Pi 4 (2GB)**: May struggle with >3 concurrent transcoded streams
- **SD card storage**: Slower library scans, prefer USB SSD
- **WiFi**: Higher latency than ethernet, may affect streaming quality

### Automated Test Suite

Run the full test suite on Pi to verify implementation:

```bash
cd ariami_core
dart test
```

All 85 tests should pass. If tests fail on Pi but pass on desktop, check for:
- Timing-sensitive tests (may need tolerance adjustments)
- File system permission issues
- Memory constraints
