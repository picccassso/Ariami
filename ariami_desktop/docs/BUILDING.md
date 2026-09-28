# Building Ariami Desktop from Source

This supplements the "Building" section in the existing
`ariami_desktop/README.md` with platform-specific prerequisites, verified
against the project files and the workflows under `.github/`.

## Common prerequisites

- **Dart SDK 3.5.0+** (`ariami_desktop/pubspec.yaml`:
  `environment: sdk: ^3.5.0`)
- **Flutter SDK**, stable. The CI and release workflows pin Flutter 3.44.6
  (`.github/workflows/ci.yml`, `.github/workflows/release.yml`).
- The sibling `ariami_core` package checked out at `../ariami_core` relative
  to `ariami_desktop`. The dependency resolves from that checkout
  (`ariami_desktop/pubspec.yaml`:
  `ariami_core: { path: ../ariami_core }`).

```bash
cd ariami_desktop
flutter pub get
```

## Sonic transcoder (Rust FFI library)

Low/medium-quality server-side transcoding is powered by a bundled Rust
library ("Sonic") built from the `sonic/` directory at the repository root,
which is a **git submodule**. Each platform's build scripts compile it with:

```bash
cargo build --release --features aac-fdk --lib
```

so building with transcoding needs a working **Rust + Cargo** toolchain.
CMake or Xcode runs that Cargo command during the normal Flutter build, so
you never invoke it by hand.

If you cloned the repository without submodules, fetch it first:

```bash
git submodule update --init --recursive
```

How each platform handles it:

- **macOS**: required. An Xcode build phase ("Build Sonic FFI" in
  `ariami_desktop/macos/Runner.xcodeproj/project.pbxproj`) runs Cargo and
  copies `libsonic_transcoder.dylib` into the app's `Frameworks` folder. The
  build fails if the submodule or Cargo is missing.
- **Linux**: optional. `ariami_desktop/linux/CMakeLists.txt` builds the
  library when `${SONIC_DIR}/Cargo.toml` exists and installs
  `libsonic_transcoder.so` into the bundle; otherwise it prints a warning
  ("Sonic source not found ... low/medium transcoding will be disabled") and
  the build continues:

  ```cmake
  # ariami_desktop/linux/CMakeLists.txt
  if(EXISTS "${SONIC_DIR}/Cargo.toml")
    add_custom_target(build_sonic_library ALL
      COMMAND ${CMAKE_COMMAND} -E env CARGO_TARGET_DIR=${SONIC_TARGET_DIR} cargo build --release --features aac-fdk --lib
      WORKING_DIRECTORY "${SONIC_DIR}" ...)
  else()
    message(WARNING "Sonic source not found at ${SONIC_DIR}; low/medium transcoding will be disabled.")
  endif()
  ```
- **Windows**: optional, same pattern.
  `ariami_desktop/windows/CMakeLists.txt` builds and installs
  `sonic_transcoder.dll` next to the executable when the submodule is
  present, and warns otherwise.

If the library is missing at run time, `TranscodingService.isSonicAvailable()`
returns false, low/medium transcode requests are refused, and the app logs
"transcoding will be disabled" (see `docs/TROUBLESHOOTING.md`).

## macOS

- **Minimum macOS version:** 12.0 (`MACOSX_DEPLOYMENT_TARGET = 12.0` in
  `ariami_desktop/macos/Runner.xcodeproj/project.pbxproj`).
- **Bundle identifier:** `com.example.ariamiDesktop`, with the app named
  `Ariami-Desktop` (`PRODUCT_NAME` and `PRODUCT_BUNDLE_IDENTIFIER` in
  `ariami_desktop/macos/Runner/Configs/AppInfo.xcconfig`).
- **Sandbox:** disabled (`com.apple.security.app-sandbox` is `false` in both
  `ariami_desktop/macos/Runner/Release.entitlements` and
  `DebugProfile.entitlements`).
- Xcode and the Flutter macOS desktop toolchain must be installed and
  accepted (`sudo xcodebuild -license` if you've never opened Xcode).
- **Rust + Cargo**, because the "Build Sonic FFI" phase runs as part of every
  app build (see above).

```bash
cd ariami_desktop
flutter run -d macos      # debug run
flutter build macos       # release build; produces Ariami-Desktop.app under build/macos/Build/Products/Release
```

The app icon is generated via `flutter_launcher_icons`
(`ariami_desktop/pubspec.yaml`, `flutter_launcher_icons: macos:` section),
sourced from `assets/Ariami_icon_macos.png`, pre-padded to Apple's icon grid
per the comment in `pubspec.yaml`.

## Windows

- **Windows 10 or later**: `ariami_desktop/windows/runner/runner.exe.manifest`
  declares the Windows 10/11 supportedOS GUID.
- Uses the standard Flutter Windows desktop toolchain (CMake plus a Visual
  Studio C++ toolchain), per
  `ariami_desktop/windows/CMakeLists.txt`
  (`cmake_minimum_required(VERSION 3.14)`). Enable the "Desktop development
  with C++" workload in Visual Studio if `flutter doctor` flags it as missing.
- **Rust + Cargo** for the Sonic transcoder; without the submodule the build
  warns and skips it (see above).
- Binary/product name: `ariami_desktop`
  (`set(BINARY_NAME "ariami_desktop")` in `windows/CMakeLists.txt`).
- Version info baked into the executable comes from
  `ariami_desktop/windows/runner/Runner.rc`, driven by `FLUTTER_VERSION_*`
  build defines. The literal `"4.2.0"` in that file is the Flutter template
  fallback, used only when the defines are absent; the real version always
  comes from `pubspec.yaml`'s `version:` field.

```bash
cd ariami_desktop
flutter run -d windows
flutter build windows     # produces build\windows\x64\runner\Release\
```

## Linux

- **Requires GTK 3 development headers** at build time
  (`ariami_desktop/linux/CMakeLists.txt`:
  `pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)`), plus the
  AppIndicator headers `tray_manager` needs for the system tray. The release
  workflow installs exactly this set (`.github/workflows/release.yml`):

  ```bash
  sudo apt-get update
  sudo apt-get install -y ninja-build libgtk-3-dev libblkid-dev liblzma-dev libayatana-appindicator3-dev
  ```

  Add `clang`, `cmake`, and `pkg-config` if your distro does not already have
  them; they are Flutter's general Linux desktop build prerequisites.
- **Rust + Cargo** if you want the Sonic transcoder built (see above); the
  build proceeds without it, just with transcoding disabled.
- Project/binary name: `ariami_desktop`
  (`ariami_desktop/linux/CMakeLists.txt`:
  `set(BINARY_NAME "ariami_desktop")`; `APPLICATION_ID` defaults to the
  Flutter template value `com.example.ariami_desktop`).
- The Linux window icon is **not** generated by `flutter_launcher_icons`
  (which has no Linux support, per the comment in
  `ariami_desktop/pubspec.yaml`); it is drawn from
  `ariami_desktop/linux/runner/resources/app_icon.png`.

```bash
cd ariami_desktop
flutter run -d linux
flutter build linux       # produces build/linux/x64/release/bundle/
```

## Release packaging

`.github/workflows/release.yml` builds all three desktop targets with Flutter
3.44.6 on release tags and packages them:

- macOS: `flutter build macos --release`, shipped as a `.dmg` built from
  `build/macos/Build/Products/Release/Ariami-Desktop.app`
- Windows: `flutter build windows --release`, zipped from
  `build/windows/x64/runner/Release`
- Linux: `flutter build linux --release`, packaged as an AppImage

## Running tests

`ariami_desktop/test/` contains widget and service-level unit tests:

```bash
cd ariami_desktop
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
```

CI runs `flutter analyze --no-fatal-infos --no-fatal-warnings` and
`flutter test` for this package (`.github/workflows/ci.yml`). The suites that
end in `_test.dart` cover the desktop download-limits and transcode-slots
services, the Spotify import service, the update-check service, the
onboarding help dialog, the Spotify import button and user-activity table
widgets, and a smoke test that constructs the app. Two extra scripts,
`test/test_change_processor_unit.dart` and `test/test_folder_watcher.dart`,
are manual harnesses; `flutter test` skips them because they do not end in
`_test.dart`.
