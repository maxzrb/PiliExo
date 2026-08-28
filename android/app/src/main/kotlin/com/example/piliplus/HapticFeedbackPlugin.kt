package com.maxzrb.piliexo

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** 为 Flutter 提供可调振幅的 Android 导航震动反馈。 */
class HapticFeedbackPlugin(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "com.maxzrb.piliexo/haptics"
        private const val DEFAULT_DURATION_MS = 18L
    }

    private val vibrator: Vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        val manager = context.getSystemService(VibratorManager::class.java)
        manager.defaultVibrator
    } else {
        @Suppress("DEPRECATION")
        context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
    }
    private val channel = MethodChannel(messenger, CHANNEL)

    fun register() {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "vibrate" -> {
                val amplitude = (call.argument<Number>("amplitude")?.toInt() ?: 128)
                    .coerceIn(1, 255)
                val durationMs = (call.argument<Number>("durationMs")?.toLong()
                    ?: DEFAULT_DURATION_MS).coerceIn(1L, 100L)
                if (vibrator.hasVibrator()) {
                    // 取消上一段短震动，避免连续点击时叠加成拖沓的长震动。
                    vibrator.cancel()
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        vibrator.vibrate(
                            VibrationEffect.createOneShot(durationMs, amplitude),
                        )
                    } else {
                        @Suppress("DEPRECATION")
                        vibrator.vibrate(durationMs)
                    }
                }
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        vibrator.cancel()
    }
}
