# Building from source

Facts here come from `pubspec.yaml`, `android/app/build.gradle.kts`,
`ios/Runner.xcodeproj/project.pbxproj`, and the vendored packages under
`ariami_mobile/third_party/`. For end-user install instructions (APK
download and so on), see the top-level repository `README.md` instead. This
page is for building the app yourself.

## Prerequisites

- **Flutter SDK** with Dart `^3.5.0` (`pubspec.yaml` → `environment.sdk`).
  CI and release builds use Flutter 3.44.6
  (`.github/workflows/ci.yml`, `.github/workflows/release.yml`).
- This package depends on `ariami_core` via a relative path
  (`path: ../ariami_core` in `pubspec.yaml`), so build it from inside a full
  checkout of the Ariami monorepo. It won't resolve on its own if copied out
  in isolation.
- **Android:** JDK 17 (`compileOptions`/`kotlin.compilerOptions.jvmTarget`
  are both set to Java/Kotlin 17 in `android/app/build.gradle.kts`).
- **iOS:** Xcode, with a deployment target of **iOS 15.0**
  (`IPHONEOS_DEPLOYMENT_TARGET = 15.0` throughout
  `ios/Runner.xcodeproj/project.pbxproj`). The Xcode project uses Flutter's
  generated Swift package for plugin integration
  (`FlutterGeneratedPluginSwiftPackage` in `project.pbxproj`), so there's no
  checked-in Podfile to install.

## Getting dependencies

```bash
cd ariami_mobile
flutter pub get
```

`pubspec.yaml` overrides two dependencies with local copies in
`third_party/`:

```yaml
dependency_overrides:
  flutter_chrome_cast:
    path: third_party/flutter_chrome_cast
  just_audio:
    path: third_party/just_audio
```

- **`just_audio` 0.10.5** (see `third_party/just_audio/pubspec.yaml`)
  adds a native iOS/macOS equalizer (`DarwinEqualizer`, built on
  `MTAudioProcessingTap` in
  `third_party/just_audio/darwin/just_audio/Sources/just_audio/JAEqualizer.m`).
  Upstream only ships an Android equalizer, so
  `lib/services/audio/equalizer_service.dart` relies on this fork for
  iOS/macOS EQ support.
- **`flutter_chrome_cast` 1.4.6**
  (`third_party/flutter_chrome_cast/ARIAMI_PATCHES.md`) defaults a missing
  track content type to an empty string. Google Home Mini status messages can
  omit `trackContentType` for an in-band audio track, which upstream throws
  on, leaving the sender stuck on its last buffering status. Regression tests
  live in `test/services/cast/`.

`flutter pub get` picks both up automatically, so there's nothing extra to
configure. Removing either override brings the corresponding bug back.

## Running in development

```bash
flutter run
flutter test
```

## Building release artifacts

```bash
flutter build apk      # Android APK
flutter build appbundle  # Android App Bundle (for Play Store)
flutter build ios      # iOS (requires Xcode + a provisioning profile)
```

### Android signing

`android/app/build.gradle.kts` currently signs release builds with the
**debug** signing config:

```kotlin
buildTypes {
    release {
        // TODO: Add your own signing config for the release build.
        // Signing with the debug keys for now, so `flutter run --release` works.
        signingConfig = signingConfigs.getByName("debug")
    }
}
```

This is fine for local testing (`flutter run --release`), but a release APK
built this way is signed with the shared Flutter debug key and isn't
suitable for distribution. To ship a real release build, add your own
`signingConfig` (keystore, alias, passwords) per the
[Flutter Android deployment guide](https://docs.flutter.dev/deployment/android)
and point `release { signingConfig = ... }` at it. The Android
`applicationId` is `app.ariami.mobile` (`android/app/build.gradle.kts`).

### iOS signing

`ios/Runner.xcodeproj/project.pbxproj` ships with:

```
PRODUCT_BUNDLE_IDENTIFIER = com.example.ariamiMobile;
DEVELOPMENT_TEAM = QZTBSUBN77;
CODE_SIGN_STYLE = Automatic;
```

The bundle identifier is still the Flutter template placeholder
(`com.example.ariamiMobile`), and the checked-in `DEVELOPMENT_TEAM` belongs
to the original author's Apple Developer account, so it won't work for your
build. In Xcode, open `ios/Runner.xcworkspace`, select the `Runner` target →
**Signing & Capabilities**, and set your own Team and a bundle identifier you
control before building for a real device or for distribution. Simulator
builds don't require this.

### App icon generation

Icons are generated via `flutter_launcher_icons` (dev dependency), configured
at the bottom of `pubspec.yaml` from four source images under `assets/`:
`Ariami_icon.png` (Android), `Ariami_icon_ios.png` (iOS, full-bleed since iOS
applies its own corner mask), plus `Ariami_icon_foreground.png` and
`Ariami_icon_monochrome.png` for the Android adaptive icon and the themed
Material You icon, on a `#1b1f20` background. Regenerate with:

```bash
dart run flutter_launcher_icons
```

## Platform-declared capabilities (for reference)

These are declared in the platform manifests and are relevant if you're
modifying the native project files. See `docs/TROUBLESHOOTING.md` for the
user-facing implications of each:

- **iOS** (`ios/Runner/Info.plist`): camera (QR scanning), notifications,
  local network + Bonjour (`_googlecast._tcp`, Chromecast discovery),
  background audio mode, and `NSAllowsArbitraryLoads` (ATS fully disabled,
  required for Tailscale/CGNAT streaming).
- **Android** (`android/app/src/main/AndroidManifest.xml`): camera,
  notifications (`POST_NOTIFICATIONS`), legacy storage permissions
  (`maxSdkVersion=32`) plus granular media permissions for Android 13+,
  internet/network-state, wake lock, and three foreground service
  declarations covering two types (`mediaPlayback` for `audio_service`,
  `dataSync` for WorkManager-backed background downloads and the batch
  download notification). It also sets
  `android:usesCleartextTraffic="true"` app-wide for plain-HTTP servers.
