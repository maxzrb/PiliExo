package com.maxzrb.piliexo

import android.content.Context
import android.hardware.display.DisplayManager
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Display
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.sin

/**
 * 读取当前 Android 蓝牙输出信息，并向 Media3 视频渲染器提供统一的画面延迟。
 *
 * Android 普通应用拿不到活动 Bluetooth codec，codec 区间由 Dart 设置层选择；
 * 这里只报告音频协议、设备名、刷新率和主机缓冲区事实。
 */
class BluetoothLatencyPlugin(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        const val CHANNEL = "com.maxzrb.piliexo/bluetooth_latency"
        private const val TAG = "BluetoothLatency"
        private const val CUE_INTERVAL_SECONDS = 3
        private const val CUE_LEAD_US = 700_000L

        @Volatile
        private var videoDelayUs = 0L

        fun currentVideoDelayUs(): Long = videoDelayUs
    }

    private val appContext = context.applicationContext
    private val audioManager = appContext.getSystemService(AudioManager::class.java)
    private val displayManager = appContext.getSystemService(DisplayManager::class.java)
    private val channel = MethodChannel(messenger, CHANNEL)
    private val calibrationChannel = EventChannel(messenger, "$CHANNEL/calibration")
    private val mainHandler = Handler(Looper.getMainLooper())
    private val calibrationWorker = Executors.newSingleThreadExecutor()
    private var calibration: CalibrationRun? = null
    private val deviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) {
            notifyOutputChanged(addedDevices)
        }

        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) {
            notifyOutputChanged(removedDevices)
        }
    }

    init {
        channel.setMethodCallHandler(this)
        calibrationChannel.setStreamHandler(this)
        audioManager.registerAudioDeviceCallback(deviceCallback, mainHandler)
    }

    private fun notifyOutputChanged(devices: Array<out AudioDeviceInfo>) {
        if (devices.any { it.isSink && bluetoothProtocol(it.type) != null }) {
            channel.invokeMethod("outputChanged", null)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getOutputInfo" -> result.success(readOutputInfo())
            "setVideoDelayMs" -> {
                val delayMs = (call.arguments as? Number)?.toInt() ?: 0
                videoDelayUs = delayMs.coerceIn(0, 500).toLong() * 1000L
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        onCancel(null)
        val run = CalibrationRun()
        calibration = run
        calibrationWorker.execute {
            try {
                if (!run.stopped) playCalibration(run) { cueUs ->
                    mainHandler.post {
                        if (calibration === run) events.success(cueUs)
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "calibration audio failed", e)
                mainHandler.post {
                    if (calibration === run) {
                        events.error("audio_output", null, null)
                        events.endOfStream()
                    }
                }
            }
        }
    }

    override fun onCancel(arguments: Any?) {
        calibration?.stopped = true
        calibration = null
    }

    fun dispose() {
        audioManager.unregisterAudioDeviceCallback(deviceCallback)
        channel.setMethodCallHandler(null)
        calibrationChannel.setStreamHandler(null)
        onCancel(null)
        calibrationWorker.shutdown()
    }

    private fun readOutputInfo(): Map<String, Any?> {
        val selected = findBluetoothOutput()
        val refreshRate = runCatching {
            displayManager.getDisplay(Display.DEFAULT_DISPLAY)?.refreshRate ?: 60f
        }.getOrDefault(60f)
        val sampleRate = runCatching {
            audioManager.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)
                ?.toIntOrNull() ?: 0
        }.getOrDefault(0)
        val framesPerBuffer = runCatching {
            audioManager.getProperty(AudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER)
                ?.toIntOrNull() ?: 0
        }.getOrDefault(0)

        if (selected == null) {
            return mapOf(
                "isBluetooth" to false,
                "connected" to false,
                "active" to false,
                "protocol" to "none",
                "deviceName" to "",
                "refreshRate" to refreshRate,
                "sampleRate" to sampleRate,
                "framesPerBuffer" to framesPerBuffer,
            )
        }

        val protocol = bluetoothProtocol(selected.type) ?: "unknown"
        return mapOf(
            "isBluetooth" to true,
            "connected" to true,
            // AudioManager 不公开活动媒体路由；检测到已连接蓝牙输出时允许补偿，
            // 用户可在“额外补偿”里确认实际听感并随时关闭。
            "active" to true,
            "protocol" to protocol,
            "deviceName" to (selected.productName?.toString() ?: ""),
            "refreshRate" to refreshRate,
            "sampleRate" to sampleRate,
            "framesPerBuffer" to framesPerBuffer,
        )
    }

    private fun bluetoothProtocol(type: Int): String? = when (type) {
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "a2dp"
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "hfp"
        AudioDeviceInfo.TYPE_BLE_HEADSET,
        AudioDeviceInfo.TYPE_BLE_SPEAKER,
        AudioDeviceInfo.TYPE_HEARING_AID -> "leAudio"
        else -> null
    }

    private fun findBluetoothOutput(): AudioDeviceInfo? {
        val devices = runCatching {
            audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        }.getOrDefault(emptyArray())
        return devices
            .filter { it.isSink && bluetoothProtocol(it.type) != null }
            .minByOrNull {
                when (it.type) {
                    AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> 0
                    AudioDeviceInfo.TYPE_BLE_HEADSET,
                    AudioDeviceInfo.TYPE_BLE_SPEAKER,
                    AudioDeviceInfo.TYPE_HEARING_AID -> 1
                    AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> 2
                    else -> 3
                }
            }
    }

    private class CalibrationRun {
        @Volatile
        var stopped = false
    }

    private fun playCalibration(run: CalibrationRun, onCue: (Long) -> Unit) {
        val output = checkNotNull(findBluetoothOutput()) { "no Bluetooth output for calibration" }
        val outputRate = audioManager.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)
            ?.toIntOrNull()?.takeIf { it > 0 } ?: 48000
        val (sampleRate, minBuffer) = listOf(outputRate, 44100).firstNotNullOf { rate ->
            val size = AudioTrack.getMinBufferSize(
                rate,
                AudioFormat.CHANNEL_OUT_STEREO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
            if (size > 0) rate to size else null
        }
        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build(),
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(sampleRate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                    .build(),
            )
            .setTransferMode(AudioTrack.MODE_STREAM)
            .setBufferSizeInBytes(maxOf(minBuffer * 2, sampleRate * 24 / 100))
            .build()
        try {
            check(track.state == AudioTrack.STATE_INITIALIZED)
            track.setPreferredDevice(output)
            val click = buildSoftClick(sampleRate)
            val samplesPerSecond = sampleRate * 2
            val silence = ShortArray(sampleRate / 50 * 2)
            val silenceSamples = samplesPerSecond * CUE_INTERVAL_SECONDS - click.size
            val leadSamples = (sampleRate * CUE_LEAD_US / 1_000_000).toInt() * 2
            track.play()
            // 先用静音预热输出。后续两声之间固定相隔 3 秒的采样帧。
            writeCalibrationPcm(run, track, silence, samplesPerSecond)
            while (!run.stopped) {
                // 从正在供给的音频流预告下一拍，用相同的单调时钟安排闪动。
                val cueUs = System.nanoTime() / 1_000 + CUE_LEAD_US
                onCue(cueUs)
                writeCalibrationPcm(run, track, silence, leadSamples)
                val queuedUs = writeCalibrationPcm(run, track, click, click.size)
                if (queuedUs != 0L) {
                    Log.d(TAG, "calibration cue plannedUs=$cueUs queuedUs=$queuedUs")
                }
                writeCalibrationPcm(run, track, silence, silenceSamples - leadSamples)
            }
        } finally {
            track.release()
        }
    }

    private fun writeCalibrationPcm(
        run: CalibrationRun,
        track: AudioTrack,
        samples: ShortArray,
        count: Int,
    ): Long {
        var offset = 0
        var firstWriteUs = 0L
        while (offset < count && !run.stopped) {
            val start = offset % samples.size
            val remaining = minOf(count - offset, samples.size - start)
            val written = track.write(samples, start, remaining, AudioTrack.WRITE_NON_BLOCKING)
            check(written >= 0) { "calibration audio write failed: $written" }
            if (written == 0) {
                Thread.sleep(5)
            } else {
                if (offset == 0) firstWriteUs = System.nanoTime() / 1_000
                offset += written
            }
        }
        return firstWriteUs
    }

    /**
     * 660 Hz 柔和立体声正弦脉冲，带 12 ms 淡入、长衰减和 40 ms 淡出。
     * 不使用系统蜂鸣音，避免蓝牙耳机放大后刺耳。
     */
    private fun buildSoftClick(sampleRate: Int): ShortArray {
        val durationSeconds = 0.16
        val count = (sampleRate * durationSeconds).toInt()
        val attack = (sampleRate * 0.012).toInt().coerceAtLeast(1)
        val release = (sampleRate * 0.040).toInt().coerceAtLeast(1)
        val frequency = 660.0
        val amplitude = Short.MAX_VALUE * 0.42
        return ShortArray(count * 2) { packedIndex ->
            val index = packedIndex / 2
            val fadeIn = (index.toDouble() / attack).coerceAtMost(1.0)
            val fadeOut = ((count - index).toDouble() / release).coerceAtMost(1.0)
            val decay = if (index < attack) {
                1.0
            } else {
                exp(-1.2 * (index - attack) / (count - attack).coerceAtLeast(1))
            }
            val envelope = fadeIn * fadeOut * decay
            (
                sin(2.0 * PI * frequency * index / sampleRate) *
                    amplitude *
                    envelope
                ).toInt().toShort()
        }
    }
}
