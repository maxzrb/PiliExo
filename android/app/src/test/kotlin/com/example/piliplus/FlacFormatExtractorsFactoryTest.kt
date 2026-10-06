package com.maxzrb.piliexo

import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** 回归 96 kHz、24 bit 无损音轨超过 Android FLAC 默认 32 KiB 输入缓冲的场景。 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE)
class FlacFormatExtractorsFactoryTest {
    private fun flacFormat(maxFrameSize: Int = 40000, maxInputSize: Int = Format.NO_VALUE): Format {
        val data = ByteArray(42)
        "fLaC".toByteArray(Charsets.UTF_8).copyInto(data)
        data[4] = 0x80.toByte()
        data[7] = 34
        // STREAMINFO：最大块 8192 samples，最大帧 40000 bytes，96 kHz / 2 声道 / 24 bit。
        data[10] = 0x20
        for (i in 0..2) data[15 + i] = (maxFrameSize shr (16 - 8 * i)).toByte()
        val packed = (96000L shl 44) or (1L shl 41) or (23L shl 36)
        for (i in 0..7) data[18 + i] = (packed shr (56 - 8 * i)).toByte()
        return Format.Builder().setSampleMimeType(MimeTypes.AUDIO_FLAC)
            .setSampleRate(0).setChannelCount(2).setMaxInputSize(maxInputSize)
            .setInitializationData(listOf(data)).build()
    }

    @Test
    fun restoresStreamInfoAndReservesSpaceForLargeCompressedFrames() {
        val input = flacFormat()
        val result = correctFlacFormat(input)
        assertEquals(96000, result.sampleRate)
        assertEquals(2, result.channelCount)
        assertEquals(40000, result.maxInputSize)
        assertTrue(result.maxInputSize >= 36693)
        assertSame(input.initializationData, result.initializationData)
    }

    @Test
    fun unknownFrameSizeUsesUncompressedBlockBound() {
        assertEquals(8192 * 2 * 3 + 64, correctFlacFormat(flacFormat(0)).maxInputSize)
    }

    @Test
    fun preservesLargerContainerInputSize() {
        assertEquals(100000, correctFlacFormat(flacFormat(maxInputSize = 100000)).maxInputSize)
    }

    @Test
    fun leavesOtherCodecsAndInvalidMetadataUntouched() {
        val aac = Format.Builder().setSampleMimeType(MimeTypes.AUDIO_AAC).build()
        assertSame(aac, correctFlacFormat(aac))
        val missing = Format.Builder().setSampleMimeType(MimeTypes.AUDIO_FLAC).build()
        assertSame(missing, correctFlacFormat(missing))
        for (data in listOf(ByteArray(12), ByteArray(42), "fLaC".toByteArray())) {
            val invalid = missing.buildUpon().setInitializationData(listOf(data)).build()
            assertSame(invalid, correctFlacFormat(invalid))
        }
    }
}
