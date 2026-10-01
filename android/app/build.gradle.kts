import java.util.Properties
import java.io.FileInputStream

// --- 1. KEYSTORE LOGIC BLOCK ---
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    packaging {
        jniLibs {
            keepDebugSymbols += "**/*.so"
        }
    }

    namespace = "com.portablecook.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // --- 2. SIGNING CONFIGURATION ---
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    compileOptions {
        // --- ADDED FOR DESUGARING ---
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        
        applicationId = "com.portablecook.app"

        // flutter_local_notifications requires minSdk 21 for some features
        minSdk = flutter.minSdkVersion 
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // --- ADDED FOR DESUGARING ---
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // --- 3. UPDATED SIGNING CONFIG ---
            // We changed this from "debug" to "release"
            signingConfig = signingConfigs.getByName("release")
            
            
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

// --- ADDED THIS BLOCK FOR DESUGARING ---
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}