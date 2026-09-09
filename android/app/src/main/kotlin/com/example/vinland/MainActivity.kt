package com.example.vinland // adapte ton package

import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache

class MainActivity: FlutterActivity() {
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