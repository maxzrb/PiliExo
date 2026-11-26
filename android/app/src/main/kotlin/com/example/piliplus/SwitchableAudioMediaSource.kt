package com.maxzrb.piliexo

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Timeline
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.TransferListener
import androidx.media3.decoder.DecoderInputBuffer
import androidx.media3.exoplayer.FormatHolder
import androidx.media3.exoplayer.LoadingInfo
import androidx.media3.exoplayer.SeekParameters
import androidx.media3.exoplayer.source.CompositeMediaSource
import androidx.media3.exoplayer.source.MediaPeriod
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.MediaSource.MediaPeriodId
import androidx.media3.exoplayer.source.SampleStream
import androidx.media3.exoplayer.source.TrackGroupArray
import androidx.media3.exoplayer.trackselection.ExoTrackSelection
import androidx.media3.exoplayer.trackselection.FixedTrackSelection
import androidx.media3.exoplayer.upstream.Allocator
import java.io.IOException

@UnstableApi
internal enum class Media3AudioSwitch(val value: String) {
    UNAVAILABLE("unavailable"),
    FAILED("failed"),
    SWITCHED("switched"),
}

/** 保留合并源的时间轴和已选音频流对象，只替换其读取的独立音频分轨。 */
@UnstableApi
internal class SwitchableAudioMediaSource(
    private val original: MediaSource,
) : CompositeMediaSource<MediaSource>() {
    private val periods = mutableSetOf<AudioPeriod>()
    private var selectedSource = original
    private var selectedPeriodUid: Any? = null
    private var playbackHandler: Handler? = null
    private var pending: PendingSwitch? = null

    private class PendingSwitch(
        val owner: AudioPeriod,
        val source: MediaSource,
        val positionUs: Long,
        val complete: (Media3AudioSwitch) -> Unit,
    ) {
        val deadlineMs = SystemClock.elapsedRealtime() + 8000
        val format = FormatHolder()
        val sample = DecoderInputBuffer.newNoDataInstance()
        var period: MediaPeriod? = null
        var selection: FixedTrackSelection? = null
        var stream: SampleStream? = null
        var periodUid: Any? = null
    }

    override fun getMediaItem(): MediaItem = original.mediaItem

    override fun prepareSourceInternal(mediaTransferListener: TransferListener?) {
        super.prepareSourceInternal(mediaTransferListener)
        playbackHandler = Handler(checkNotNull(Looper.myLooper()))
        prepareChildSource(original, original)
    }

    override fun maybeThrowSourceInfoRefreshError() {
        // 备用轨的网络错误只结束本次切换，当前主播放源仍能继续读取。
        selectedSource.maybeThrowSourceInfoRefreshError()
    }

    override fun onChildSourceInfoRefreshed(
        id: MediaSource,
        mediaSource: MediaSource,
        timeline: Timeline,
    ) {
        if (id === original) {
            refreshSourceInfo(timeline)
            return
        }
        val request = pending?.takeIf { it.source === id && it.period == null } ?: return
        if (timeline.isEmpty) return
        val uid = timeline.getUidOfPeriod(0)
        val startUs = request.owner.nextSampleUs(request.positionUs)
        val period = mediaSource.createPeriod(
            request.owner.id.copyWithPeriodUid(uid),
            request.owner.allocator,
            startUs,
        )
        request.periodUid = uid
        request.period = period
        request.owner.applyPeriodSettings(period)
        period.prepare(object : MediaPeriod.Callback {
            override fun onPrepared(mediaPeriod: MediaPeriod) {
                if (pending !== request) return
                val groups = mediaPeriod.trackGroups
                val currentMime = request.owner.audioMimeType
                val selection = (0 until groups.length).firstNotNullOfOrNull { groupIndex ->
                    val group = groups[groupIndex]
                    (0 until group.length).firstOrNull { group.getFormat(it).sampleMimeType == currentMime }
                        ?.let { FixedTrackSelection(group, it) }
                }
                if (selection == null) {
                    finish(request, Media3AudioSwitch.UNAVAILABLE)
                    return
                }
                val streams = arrayOfNulls<SampleStream>(1)
                val positionUs = request.owner.nextSampleUs(request.positionUs)
                mediaPeriod.selectTracks(
                    arrayOf(selection), booleanArrayOf(false), streams, BooleanArray(1), positionUs,
                )
                request.selection = selection
                request.stream = checkNotNull(streams.single())
                mediaPeriod.continueLoading(loadingAt(positionUs))
            }

            override fun onContinueLoadingRequested(source: MediaPeriod) {
                if (request.owner.current === source) request.owner.requestLoading()
            }
        }, startUs)
    }

    override fun createPeriod(id: MediaPeriodId, allocator: Allocator, startPositionUs: Long): MediaPeriod {
        val source = selectedSource
        val childId = if (source === original) id else id.copyWithPeriodUid(checkNotNull(selectedPeriodUid))
        return AudioPeriod(id, allocator, source, source.createPeriod(childId, allocator, startPositionUs))
            .also(periods::add)
    }

    override fun releasePeriod(mediaPeriod: MediaPeriod) {
        val period = mediaPeriod as AudioPeriod
        cancelSwitch(period)
        periods.remove(period)
        period.source.releasePeriod(period.current)
        releaseUnusedChild(period.source)
    }

    override fun releaseSourceInternal() {
        playbackHandler?.removeCallbacksAndMessages(null)
        playbackHandler = null
        selectedSource = original
        selectedPeriodUid = null
        super.releaseSourceInternal()
    }

    override fun getMediaPeriodIdForChildMediaPeriodId(
        id: MediaSource,
        mediaPeriodId: MediaPeriodId,
    ): MediaPeriodId? = if (id === original) mediaPeriodId else periods.firstOrNull {
        it.source === id && it.id.windowSequenceNumber == mediaPeriodId.windowSequenceNumber
    }?.id

    fun switchTo(source: MediaSource, positionUs: Long, complete: (Media3AudioSwitch) -> Unit) {
        val owner = periods.singleOrNull()
        val handler = playbackHandler
        if (owner?.canSwitch != true || handler == null || pending != null) {
            complete(Media3AudioSwitch.UNAVAILABLE)
            return
        }
        val request = PendingSwitch(owner, source, positionUs, complete)
        pending = request
        prepareChildSource(source, source)
        handler.post { poll(request) }
    }

    private fun poll(request: PendingSwitch) {
        if (pending !== request) return
        val owner = request.owner
        if (!owner.canSwitch || SystemClock.elapsedRealtime() >= request.deadlineMs) {
            finish(request, Media3AudioSwitch.FAILED)
            return
        }
        try {
            request.source.maybeThrowSourceInfoRefreshError()
            val period = request.period
            period?.maybeThrowPrepareError()
            val stream = request.stream
            if (period != null && stream != null) {
                val positionUs = owner.nextSampleUs(request.positionUs)
                period.readDiscontinuity()
                period.continueLoading(loadingAt(positionUs))
                val bufferedUs = period.bufferedPositionUs
                if (bufferedUs != C.TIME_END_OF_SOURCE && bufferedUs < positionUs + 200_000) {
                    playbackHandler?.postDelayed({ poll(request) }, 25)
                    return
                }
                stream.skipData(positionUs)
                request.sample.clear()
                val flags = SampleStream.FLAG_PEEK or SampleStream.FLAG_OMIT_SAMPLE_DATA
                var result = stream.readData(request.format, request.sample, flags)
                if (result == C.RESULT_FORMAT_READ) {
                    result = stream.readData(request.format, request.sample, flags)
                }
                // skipData 可停在目标之前的一帧，消耗这一帧以避免音频时间戳倒退。
                if (result == C.RESULT_BUFFER_READ && !request.sample.isEndOfStream &&
                    request.sample.timeUs < positionUs
                ) {
                    stream.readData(request.format, request.sample, SampleStream.FLAG_OMIT_SAMPLE_DATA)
                    request.sample.clear()
                    result = stream.readData(request.format, request.sample, flags)
                }
                if (result == C.RESULT_BUFFER_READ) {
                    if (request.sample.isEndOfStream || request.sample.timeUs > positionUs + 120_000) {
                        finish(request, Media3AudioSwitch.FAILED)
                        return
                    }
                    if (request.sample.timeUs >= positionUs) {
                        val previousSource = owner.source
                        val previousPeriod = owner.current
                        selectedSource = request.source
                        selectedPeriodUid = request.periodUid
                        owner.replace(request.source, period, checkNotNull(request.selection), stream)
                        previousSource.releasePeriod(previousPeriod)
                        releaseUnusedChild(previousSource)
                        finish(request, Media3AudioSwitch.SWITCHED)
                        owner.requestLoading()
                        return
                    }
                }
            }
        } catch (_: IOException) {
            finish(request, Media3AudioSwitch.FAILED)
            return
        }
        playbackHandler?.postDelayed({ poll(request) }, 25)
    }

    private fun finish(request: PendingSwitch, result: Media3AudioSwitch) {
        pending = null
        if (result != Media3AudioSwitch.SWITCHED) {
            request.period?.let(request.source::releasePeriod)
            releaseChildSource(request.source)
        }
        request.complete(result)
    }

    private fun cancelSwitch(owner: AudioPeriod) {
        pending?.takeIf { it.owner === owner }?.let { finish(it, Media3AudioSwitch.FAILED) }
    }

    private fun releaseUnusedChild(source: MediaSource) {
        if (source !== original && source !== selectedSource && periods.none { it.source === source }) {
            releaseChildSource(source)
        }
    }

    private fun loadingAt(positionUs: Long) =
        LoadingInfo.Builder().setPlaybackPositionUs(positionUs).build()

    private inner class AudioPeriod(
        val id: MediaPeriodId,
        val allocator: Allocator,
        var source: MediaSource,
        var current: MediaPeriod,
    ) : MediaPeriod {
        private lateinit var callback: MediaPeriod.Callback
        private lateinit var exposedGroups: TrackGroupArray
        private var replacementSelection: FixedTrackSelection? = null
        private var selectedStream: AudioStream? = null
        private var endPositionUs: Long? = null
        private var usesStreamPrerollFlags = false
        var audioMimeType: String? = null
            private set
        val canSwitch get() = audioMimeType != null && selectedStream?.ended == false

        override fun prepare(callback: MediaPeriod.Callback, positionUs: Long) {
            this.callback = callback
            current.prepare(object : MediaPeriod.Callback {
                override fun onPrepared(mediaPeriod: MediaPeriod) {
                    exposedGroups = mediaPeriod.trackGroups
                    callback.onPrepared(this@AudioPeriod)
                }

                override fun onContinueLoadingRequested(source: MediaPeriod) {
                    if (source === current) requestLoading()
                }
            }, positionUs)
        }

        fun requestLoading() = callback.onContinueLoadingRequested(this)
        fun nextSampleUs(positionUs: Long) =
            maxOf(positionUs, (selectedStream?.lastSampleUs ?: Long.MIN_VALUE) + 1)

        fun applyPeriodSettings(period: MediaPeriod) {
            endPositionUs?.let(period::setEndPositionUs)
            if (usesStreamPrerollFlags) period.setUsesStreamPrerollFlags()
        }

        fun replace(source: MediaSource, period: MediaPeriod, selection: FixedTrackSelection, stream: SampleStream) {
            this.source = source
            current = period
            replacementSelection = selection
            checkNotNull(selectedStream).replace(stream)
        }

        override fun getTrackGroups(): TrackGroupArray = exposedGroups
        override fun maybeThrowPrepareError() = current.maybeThrowPrepareError()

        override fun selectTracks(
            selections: Array<out ExoTrackSelection?>,
            mayRetainStreamFlags: BooleanArray,
            streams: Array<SampleStream?>,
            streamResetFlags: BooleanArray,
            positionUs: Long,
        ): Long {
            val childSelections = Array(selections.size) { index ->
                selections[index]?.let { replacementSelection ?: it }
            }
            val childStreams = Array(streams.size) { index -> (streams[index] as? AudioStream)?.child }
            val actualPositionUs = current.selectTracks(
                childSelections, mayRetainStreamFlags, childStreams, streamResetFlags, positionUs,
            )
            selectedStream = null
            audioMimeType = null
            for (index in streams.indices) {
                val child = childStreams[index]
                val previous = streams[index] as? AudioStream
                streams[index] = when {
                    child == null -> null
                    previous?.child === child -> previous.also {
                        if (streamResetFlags[index]) it.reset()
                    }
                    else -> AudioStream(child)
                }
                val selection = childSelections[index]
                if (selection?.trackGroup?.type == C.TRACK_TYPE_AUDIO) {
                    selectedStream = streams[index] as? AudioStream
                    audioMimeType = selection.selectedFormat.sampleMimeType
                }
            }
            return actualPositionUs
        }

        override fun seekToUs(positionUs: Long): Long {
            cancelSwitch(this)
            selectedStream?.reset()
            return current.seekToUs(positionUs)
        }

        override fun discardBuffer(positionUs: Long, toKeyframe: Boolean) =
            current.discardBuffer(positionUs, toKeyframe)
        override fun readDiscontinuity(): Long = current.readDiscontinuity()
        override fun getAdjustedSeekPositionUs(positionUs: Long, seekParameters: SeekParameters): Long =
            current.getAdjustedSeekPositionUs(positionUs, seekParameters)
        override fun getBufferedPositionUs(): Long = current.bufferedPositionUs
        override fun getNextLoadPositionUs(): Long = current.nextLoadPositionUs
        override fun continueLoading(loadingInfo: LoadingInfo): Boolean = current.continueLoading(loadingInfo)
        override fun isLoading(): Boolean = current.isLoading
        override fun reevaluateBuffer(positionUs: Long) = current.reevaluateBuffer(positionUs)
        override fun setEndPositionUs(positionUs: Long): Long {
            endPositionUs = positionUs
            return current.setEndPositionUs(positionUs)
        }

        override fun setUsesStreamPrerollFlags() {
            usesStreamPrerollFlags = true
            current.setUsesStreamPrerollFlags()
        }
    }

    private class AudioStream(var child: SampleStream) : SampleStream {
        var lastSampleUs = Long.MIN_VALUE
            private set
        var ended = false
            private set
        private var requireFormat = false

        fun replace(newChild: SampleStream) {
            child = newChild
            // 探测备用轨时已读过格式，交给解码器的第一条消息仍需携带新格式。
            requireFormat = true
        }

        fun reset() {
            lastSampleUs = Long.MIN_VALUE
            ended = false
        }

        override fun isReady(): Boolean = child.isReady
        override fun maybeThrowError() = child.maybeThrowError()
        override fun getFlags(): Int = child.flags
        override fun skipData(positionUs: Long): Int = child.skipData(positionUs)

        override fun readData(holder: FormatHolder, buffer: DecoderInputBuffer, readFlags: Int): Int {
            val flags = if (requireFormat) readFlags or SampleStream.FLAG_REQUIRE_FORMAT else readFlags
            val result = child.readData(holder, buffer, flags)
            if (result == C.RESULT_FORMAT_READ) requireFormat = false
            if (result == C.RESULT_BUFFER_READ && flags and SampleStream.FLAG_PEEK == 0) {
                ended = buffer.isEndOfStream
                if (!ended) lastSampleUs = buffer.timeUs
            }
            return result
        }
    }
}
