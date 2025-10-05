plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.fridge"

    // These come from the Flutter Gradle plugin
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.example.fridge"

        // Use 21+ for Flutter and local notifications; you can also do: minSdk = max(21, flutter.minSdkVersion)
        minSdk = flutter.minSdkVersion

        // Target SDK from Flutter plugin (keeps up to date with your Flutter SDK)
        targetSdk = flutter.targetSdkVersion

        // Version pulled from pubspec.yaml via Flutter plugin
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Java/Kotlin + Desugaring (needed for flutter_local_notifications v19.x)
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    // (Optional) If you have native libs or need to tweak packaging, add packaging options here.

    buildTypes {
        release {
            // TODO: set up your own signing config for release builds.
            // Using debug signing for convenience so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // Disable minification to avoid ML Kit issues
            isMinifyEnabled = false
            // proguardFiles(
            //     getDefaultProguardFile("proguard-android-optimize.txt"),
            //     "proguard-rules.pro"
            // )
        }
        debug {
            // Debug options if you need them
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Your Flutter/Gradle-managed Android deps go here when needed (usually none for pure Flutter).

    // Required for core library desugaring (Android Gradle Plugin 8.x+)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // If you ever add native Firebase deps (not needed for FlutterFire plugins), you would use the BOM:
    // implementation(platform("com.google.firebase:firebase-bom:33.4.0"))
    // implementation("com.google.firebase:firebase-analytics")
}
