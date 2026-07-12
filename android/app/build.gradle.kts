plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.rotem.quicksign"
    // receive_sharing_intent compiles against SDK 37.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.rotem.quicksign"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Release AABs/APKs are signed with the upload keystore when
    // android/app/keystore.jks + KEYSTORE_* env vars are present (CI, via
    // GitHub Actions secrets — see .github/workflows/build-aab.yml). Falls
    // back to the debug key locally so `flutter build apk`/`flutter run
    // --release` keep working without that keystore.
    signingConfigs {
        create("release") {
            val keystoreFile = file("keystore.jks")
            if (keystoreFile.exists()) {
                storeFile = keystoreFile
                storePassword = System.getenv("KEYSTORE_STORE_PASS")
                keyAlias = System.getenv("KEYSTORE_ALIAS")
                keyPassword = System.getenv("KEYSTORE_KEY_PASS")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (file("keystore.jks").exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    // DocumentFile: ergonomic wrapper over the SAF tree URI granted by the
    // default-folder picker (create/find/delete children).
    implementation("androidx.documentfile:documentfile:1.0.1")
}

flutter {
    source = "../.."
}
