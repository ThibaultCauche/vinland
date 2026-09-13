package com.example.vinland

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/**
 * Declaree statiquement dans le manifest : recoit ACL_CONNECTED meme si
 * l'app n'a jamais tourne depuis le dernier redemarrage du telephone (cas
 * reveil + casque bluetooth du matin). Si l'appareil qui vient de se
 * connecter fait partie de la liste "de confiance" (choisie dans Parametres),
 * demarre ResumePlaybackService pour reprendre la derniere lecture.
 */
class BluetoothConnectReceiver : BroadcastReceiver() {
    @SuppressLint("MissingPermission")
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != BluetoothDevice.ACTION_ACL_CONNECTED) return

        val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
        } ?: return

        val address = try {
            device.address
        } catch (e: SecurityException) {
            return
        } ?: return

        val trusted = BluetoothTrustedDevices.getTrustedMacs(context)
        if (!trusted.contains(address)) return

        // L'app tourne deja dans ce process (ouverte au moins une fois depuis
        // le dernier redemarrage) : pas besoin (et risque de double lecture)
        // de demarrer un second FlutterEngine headless par-dessus, mais il
        // faut quand meme prevenir le Dart deja en cours d'execution, sinon
        // rien ne se passe quand l'app est ouverte au moment du branchement.
        val runningEngine = FlutterEngineCache.getInstance().get(MainActivity.MAIN_ENGINE_ID)
        if (runningEngine != null) {
            MethodChannel(runningEngine.dartExecutor.binaryMessenger, "vinland/bluetooth_devices")
                .invokeMethod("trustedDeviceConnected", null)
            return
        }

        val serviceIntent = Intent(context, ResumePlaybackService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }
}
