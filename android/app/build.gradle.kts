import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release-Signierung über android/key.properties (NICHT committen – steht in
// .gitignore). Enthält keyAlias, keyPassword, storeFile, storePassword.
// Fehlt die Datei (z. B. frischer Clone), fallen Release-Builds auf die
// Debug-Keys zurück (robuste Variante: Build bricht NICHT ab, sondern
// warnt; signiert damit aber NICHT Play-Store-tauglich).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
} else {
    logger.warn("WARNUNG: android/key.properties fehlt – Release-Build wird mit dem DEBUG-Keystore signiert (nur für lokale Tests, NICHT für den Play Store geeignet).")
}

android {
    namespace = "com.wisp.app"
    // permission_handler_android (v14) benötigt compileSdk 37.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        // Release-Signierung nur anlegen, wenn key.properties existiert;
        // sonst greift in buildTypes der Debug-Fallback.
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.wisp.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 28
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Release mit dem echten Keystore signieren, wenn key.properties
            // vorhanden ist; sonst Debug-Keys (lokale Tests).
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
