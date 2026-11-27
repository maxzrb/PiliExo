package com.maxzrb.piliexo

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor.AudioFormat
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder

class AppVolumeAudioProcessorTest {
    @Test
    fun unityGainPreservesSamples() {
        val samples = shortArrayOf(Short.MIN_VALUE, -2500, 0, 2500, Short.MAX_VALUE)
        assertArrayEquals(samples, process(samples, 1f))
    }

    @Test
    fun boostAmplifiesQuietSamplesAndLimitsPeaks() {
        val output = process(shortArrayOf(-30000, -1000, 0, 1000, 30000), 8f)
        assertTrue(output[1] == (-8000).toShort())
        assertTrue(output[3] == 8000.toShort())
        assertTrue(output[0] in -32767..-30001)
        assertTrue(output[4] in 30001..32766)
    }

    private fun process(samples: ShortArray, gain: Float): ShortArray {
        val processor = AppVolumeAudioProcessor()
        processor.configure(AudioFormat(48000, 1, C.ENCODING_PCM_16BIT))
        processor.flush()
        processor.gain = gain
        val input = ByteBuffer.allocateDirect(samples.size * 2).order(ByteOrder.nativeOrder())
        samples.forEach(input::putShort)
        input.flip()
        processor.queueInput(input)
        val output = processor.output.order(ByteOrder.nativeOrder())
        return ShortArray(samples.size) { output.short }
    }
}
