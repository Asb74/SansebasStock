import java.io.FileInputStream
import java.util.Properties
import java.util.regex.Pattern

// Lee versionName (antes del '+') desde pubspec.yaml
fun getFlutterVersionName(): String {
    val pubspecFile = rootProject.file("pubspec.yaml")
    if (!pubspecFile.exists()) {
        println("pubspec.yaml not found at ${pubspecFile.absolutePath}, using default versionName 1.0.0")
        return "1.0.0"
    }

    val text = pubspecFile.readText()
    // Soporta: version: 1.0.1+3  o  version: "1.0.1+3"
    val regex = Pattern.compile("""version:\s*["']?(\d+\.\d+\.\d+)""")
    val matcher = regex.matcher(text)
    return if (matcher.find()) matcher.group(1) else "1.0.0"
}

// Lee versionCode (después del '+') desde pubspec.yaml
fun getFlutterVersionCode(): Int {
    val pubspecFile = rootProject.file("pubspec.yaml")
    if (!pubspecFile.exists()) {
        println("pubspec.yaml not found at ${pubspecFile.absolutePath}, using default versionCode 1")
        return 1
    }

    val text = pubspecFile.readText()
    // Soporta: version: 1.0.1+3  o  version: "1.0.1+3"
    val regex = Pattern.compile("""version:\s*["']?\d+\.\d+\.\d+\+(\d+)""")
    val matcher = regex.matcher(text)
    return if (matcher.find()) matcher.group(1).toInt() else 1
}

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

        // AHORA se leen desde pubspec.yaml
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
