import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Load keystore properties from android/key.properties
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")

if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

fun getKeystoreProp(name: String): String? {
    return keystoreProperties.getProperty(name)
}

android {
    namespace = "com.autiease.fyp2026"
    compileSdk = 36
    ndkVersion = "28.2.13676358"



    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    defaultConfig {
        applicationId = "com.autiease.fyp2026"
        minSdk = flutter.minSdkVersion
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        val alias = getKeystoreProp("keyAlias")
        val keyPass = getKeystoreProp("keyPassword")
        val storePass = getKeystoreProp("storePassword")
        val storeFilePath = getKeystoreProp("storeFile")

        if (alias != null && keyPass != null && storePass != null && storeFilePath != null) {
            create("release") {
                keyAlias = alias
                keyPassword = keyPass
                storeFile = file(storeFilePath)
                storePassword = storePass
            }
        }
    }

    buildTypes {
        getByName("release") {
            if (signingConfigs.findByName("release") != null) {
                signingConfig = signingConfigs.getByName("release")
            }
            isMinifyEnabled = false
            isShrinkResources = false

        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation(platform("com.google.firebase:firebase-bom:33.1.0"))
    implementation("com.google.android.gms:play-services-auth:21.0.0")
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-firestore")
}

flutter {
    source = "../.."
}
