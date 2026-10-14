package com.example.vinland

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.audiofx.Visualizer
import android.os.Handler
import android.os.Looper
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
        return visualizers.isNotEmpty()
    }

    private fun create(sessionId: Int): Visualizer {
        val v = Visualizer(sessionId)
        v.setEnabled(false)
        val range = Visualizer.getCaptureSizeRange()
        v.setCaptureSize(1024.coerceIn(range[0], range[1]))
        v.setScalingMode(Visualizer.SCALING_MODE_NORMALIZED)
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
                main.post { publish(sessionId, levels) }
            }
        }, rate, false, true)
        v.setEnabled(true)
        return v
    }

    /**
     * [basses 20-150 Hz, mediums 150-2000 Hz], chacun ramene a 0..1 sur une
     * echelle logarithmique (l'oreille aussi).
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
            if (hz in 20.0..150.0) {
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
        return doubleArrayOf(scale(bass, bassCount), scale(mid, midCount))
    }

    private fun publish(sessionId: Int, levels: DoubleArray) {
        if (!visualizers.containsKey(sessionId)) return
        latest[sessionId] = levels
        // Pendant un fondu les deux platines jouent : on garde la plus forte.
        var bass = 0.0
        var mid = 0.0
        for (l in latest.values) {
            bass = max(bass, l[0]); mid = max(mid, l[1])
        }
        sink?.success(doubleArrayOf(bass, mid))
    }

    private fun release(sessionId: Int) {
        visualizers.remove(sessionId)?.let {
            try {
                it.setEnabled(false)
                it.release()
            } catch (_: Exception) {}
        }
        latest.remove(sessionId)
    }

    private fun stop() {
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
