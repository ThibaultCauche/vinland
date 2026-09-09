plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.vinland"
    
    // ← FORCÉ À 36 (etait 35) : plusieurs plugins (flutter_plugin_android_lifecycle,
    // path_provider_android, shared_preferences_android...) exigent desormais
    // un compileSdk >= 36. Reste compatible avec le predictive back et les
    // notifications média (36 est retro-compatible avec 35).
    compileSdk = 36

    // ← Version la plus haute exigee parmi les plugins (integration_test)
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.vinland"
        
        // ← Vérifie que c'est bien 21 minimum (audio_service l'exige)
        minSdk = flutter.minSdkVersion
        
        // ← FORCÉ À 35 pour le Play Store et les dernières APIs
        targetSdk = 35
        
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
