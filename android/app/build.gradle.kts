import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keyProperties = Properties()
val keyPropertiesFile = rootProject.file("key.properties")
if (keyPropertiesFile.exists()) {
    keyPropertiesFile.inputStream().use(keyProperties::load)
}
val envProperties = Properties()
val envPropertiesFile = rootProject.file("../.env")
if (envPropertiesFile.exists()) {
    envPropertiesFile.inputStream().use(envProperties::load)
}
val hasReleaseSigning = listOf(
    "storeFile",
    "storePassword",
    "keyAlias",
    "keyPassword",
).all { !keyProperties.getProperty(it).isNullOrBlank() }
fun firstNonBlank(vararg values: String?): String? =
    values.firstOrNull { !it.isNullOrBlank() }?.trim()

val googleMapsAndroidApiKey = firstNonBlank(
    System.getenv("GOOGLE_MAPS_ANDROID_API_KEY"),
    project.findProperty("GOOGLE_MAPS_ANDROID_API_KEY") as String?,
    envProperties.getProperty("GOOGLE_MAPS_ANDROID_API_KEY"),
)

android {
    namespace = "com.marketflow.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.marketflow.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["GOOGLE_MAPS_ANDROID_API_KEY"] =
            googleMapsAndroidApiKey ?: "YOUR_GOOGLE_MAPS_ANDROID_API_KEY"
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                storeFile = file(keyProperties.getProperty("storeFile").trim())
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Fall back to the debug key until android/key.properties is configured.
            signingConfig = if (hasReleaseSigning) {
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
