import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is read from android/key.properties (gitignored). When that
// file is absent (CI, other machines) the release build falls back to the debug
// key below so `flutter build apk` still works without secrets present.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "dev.pitch.pitch_app"
    // device_info_plus (via supabase_flutter) requires compileSdk 36; the
    // Flutter default is still 35, so pin it here.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.pitch.pitch_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Only attach the real signing config when we actually have it. The
            // "you must have a keystore" rule is enforced below, at EXECUTION
            // time, not here.
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

// NEVER silently fall back to the debug key: a debug-signed release cannot be
// updated over a real install and is rejected by Play, and the old fallback made
// that failure invisible until upload (penetration review 2026-07-07).
//
// But this check used to live INSIDE `buildTypes.release { }`, and Gradle
// evaluates that block at CONFIGURATION time for every invocation - so it threw
// on `flutter build apk --debug`, `flutter run`, and `flutter test` too. Nobody
// without the release keystore could build the app at all, which is every fresh
// clone and every CI machine (whole-system review #2, 2026-07-28).
//
// Check when a release artifact is actually being assembled, and only then.
gradle.taskGraph.whenReady {
    val buildingRelease = allTasks.any { task ->
        val n = task.name
        (n.startsWith("assemble") || n.startsWith("bundle") || n.startsWith("package")) &&
            n.contains("Release")
    }
    if (buildingRelease && !keystorePropertiesFile.exists()) {
        throw GradleException(
            "android/key.properties is missing - refusing to build an " +
            "unsigned/debug-signed release. Create it from the release " +
            "keystore before building. (Debug builds do not need it.)"
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
