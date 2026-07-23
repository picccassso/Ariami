# Building from source

Facts here come from `pubspec.yaml`, `android/app/build.gradle.kts`,
`ios/Runner.xcodeproj/project.pbxproj`, and `ariami_mobile/third_party/`.
For end-user install instructions (APK download, etc.), see the top-level
repository `README.md` instead — this page is for building the app yourself.

## Prerequisites

- **Flutter SDK** with Dart `^3.5.0` (`pubspec.yaml` → `environment.sdk`).
- This package depends on `ariami_core` via a relative path
  (`path: ../ariami_core` in `pubspec.yaml`), so it must be built from inside
  a full checkout of the Ariami monorepo — it will not resolve on its own if
  copied out in isolation.
- **Android:** JDK 17 (`compileOptions`/`kotlin.compilerOptions.jvmTarget` are
  both set to Java/Kotlin 17 in `android/app/build.gradle.kts`).
- **iOS:** Xcode with a deployment target of **iOS 15.0**
  (`IPHONEOS_DEPLOYMENT_TARGET = 15.0` throughout
  `ios/Runner.xcodeproj/project.pbxproj`), and CocoaPods (standard for any
  Flutter iOS build).

## Getting dependencies

```bash
cd ariami_mobile
flutter pub get
```

Note the `dependency_overrides` in `pubspec.yaml`:

```yaml
dependency_overrides:
  just_audio:
    path: third_party/just_audio
```

This swaps in a **vendored fork of `just_audio` 0.10.5** (see
`third_party/just_audio/pubspec.yaml`,
`third_party/just_audio/CHANGELOG.md`) that adds a native iOS/macOS
equalizer (`DarwinEqualizer`, via `MTAudioProcessingTap`) — the upstream
package only ships an Android equalizer. `flutter pub get` picks this up
automatically; there's nothing extra to configure, but don't remove the
override or the iOS equalizer (`lib/services/audio/equalizer_service.dart`)
will stop working on iOS/macOS.

## Running in development

```bash
flutter run
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
built this way is signed with the shared Flutter debug key, not suitable for
distribution. To ship a real release build, add your own `signingConfig`
(keystore, alias, passwords) per the
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
to the original author's Apple Developer account — it will not work for your
build. In Xcode, open `ios/Runner.xcworkspace`, select the `Runner` target →
**Signing & Capabilities**, and set your own Team and a bundle identifier you
control before building for a real device or for distribution. Simulator
builds don't require this.

### App icon generation

Icons are generated via `flutter_launcher_icons` (dev dependency), configured
at the bottom of `pubspec.yaml` from three source images under `assets/`:
`Ariami_icon.png` (Android), `Ariami_icon_ios.png` (iOS, full-bleed since iOS
applies its own corner mask), and `Ariami_icon_foreground.png` /
`Ariami_icon_monochrome.png` (Android adaptive/Material You icon). Regenerate
with:

```bash
dart run flutter_launcher_icons
```

## Platform-declared capabilities (for reference)

These are declared in the platform manifests and are relevant if you're
modifying the native project files — see `docs/TROUBLESHOOTING.md` for the
user-facing implications of each:

- **iOS** (`ios/Runner/Info.plist`): camera (QR scanning), notifications,
  local network + Bonjour (`_googlecast._tcp`, Chromecast discovery),
  background audio mode, and `NSAllowsArbitraryLoads` (ATS fully disabled,
  required for Tailscale/CGNAT streaming).
- **Android** (`android/app/src/main/AndroidManifest.xml`): camera,
  notifications (`POST_NOTIFICATIONS`), legacy storage permissions
  (`maxSdkVersion=32`) plus granular media permissions for Android 13+,
  internet/network-state, wake lock, and three foreground service types
  (`mediaPlayback` for `audio_service`, `dataSync` for WorkManager-backed
  background downloads and the batch download notification). Also sets
  `android:usesCleartextTraffic="true"` app-wide for plain-HTTP servers.
