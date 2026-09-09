pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.13.0" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")

// FIX: Injecte le namespace après l'évaluation de chaque sous-projet
gradle.allprojects {
    afterEvaluate {
        if (extensions.findByName("android") != null) {
            val androidExt = extensions.getByName("android")
            try {
                val getNs = androidExt::class.java.getMethod("getNamespace")
                val ns = getNs.invoke(androidExt)
                if (ns == null) {
                    val setNs = androidExt::class.java.getMethod("setNamespace", String::class.java)
                    setNs.invoke(androidExt, group.toString())
                }
            } catch (_: Exception) {
                // Ignore si pas de méthode getNamespace/setNamespace
            }

            // FIX: certains plugins (ex: metadata_god 0.5.2, plus maintenu)
            // codent en dur un compileSdk ancien (31) dans leur propre
            // build.gradle. Comme Gradle unifie les versions d'AndroidX sur
            // tout le projet, ces plugins finissent par dependre (via
            // resolution transitive) de bibliotheques AndroidX exigeant un
            // compileSdk >= 34, ce que verifie la tache
            // `checkDebugAarMetadata` -- et le build echoue. On force donc le
            // compileSdk de TOUS les sous-projets a la meme valeur que
            // l'app (36), une pratique standard pour les vieux plugins.
            try {
                val setCompileSdk =
                    androidExt::class.java.getMethod("setCompileSdk", Int::class.javaObjectType)
                setCompileSdk.invoke(androidExt, 36)
            } catch (_: Exception) {
                // Ignore si pas de methode setCompileSdk (DSL plus ancienne)
            }
        }
    }
}