package com.example.vinland

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.audiofx.Visualizer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.math.hypot
import kotlin.math.ln
import kotlin.math.max

/**
 * Niveaux de basses et de mediums de la musique que joue Vinland, pour le
 * visuel en hexagones du lecteur (lib/services/audio_visualizer.dart).
 *
 * S'appuie sur android.media.audiofx.Visualizer, branche sur les sessions
 * audio des deux platines just_audio (voir DeckPlayerEngine) : on n'analyse
 * que le son de Vinland, jamais le micro. Android exige pourtant la
 * permission RECORD_AUDIO pour cette API, d'ou la demande cote Dart.
 *
 * Mode SCALING_MODE_NORMALIZED : les niveaux ne dependent pas du volume
 * choisi par l'utilisateur (ni du fondu enchaine).
 */
class AudioVisualizer private constructor(private val context: Context) :
    EventChannel.StreamHandler {

    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private val visualizers = mutableMapOf<Int, Visualizer>()
    private val latest = mutableMapOf<Int, DoubleArray>()
    private val lastCapture = mutableMapOf<Int, Long>()

    /**
     * Un Visualizer cree avant que sa session ait une piste (changement de
     * titre : just_audio annonce la nouvelle session avant de creer
     * l'AudioTrack) ne capte jamais rien sur certains telephones. On recree
     * ceux qui se taisent depuis plus de [SILENT_MS].
     */
    private val watchdog = object : Runnable {
        override fun run() {
            val now = SystemClock.elapsedRealtime()
            for ((id, last) in lastCapture.toList()) {
                if (now - last < SILENT_MS) continue
                release(id)
                try {
                    visualizers[id] = create(id)
                } catch (e: Exception) {
                    Log.w(TAG, "Visualizer indisponible pour la session $id: $e")
                    lastCapture[id] = now
                }
            }
            if (visualizers.isNotEmpty() || lastCapture.isNotEmpty()) {
                main.postDelayed(this, WATCHDOG_MS)
            }
        }
    }

    private fun hasPermission(): Boolean =
        context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    /** Branche une analyse par session (et lache celles qui ont disparu). */
    private fun start(sessionIds: List<Int>): Boolean {
        if (!hasPermission()) return false
        val wanted = sessionIds.filter { it > 0 }.toSet()
        for (id in visualizers.keys - wanted) release(id)
        for (id in wanted - visualizers.keys) {
            try {
                visualizers[id] = create(id)
            } catch (e: Exception) {
                // Session pas encore prete (platine pas encore chargee) ou
                // effet refuse par le constructeur : on reessaiera au
                // prochain appel, le visuel passe en mode « au repos ».
                Log.w(TAG, "Visualizer indisponible pour la session $id: $e")
            }
        }
        main.removeCallbacks(watchdog)
        if (visualizers.isNotEmpty()) main.postDelayed(watchdog, WATCHDOG_MS)
        return visualizers.isNotEmpty()
    }

    private fun create(sessionId: Int): Visualizer {
        val v = Visualizer(sessionId)
        v.setEnabled(false)
        val range = Visualizer.getCaptureSizeRange()
        v.setCaptureSize(1024.coerceIn(range[0], range[1]))
        v.setScalingMode(Visualizer.SCALING_MODE_NORMALIZED)
        // Volume reel (RMS, en millibels) : le mode NORMALIZED gonfle un
        // piano doux autant qu'une grosse caisse, le RMS dit ce qui est fort.
        v.setMeasurementMode(Visualizer.MEASUREMENT_MODE_PEAK_RMS)
        val rms = Visualizer.MeasurementPeakRms()
        val rate = Visualizer.getMaxCaptureRate()
        v.setDataCaptureListener(object : Visualizer.OnDataCaptureListener {
            override fun onWaveFormDataCapture(
                visualizer: Visualizer?, waveform: ByteArray?, samplingRate: Int
            ) {}

            override fun onFftDataCapture(
                visualizer: Visualizer?, fft: ByteArray?, samplingRate: Int
            ) {
                if (fft == null) return
                val levels = bands(fft, samplingRate)
                val loudness = try {
                    visualizer?.getMeasurementPeakRms(rms)
                    // -60 dB (ou moins) -> 0, 0 dB (plein volume) -> 1.
                    ((rms.mRms / 100.0 + 60) / 60).coerceIn(0.0, 1.0)
                } catch (_: Exception) {
                    1.0
                }
                levels[2] = loudness
                main.post { publish(sessionId, levels) }
            }
        }, rate, false, true)
        v.setEnabled(true)
        lastCapture[sessionId] = SystemClock.elapsedRealtime()
        return v
    }

    /**
     * [basses 30-120 Hz (grosse caisse), mediums 150-2000 Hz], chacun
     * ramene a 0..1 sur une echelle logarithmique (l'oreille aussi), puis
     * une case pour le volume, remplie par l'appelant.
     */
    private fun bands(fft: ByteArray, samplingRateMilliHz: Int): DoubleArray {
        val n = fft.size
        val binHz = samplingRateMilliHz / 1000.0 / n
        var bass = 0.0
        var bassCount = 0
        var mid = 0.0
        var midCount = 0
        // fft[0] et fft[1] = composantes 0 et Nyquist, puis (re, im) par
        // case de frequence.
        for (k in 1 until n / 2) {
            val hz = k * binHz
            if (hz > 2000) break
            val mag = hypot(fft[2 * k].toDouble(), fft[2 * k + 1].toDouble())
            if (hz in 30.0..120.0) {
                bass += mag; bassCount++
            } else if (hz > 150) {
                mid += mag; midCount++
            }
        }
        fun scale(sum: Double, count: Int): Double {
            if (count == 0) return 0.0
            val avg = sum / count
            return (ln(1 + avg) / ln(1 + 128.0)).coerceIn(0.0, 1.0)
        }
        return doubleArrayOf(scale(bass, bassCount), scale(mid, midCount), 1.0)
    }

    /**
     * Retard estime entre l'analyse et le haut-parleur, en ms.
     *
     * L'effet Visualizer lit le son avant le grand tampon de sortie
     * (« deep buffer ») utilise pour la musique : mesure sur le telephone de
     * Thibault, ~370 ms sur le haut-parleur. Un casque Bluetooth ajoute
     * encore ~200 ms. Le visuel decale l'affichage d'autant.
     */
    private fun outputLatencyMs(): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return 350
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val bluetooth = audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any {
            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                it.type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
                it.type == AudioDeviceInfo.TYPE_BLE_SPEAKER
        }
        return if (bluetooth) 550 else 350
    }

    private fun publish(sessionId: Int, levels: DoubleArray) {
        if (!visualizers.containsKey(sessionId)) return
        latest[sessionId] = levels
        lastCapture[sessionId] = SystemClock.elapsedRealtime()
        // Pendant un fondu les deux platines jouent : on garde la plus forte.
        var bass = 0.0
        var mid = 0.0
        var loudness = 0.0
        for (l in latest.values) {
            bass = max(bass, l[0]); mid = max(mid, l[1]); loudness = max(loudness, l[2])
        }
        sink?.success(doubleArrayOf(bass, mid, loudness))
    }

    private fun release(sessionId: Int) {
        visualizers.remove(sessionId)?.let {
            try {
                it.setEnabled(false)
                it.release()
            } catch (_: Exception) {}
        }
        latest.remove(sessionId)
        lastCapture.remove(sessionId)
    }

    private fun stop() {
        main.removeCallbacks(watchdog)
        for (id in visualizers.keys.toList()) release(id)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        stop()
    }

    companion object {
        private const val TAG = "VinlandVisualizer"
        private const val SILENT_MS = 1500L
        private const val WATCHDOG_MS = 1000L

        fun registerWith(engine: FlutterEngine, context: Context) {
            val visualizer = AudioVisualizer(context)
            val messenger = engine.dartExecutor.binaryMessenger
            EventChannel(messenger, "vinland/visualizer/levels")
                .setStreamHandler(visualizer)
            MethodChannel(messenger, "vinland/visualizer")
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "start" -> {
                            val ids = call.argument<List<Int>>("sessionIds")
                                ?: emptyList()
                            result.success(visualizer.start(ids))
                        }
                        "latency" -> result.success(visualizer.outputLatencyMs())
                        "stop" -> {
                            visualizer.stop()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
        }
    }
}
