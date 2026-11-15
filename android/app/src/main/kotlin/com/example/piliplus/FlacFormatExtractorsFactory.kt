package com.maxzrb.piliexo

import android.net.Uri
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.Extractor
import androidx.media3.extractor.ExtractorOutput
import androidx.media3.extractor.ExtractorsFactory
import androidx.media3.extractor.FlacStreamMetadata
import androidx.media3.extractor.TrackOutput

/** 用 FLAC 自身的 STREAMINFO 补齐 MP4 容器遗漏的音频参数。 */
@UnstableApi
internal fun correctFlacFormat(format: Format): Format {
    if (format.sampleMimeType != MimeTypes.AUDIO_FLAC) return format
    val data = format.initializationData.firstOrNull() ?: return format
    // Media3 的 FLAC 初始化数据包含 fLaC 标记、元数据块头和 34 字节 STREAMINFO。
    if (data.size < 42 || data[0] != 0x66.toByte() || data[1] != 0x4c.toByte() ||
        data[2] != 0x61.toByte() || data[3] != 0x43.toByte() ||
        (data[4].toInt() and 0x7f) != 0 || data[5] != 0.toByte() ||
        data[6] != 0.toByte() || data[7] != 34.toByte()
    ) return format

    val metadata = FlacStreamMetadata(data, 8)
    if (metadata.sampleRate <= 0 || metadata.maxBlockSizeSamples <= 0 ||
        metadata.bitsPerSample !in 4..32
    ) return format
    // 高采样率 MP4 的 16 位采样率字段可能为 0；真实采样率以 STREAMINFO 为准。
    // 最大压缩帧大小为 0 表示未知，此时按最大未压缩块加帧头预留输入空间。
    val maxFrameSize = metadata.maxFrameSize.takeIf { it > 0 }
        ?: (metadata.maxBlockSizeSamples * metadata.channels *
            ((metadata.bitsPerSample + 7) / 8) + 64)
    return format.buildUpon()
        .setSampleRate(metadata.sampleRate)
        .setChannelCount(metadata.channels)
        .setMaxInputSize(maxOf(format.maxInputSize, maxFrameSize))
        .build()
}

/** 在轨道送入选轨和解码器之前修正格式，保持默认解封装、字幕和音视频输出路径。 */
@UnstableApi
internal class FlacFormatExtractorsFactory(
    private val delegate: ExtractorsFactory = DefaultExtractorsFactory(),
) : ExtractorsFactory by delegate {
    override fun createExtractors(): Array<Extractor> = wrap(delegate.createExtractors())

    override fun createExtractors(
        uri: Uri,
        responseHeaders: Map<String, List<String>>,
    ): Array<Extractor> = wrap(delegate.createExtractors(uri, responseHeaders))

    private fun wrap(extractors: Array<Extractor>): Array<Extractor> =
        extractors.map { extractor ->
            object : Extractor by extractor {
                override fun init(output: ExtractorOutput) {
                    extractor.init(object : ExtractorOutput by output {
                        override fun track(id: Int, type: Int): TrackOutput {
                            val track = output.track(id, type)
                            return object : TrackOutput by track {
                                override fun format(format: Format) {
                                    track.format(correctFlacFormat(format))
                                }
                            }
                        }
                    })
                }
            }
        }.toTypedArray()
}
