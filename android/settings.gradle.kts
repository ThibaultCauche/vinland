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
    id("com.android.application") version "8.7.0" apply false
    id("org.jetbrains.kotlin.android") version "1.8.22" apply false
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
        }
    }
}