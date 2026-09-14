import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Cle de release (voir android/key.properties, gitignore) : en local ce
// fichier pointe vers vinland-release-keystore/vinland-release.jks (hors
// repo) ; en CI (GitHub Actions) le workflow ecrit ce meme fichier a partir
// des secrets juste avant le build. Absent -> on retombe sur la signature
// debug (build encore installable mais pas la vraie cle de release).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
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

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // La reduction/renommage des ressources (active par defaut sur
            // le build de release) supprimait les icones drawable des
            // controles media personnalises (ic_notification,
            // ic_notification_add) : elles ne sont referencees que par une
            // chaine de texte envoyee depuis Dart a audio_service
            // (ex: 'drawable/ic_notification_add'), jamais par du code
            // Java/Kotlin, donc invisibles pour l'analyse statique de
            // l'outil de reduction qui les traite comme "non utilisees" et
            // les retire du build final. Consequence en prod (verifie via
            // adb logcat sur un vrai appareil) : IllegalArgumentException
            // "You must specify an icon resource id to build a CustomAction"
            // a chaque mise a jour de position, empechant la notification
            // (et donc les controles media notif/ecran de verrouillage) de
            // jamais se construire correctement.
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}
