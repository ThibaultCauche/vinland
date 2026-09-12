package com.example.vinland // adapte ton package

import android.os.Bundle
import androidx.core.view.WindowCompat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache

// Herite d'AudioServiceActivity (pas FlutterActivity) : c'est ce qui branche
// cette activite sur le FlutterEngine partage gere par AudioServicePlugin
// (celui qui continue de tourner pour la lecture en fond), au lieu d'un
// engine independant. Necessaire aussi pour que cette classe soit reellement
// instanciee : voir AndroidManifest.xml, qui doit declarer .MainActivity (et
// non com.ryanheise.audioservice.AudioServiceActivity directement) comme
// activite LAUNCHER, sinon configureFlutterEngine() ci-dessous n'est jamais
// appele et ni le cache MAIN_ENGINE_ID ni le channel Bluetooth ne sont
// jamais mis en place.
class MainActivity: AudioServiceActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Sert uniquement de marqueur "l'app tourne deja dans ce process" pour
        // BluetoothConnectReceiver (voir MAIN_ENGINE_ID) : on ne relit jamais
        // cet engine depuis le receiver, juste sa presence dans le cache.
        FlutterEngineCache.getInstance().put(MAIN_ENGINE_ID, flutterEngine)
        BluetoothTrustedDevices.registerWith(flutterEngine, applicationContext)
    }

    companion object {
        const val MAIN_ENGINE_ID = "vinland_main_engine"
    }
}