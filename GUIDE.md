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
