import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.flutter_video_editor"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.motiongr.videoedit"
        minSdk = maxOf(21, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val keystorePropertiesFile = rootProject.file("key.properties")
            if (keystorePropertiesFile.exists()) {
                val keystoreProperties = Properties()
                keystoreProperties.load(FileInputStream(keystorePropertiesFile))
                storeFile = file(keystoreProperties.getProperty("storeFile") ?: "upload-keystore.jks")
                storePassword = keystoreProperties.getProperty("storePassword") ?: System.getenv("KEYSTORE_STORE_PASSWORD")
                keyAlias = keystoreProperties.getProperty("keyAlias") ?: System.getenv("KEYSTORE_KEY_ALIAS")
                keyPassword = keystoreProperties.getProperty("keyPassword") ?: System.getenv("KEYSTORE_KEY_PASSWORD")
            } else {
                val keystorePath = System.getenv("KEYSTORE_PATH")
                val keystoreStorePassword = System.getenv("KEYSTORE_STORE_PASSWORD")
                val keystoreKeyAlias = System.getenv("KEYSTORE_KEY_ALIAS")
                val keystoreKeyPassword = System.getenv("KEYSTORE_KEY_PASSWORD")

                if (keystorePath != null && keystoreStorePassword != null && keystoreKeyAlias != null && keystoreKeyPassword != null) {
                    storeFile = file(keystorePath)
                    storePassword = keystoreStorePassword
                    keyAlias = keystoreKeyAlias
                    keyPassword = keystoreKeyPassword
                } else {
                    // Fallback to debug signing when no credentials are available
                    storeFile = null
                    storePassword = null
                    keyAlias = null
                    keyPassword = null
                }
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    buildTypes {
        release {
            val releaseSigning = signingConfigs.getByName("release")
            signingConfig = if (releaseSigning.storeFile?.exists() == true || System.getenv("KEYSTORE_BASE64") != null) {
                releaseSigning
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
    implementation("androidx.media3:media3-transformer:1.5.1")
    implementation("androidx.media3:media3-effect:1.5.1")
    implementation("androidx.media3:media3-common:1.5.1")
    implementation("androidx.media3:media3-exoplayer:1.5.1")
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}