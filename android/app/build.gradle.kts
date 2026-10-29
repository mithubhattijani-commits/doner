plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.doner.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // Doner day-1 signing key. The CI workflow decodes the
    // KEYSTORE_BASE64 secret into android/app/doner.keystore and passes
    // the passwords via environment variables. The keystore file itself
    // is never committed to the repo (see .gitignore). Without it,
    // builds fall back to the standard debug key (local development
    // only) - never ship a build signed with a different key, or
    // installed users would need to uninstall before updating.
    val donerKeystoreFile = file("doner.keystore")
    if (donerKeystoreFile.exists()) {
        signingConfigs.create("doner") {
            storeFile = donerKeystoreFile
            storePassword = System.getenv("KEYSTORE_STORE_PASSWORD")
            keyAlias = "doner"
            keyPassword = System.getenv("KEYSTORE_KEY_PASSWORD")
        }
    }

    defaultConfig {
        applicationId = "com.doner.app"
        // Doner fixed: minSdk 24, targetSdk 36 (do not change without
        // a new release plan).
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        debug {
            if (donerKeystoreFile.exists()) {
                signingConfig = signingConfigs.getByName("doner")
            }
        }
        release {
            // Doner: NO shrinking, NO compression - an uncompressed
            // build is mandatory (a compressed build previously crashed
            // on the user's phone). R8 / resource shrinking stay OFF.
            isMinifyEnabled = false
            isShrinkResources = false
            if (donerKeystoreFile.exists()) {
                signingConfig = signingConfigs.getByName("doner")
            } else {
                signingConfig = signingConfigs.getByName("debug")
            }
        }
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
