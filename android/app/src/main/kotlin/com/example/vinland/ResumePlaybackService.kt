package com.example.vinland

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

private const val CHANNEL_ID = "vinland_bt_resume"
private const val NOTIFICATION_ID = 4242
private const val RESUME_CHANNEL = "vinland/bluetooth_resume"

/**
 * Foreground service transitoire : sert uniquement a demarrer un FlutterEngine
 * "headless" (sans UI) qui reprend la derniere lecture, puis a se retirer une
 * fois que le foreground service permanent de audio_service a pris le relai
 * (notification de lecture normale). Necessaire car demarrer un FlutterEngine
 * et charger/jouer un titre reseau prend quelques secondes, pendant lesquelles
 * Android exige deja un foreground service actif (demarre depuis
 * BluetoothConnectReceiver, qui reagit a une broadcast exemptee des
 * restrictions d'execution en arriere-plan).
 */
class ResumePlaybackService : Service() {
    private var engine: FlutterEngine? = null
    private val handler = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification())
        startHeadlessResume()
        // Filet de securite : si le resume Dart plante ou reste bloque
        // (reseau/NAS injoignable), ne pas rester en foreground indefiniment.
        handler.postDelayed({ stopSelfSafely() }, 20_000)
        return START_NOT_STICKY
    }

    private fun buildNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(
                CHANNEL_ID, "Reprise automatique", NotificationManager.IMPORTANCE_LOW
            )
            manager.createNotificationChannel(channel)
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Vinland")
            .setContentText("Reprise de la lecture...")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setOngoing(true)
            .build()
    }

    private fun startHeadlessResume() {
        val loader = FlutterInjector.instance().flutterLoader()
        if (!loader.initialized()) {
            loader.startInitialization(applicationContext)
        }
        loader.ensureInitializationComplete(applicationContext, null)

        val flutterEngine = FlutterEngine(applicationContext)
        engine = flutterEngine

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RESUME_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "resumeStarted" -> {
                        result.success(null)
                        // Laisse quelques secondes au foreground service de
                        // audio_service pour prendre le relai avant de couper
                        // le notre.
                        handler.postDelayed({ stopSelfSafely() }, 5_000)
                    }
                    "resumeFailed" -> {
                        result.success(null)
                        stopSelfSafely()
                    }
                    else -> result.notImplemented()
                }
            }

        val entrypoint = DartExecutor.DartEntrypoint(
            loader.findAppBundlePath(), "bluetoothResumeMain"
        )
        flutterEngine.dartExecutor.executeDartEntrypoint(entrypoint)
    }

    private fun stopSelfSafely() {
        engine?.destroy()
        engine = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        engine?.destroy()
        engine = null
        super.onDestroy()
    }
}
