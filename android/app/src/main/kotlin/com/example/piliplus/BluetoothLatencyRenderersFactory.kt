package com.maxzrb.piliexo

import android.content.Context
import android.os.Handler
import androidx.annotation.OptIn
import androidx.media3.common.Format
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.mediacodec.MediaCodecAdapter
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.video.MediaCodecVideoRenderer
import androidx.media3.exoplayer.video.VideoRendererEventListener
import java.nio.ByteBuffer
import java.util.ArrayList

/**
 * 保持系统默认视频渲染器能力，只把帧呈现时间推迟蓝牙补偿值。
 *
 * Media3 原生 HDR 使用音频作为主时钟；推迟视频帧时间等价于画面等待蓝牙声音。
 */
@OptIn(UnstableApi::class)
class BluetoothLatencyRenderersFactory(
    context: Context,
    private val volumeBoost: AppVolumeAudioProcessor,
) : DefaultRenderersFactory(context) {
    override fun buildAudioSink(
        context: Context,
        enableFloatOutput: Boolean,
        enableAudioOutputPlaybackParams: Boolean,
    ): AudioSink = DefaultAudioSink.Builder(context)
        .setEnableFloatOutput(enableFloatOutput)
        .setEnableAudioOutputPlaybackParameters(enableAudioOutputPlaybackParams)
        .setAudioProcessors(arrayOf(volumeBoost))
        .build()

    override fun buildVideoRenderers(
        context: Context,
        extensionRendererMode: Int,
        mediaCodecSelector: MediaCodecSelector,
        enableDecoderFallback: Boolean,
        eventHandler: Handler,
        eventListener: VideoRendererEventListener,
        allowedVideoJoiningTimeMs: Long,
        out: ArrayList<Renderer>,
    ) {
        super.buildVideoRenderers(
            context,
            extensionRendererMode,
            mediaCodecSelector,
            enableDecoderFallback,
            eventHandler,
            eventListener,
            allowedVideoJoiningTimeMs,
            out,
        )
        val builder = MediaCodecVideoRenderer.Builder(context)
            .setMediaCodecSelector(mediaCodecSelector)
            .setEnableDecoderFallback(enableDecoderFallback)
            .setAllowedJoiningTimeMs(allowedVideoJoiningTimeMs)
            .setEventHandler(eventHandler)
            .setEventListener(eventListener)
        if (out.isNotEmpty() && out[0] is MediaCodecVideoRenderer) {
            out[0] = DelayedMediaCodecVideoRenderer(builder)
        }
    }
}

@OptIn(UnstableApi::class)
private class DelayedMediaCodecVideoRenderer(
    builder: MediaCodecVideoRenderer.Builder,
) : MediaCodecVideoRenderer(builder) {
    override fun processOutputBuffer(
        positionUs: Long,
        elapsedRealtimeUs: Long,
        codec: MediaCodecAdapter?,
        buffer: ByteBuffer?,
        bufferIndex: Int,
        bufferFlags: Int,
        sampleCount: Int,
        bufferPresentationTimeUs: Long,
        isDecodeOnlyBuffer: Boolean,
        isLastBuffer: Boolean,
        format: Format,
    ): Boolean {
        return super.processOutputBuffer(
            positionUs,
            elapsedRealtimeUs,
            codec,
            buffer,
            bufferIndex,
            bufferFlags,
            sampleCount,
            bufferPresentationTimeUs +
                BluetoothLatencyPlugin.currentVideoDelayUs(),
            isDecodeOnlyBuffer,
            isLastBuffer,
            format,
        )
    }
}
