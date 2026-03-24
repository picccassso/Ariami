pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            val localPropertiesFile = file("local.properties")
            if (localPropertiesFile.exists()) {
                localPropertiesFile.inputStream().use { properties.load(it) }
            }

            val flutterSdkPathFromLocalProperties = properties.getProperty("flutter.sdk")
            val flutterSdkPathFromEnv = System.getenv("FLUTTER_ROOT")
            val flutterSdkPath = flutterSdkPathFromLocalProperties ?: flutterSdkPathFromEnv

            require(!flutterSdkPath.isNullOrBlank()) {
                "Flutter SDK path not found. Set flutter.sdk in android/local.properties or FLUTTER_ROOT."
            }

            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.9.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

include(":app")
