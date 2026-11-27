package com.maxzrb.piliexo

import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor.AudioFormat
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.math.sign

@OptIn(UnstableApi::class)
class AppVolumeAudioProcessor : BaseAudioProcessor() {
    @Volatile
    var gain: Float = 1f

    override fun onConfigure(inputAudioFormat: AudioFormat): AudioFormat =
        if (inputAudioFormat.encoding == C.ENCODING_PCM_16BIT) {
            inputAudioFormat
        } else {
            AudioFormat.NOT_SET
        }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val output = replaceOutputBuffer(inputBuffer.remaining()).order(ByteOrder.nativeOrder())
        val currentGain = gain
        if (currentGain == 1f) {
            output.put(inputBuffer)
        } else {
            val input = inputBuffer.order(ByteOrder.nativeOrder())
            while (input.hasRemaining()) {
                val amplified = input.short * (currentGain / 32768f)
                val peak = abs(amplified)
                val limited = if (peak <= 0.75f) {
                    amplified
                } else {
                    val excess = peak - 0.75f
                    amplified.sign * (0.75f + 0.25f * excess / (excess + 0.25f))
                }
                output.putShort((limited * 32768f).roundToInt().coerceIn(-32768, 32767).toShort())
            }
        }
        output.flip()
    }
}
