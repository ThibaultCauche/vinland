package com.example.vinland

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

private const val CHANNEL = "vinland/bluetooth_devices"
private const val PREFS_NAME = "vinland_bluetooth"
private const val PREFS_KEY_TRUSTED = "trusted_macs"

/**
 * Cote Dart (Parametres) : liste les appareils Bluetooth appaires et laisse
 * l'utilisateur choisir lesquels sont "de confiance". Cote natif
 * (BluetoothConnectReceiver) : relit la meme liste, stockee dans des
 * SharedPreferences natives simples (pas celles du plugin shared_preferences,
 * dont l'encodage interne des listes n'est pas garanti et n'a pas besoin
 * d'etre relu sans passer par Dart) pour rester lisible sans FlutterEngine.
 */
object BluetoothTrustedDevices {
    fun registerWith(engine: FlutterEngine, context: Context) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getBondedDevices" -> result.success(getBondedDevices(context))
                "getTrustedDevices" -> result.success(getTrustedMacs(context).toList())
                "setTrustedDevices" -> {
                    @Suppress("UNCHECKED_CAST")
                    val macs = (call.arguments as? List<String>) ?: emptyList()
                    setTrustedMacs(context, macs.toSet())
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun getBondedDevices(context: Context): List<Map<String, String>> {
        val adapter = BluetoothAdapter.getDefaultAdapter() ?: return emptyList()
        return try {
            adapter.bondedDevices.map { device ->
                mapOf("name" to (device.name ?: device.address), "address" to device.address)
            }
        } catch (e: SecurityException) {
            // Permission BLUETOOTH_CONNECT pas encore accordee : le cote Dart
            // doit la demander (permission_handler) avant d'appeler ceci.
            emptyList()
        }
    }

    fun getTrustedMacs(context: Context): Set<String> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getStringSet(PREFS_KEY_TRUSTED, emptySet()) ?: emptySet()
    }

    private fun setTrustedMacs(context: Context, macs: Set<String>) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putStringSet(PREFS_KEY_TRUSTED, macs).apply()
    }
}
