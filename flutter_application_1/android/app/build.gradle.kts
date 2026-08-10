plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.flutter_application_1"
    
    // KUNCI SUKSES 1: Paksa kompilasi modul utama naik ke level 36 untuk mendukung androidx.camera
    compileSdk = 35
    
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.flutter_application_1"
        minSdk = flutter.minSdkVersion
        
        // KUNCI SUKSES 2: Selarasakan target SDK aplikasi ke level 36
        targetSdk = 35
        
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

// Tambahkan blok ini di baris paling bawah berkas build.gradle.kts Anda
subprojects {
    afterEvaluate {
        val androidExtension = project.extensions.findByName("android")
        if (androidExtension != null) {
            configure<com.android.build.gradle.BaseExtension> {
                compileSdkVersion(34)
                defaultConfig {
                    targetSdkVersion(34)
                }
            }
        }
    }
}

// PAKSA GRADLE MENURUNKAN VERSINYA KEMBALI AGAR COCOK DENGAN SDK 34 ANDA
configurations.all {
    resolutionStrategy {
        force("androidx.core:core:1.13.1")
        force("androidx.core:core-ktx:1.13.1")
    }
}