import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing — reads either from `android/key.properties` (local Studio
// builds) or from environment variables (CI on Codemagic). Falls back to the
// debug keystore when neither is present so `flutter build apk --debug` and
// dev day-to-day work keep working without any local secrets.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

fun signingConfigured(): Boolean {
    val hasFileProps = keystoreProperties.containsKey("storeFile")
    val hasEnvVars = System.getenv("CM_KEYSTORE_PATH") != null &&
                     System.getenv("CM_KEYSTORE_PASSWORD") != null &&
                     System.getenv("CM_KEY_ALIAS") != null &&
                     System.getenv("CM_KEY_PASSWORD") != null
    return hasFileProps || hasEnvVars
}

android {
    namespace = "com.innawoods.innawoods"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (java.time backport).
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.innawoods.innawoods"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (signingConfigured()) {
            create("release") {
                if (System.getenv("CM_KEYSTORE_PATH") != null) {
                    storeFile = file(System.getenv("CM_KEYSTORE_PATH"))
                    storePassword = System.getenv("CM_KEYSTORE_PASSWORD")
                    keyAlias = System.getenv("CM_KEY_ALIAS")
                    // The innawoods keystore is PKCS12 format, which
                    // requires keyPassword == storePassword regardless of
                    // what keytool was told at generation time (it prints
                    // a warning and silently uses the store password for
                    // both). CM_KEY_PASSWORD as a separate env var is
                    // meaningless against this keystore; force the
                    // store password for both to avoid 'Given final
                    // block not properly padded' at sign-bundle time.
                    keyPassword = System.getenv("CM_KEYSTORE_PASSWORD")
                } else {
                    storeFile = file(keystoreProperties["storeFile"] as String)
                    storePassword = keystoreProperties["storePassword"] as String
                    keyAlias = keystoreProperties["keyAlias"] as String
                    keyPassword = keystoreProperties["storePassword"] as String
                }
            }
        }
    }

    buildTypes {
        release {
            // Use the real release keystore if it's configured (CI or a local
            // dev who set up key.properties); otherwise sign with debug so
            // `flutter run --release` still works on a dev machine.
            signingConfig = if (signingConfigured()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
