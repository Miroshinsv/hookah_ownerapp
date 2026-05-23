import java.util.Properties
import java.util.Base64
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val keystorePropertiesFile = rootProject.file("app/key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localProperties.load(FileInputStream(localPropertiesFile))
}

// Flutter 3.x передаёт --dart-define значения через Gradle project property 'dart-defines'
// (с дефисом), а НЕ через local.properties 'dart.defines' (с точкой).
// Старый подход (local.properties) оставлен как запасной вариант для совместимости.
fun dartDefines(): Map<String, String> {
    val raw = (project.findProperty("dart-defines") as? String)
        ?: localProperties.getProperty("dart.defines")
        ?: return emptyMap()
    return raw.split(",").associate { entry ->
        val decoded = String(Base64.getDecoder().decode(entry))
        val idx = decoded.indexOf('=')
        if (idx >= 0) decoded.substring(0, idx) to decoded.substring(idx + 1)
        else decoded to ""
    }
}

val dartDefines = dartDefines()

android {
    namespace = "ru.hookahorder.hookah_admin"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_21.toString()
    }

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        applicationId = "ru.hookahorder.hookah_admin"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        buildConfigField(
            "String",
            "YANDEX_MAPS_API_KEY",
            "\"${dartDefines["YANDEX_MAPS_API_KEY"] ?: ""}\""
        )
        buildConfigField(
            "String",
            "YANDEX_GEOCODER_API_KEY",
            "\"${dartDefines["YANDEX_GEOCODER_API_KEY"] ?: ""}\""
        )
    }

    signingConfigs {
        create("release") {
            keyAlias     = keystoreProperties["keyAlias"]     as String? ?: ""
            keyPassword  = keystoreProperties["keyPassword"]  as String? ?: ""
            storeFile    = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String? ?: ""
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("com.yandex.android:maps.mobile:4.22.0-lite")
}
