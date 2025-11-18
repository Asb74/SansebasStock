import java.io.FileInputStream
import java.util.Properties
import java.util.regex.Pattern

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.sansebas.stock"
    compileSdk = 35
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.sansebas.stock"
        minSdk = 23
        targetSdk = 35
        versionCode = getFlutterVersionCode()
        versionName = getFlutterVersionName()
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

fun getFlutterVersionName(): String {
    val pubspec = file("../../pubspec.yaml").readText()
    val regex = Pattern.compile("version:\\s*([0-9]+\\.[0-9]+\\.[0-9]+)")
    val matcher = regex.matcher(pubspec)
    return if (matcher.find()) matcher.group(1) else "1.0.0"
}

fun getFlutterVersionCode(): Int {
    val pubspec = file("../../pubspec.yaml").readText()
    val regex = Pattern.compile("version:\\s*[0-9]+\\.[0-9]+\\.[0-9]+\\+([0-9]+)")
    val matcher = regex.matcher(pubspec)
    return if (matcher.find()) matcher.group(1).toInt() else 1
}
