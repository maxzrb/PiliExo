package com.maxzrb.piliexo

import android.app.Activity
import android.content.Context
import android.content.pm.ActivityInfo
import android.graphics.Bitmap
import android.graphics.Color
import android.media.MediaCodecList
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Base64
import android.util.TypedValue
import android.view.LayoutInflater
import android.view.PixelCopy
import android.view.SurfaceView
import android.view.View
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.Player
import androidx.media3.common.PlaybackException
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.TransferListener
import androidx.media3.exoplayer.DecoderCounters
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlaybackException
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.mediacodec.MediaCodecUtil
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.LoadEventInfo
import androidx.media3.exoplayer.source.MediaLoadData
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.upstream.BandwidthMeter
import androidx.media3.exoplayer.upstream.DefaultBandwidthMeter
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.CaptionStyleCompat
import androidx.media3.ui.PlayerView
import androidx.media3.ui.SubtitleView
import androidx.media3.datasource.okhttp.OkHttpDataSource
import okhttp3.OkHttpClient
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.embedding.engine.FlutterEngine
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.nio.charset.StandardCharsets
import java.util.ArrayDeque
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicLong

/** Android 原生 HDR 播放器的 Flutter 桥接层。 */
@UnstableApi
class HdrMedia3Plugin(
    private val context: Context,
    private val messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        const val METHOD_CHANNEL = "com.maxzrb.piliexo/media3_hdr"
        const val EVENT_CHANNEL = "com.maxzrb.piliexo/media3_hdr/events"
        const val VIEW_TYPE = "piliexo/media3_hdr_surface"
    }

    private var eventSink: EventChannel.EventSink? = null
    // 会话需要使用 Activity 上下文读取当前显示器的 HDR 能力，同时由会话生命周期控制播放器。
    private val manager = HdrMedia3Manager(context) { event ->
        eventSink?.success(event)
    }
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)

    fun register(engine: FlutterEngine) {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        engine.platformViewsController.registry.registerViewFactory(
            VIEW_TYPE,
            HdrMedia3ViewFactory(manager),
        )
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "createSession" -> {
                    val sessionId = call.argument<String>("sessionId")
                        ?: error("缺少 sessionId")
                    manager.create(sessionId)
                    result.success(null)
                }

                "load" -> {
                    val sessionId = call.argument<String>("sessionId")
                        ?: error("缺少 sessionId")
                    manager.get(sessionId).load(
                        HdrMedia3Source.from(call.arguments),
                        call.argument<Number>("startPositionMs")?.toLong() ?: 0L,
                        call.argument<Boolean>("playWhenReady") ?: false,
                    )
                    result.success(null)
                }

                "play" -> {
                    manager.getSession(call).play()
                    result.success(null)
                }

                "pause" -> {
                    manager.getSession(call).pause()
                    result.success(null)
                }

                "seekTo" -> {
                    val position = call.argument<Number>("positionMs")?.toLong()
                        ?: error("缺少 positionMs")
                    manager.getSession(call).seekTo(position)
                    result.success(null)
                }

                "setSpeed" -> {
                    val speed = call.argument<Number>("speed")?.toFloat()
                        ?: error("缺少 speed")
                    manager.getSession(call).setSpeed(speed)
                    result.success(null)
                }

                "setVolume" -> {
                    val volume = call.argument<Number>("volume")?.toFloat()
                        ?: error("缺少 volume")
                    manager.getSession(call).setVolume(volume)
                    result.success(null)
                }

                "setResizeMode" -> {
                    manager.getSession(call).setResizeMode(
                        call.argument<String>("mode") ?: "fit",
                    )
                    result.success(null)
                }

                "hideSurface" -> {
                    manager.getSession(call).hideSurface()
                    result.success(null)
                }

                "captureAmbientFrame" -> {
                    val width = (call.argument<Number>("width")?.toInt() ?: 96)
                        .coerceIn(16, 256)
                    val height = (call.argument<Number>("height")?.toInt() ?: 54)
                        .coerceIn(16, 256)
                    manager.getSession(call).captureAmbientFrame(width, height) {
                        result.success(it)
                    }
                }

                "setSubtitle" -> {
                    manager.getSession(call).setSubtitle(
                        call.argument<String>("vtt"),
                        call.argument<String>("language"),
                        call.argument<String>("label"),
                    )
                    result.success(null)
                }

                "clearSubtitle" -> {
                    manager.getSession(call).setSubtitle(null, null, null)
                    result.success(null)
                }

                "setSubtitleStyle" -> {
                    manager.getSession(call).setSubtitleStyle(
                        call.argument<Number>("fontScale")?.toFloat() ?: 1.0f,
                        call.argument<Number>("bottomPadding")?.toFloat() ?: 24.0f,
                        call.argument<Number>("horizontalPadding")?.toFloat() ?: 24.0f,
                        call.argument<Number>("backgroundOpacity")?.toFloat() ?: 0.67f,
                    )
                    result.success(null)
                }

                "releaseSession" -> {
                    val sessionId = call.argument<String>("sessionId")
                        ?: error("缺少 sessionId")
                    manager.release(sessionId)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            result.error("MEDIA3_ERROR", error.message, null)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun dispose() {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        manager.releaseAll()
        eventSink = null
    }
}

@UnstableApi
private class HdrMedia3ViewFactory(
    private val manager: HdrMedia3Manager,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *>
        val sessionId = params?.get("sessionId") as? String
            ?: error("缺少 sessionId")
        return HdrMedia3PlatformView(manager.get(sessionId))
    }
}

@UnstableApi
private class HdrMedia3PlatformView(
    private val session: HdrMedia3Session,
) : PlatformView {
    private val playerView = session.createView()

    init {
        session.attach(playerView)
    }

    override fun getView(): View = playerView

    override fun dispose() {
        session.detach(playerView)
    }
}

@UnstableApi
private class HdrMedia3Manager(
    private val context: Context,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    private val sessions = linkedMapOf<String, HdrMedia3Session>()

    fun create(sessionId: String): HdrMedia3Session {
        return sessions.getOrPut(sessionId) {
            HdrMedia3Session(context, sessionId, emit)
        }
    }

    fun get(sessionId: String): HdrMedia3Session = create(sessionId)

    fun getSession(call: MethodCall): HdrMedia3Session {
        val sessionId = call.argument<String>("sessionId")
            ?: error("缺少 sessionId")
        return get(sessionId)
    }

    fun release(sessionId: String) {
        sessions.remove(sessionId)?.release()
    }

    fun releaseAll() {
        sessions.values.toList().forEach(HdrMedia3Session::release)
        sessions.clear()
    }
}

@UnstableApi
internal data class HdrMedia3Track(
    val urls: List<Uri>,
    val mimeType: String?,
    val codecs: String?,
    val width: Int,
    val height: Int,
    val frameRate: String?,
    val bitrate: Int?,
)

@UnstableApi
internal data class HdrMedia3Representation(
    val id: String,
    val qualityCode: Int,
    val track: HdrMedia3Track,
)

/**
 * Media3 明确报告视频解码/格式错误后使用的候选状态。
 *
 * 候选顺序由 Dart 按同分辨率 codec、再按较低清晰度准备；状态类只负责记忆
 * 已失败的 Representation，任何候选都不会被重复尝试，从而避免错误回调造成循环。
 */
@UnstableApi
internal class RepresentationFallbackState(
    val representations: List<HdrMedia3Representation>,
) {
    var currentIndex: Int = 0
        private set
    private val failedIds = linkedSetOf<String>()

    val current: HdrMedia3Representation?
        get() = representations.getOrNull(currentIndex)

    val failedRepresentationIds: Set<String>
        get() = failedIds.toSet()

    fun reset(currentId: String?) {
        failedIds.clear()
        currentIndex = representations.indexOfFirst { it.id == currentId }
            .takeIf { it >= 0 } ?: 0
    }

    /** 标记当前候选失败，并返回下一个尚未尝试的候选。 */
    fun markCurrentFailedAndGetNext(): HdrMedia3Representation? {
        val failed = current ?: return null
        if (!failedIds.add(failed.id)) return null
        val nextIndex = (currentIndex + 1 until representations.size)
            .firstOrNull { !failedIds.contains(representations[it].id) }
            ?: return null
        currentIndex = nextIndex
        return representations[currentIndex]
    }
}

/** Representation 切换时需要从当前播放器复制的运行状态。 */
internal data class RepresentationFallbackPlan(
    val representation: HdrMedia3Representation,
    val positionMs: Long,
    val playWhenReady: Boolean,
    val speed: Float,
)

internal fun createRepresentationFallbackPlan(
    representation: HdrMedia3Representation,
    positionMs: Long,
    playWhenReady: Boolean,
    speed: Float,
): RepresentationFallbackPlan = RepresentationFallbackPlan(
    representation = representation,
    positionMs = positionMs.coerceAtLeast(0L),
    playWhenReady = playWhenReady,
    speed = speed,
)

/** 只有用户仍然准备播放时才允许带宽采样，暂停后冻结当前估计值。 */
internal class BandwidthSamplingGate {
    @Volatile
    var enabled: Boolean = false
        private set

    fun setPlayWhenReady(playWhenReady: Boolean) {
        enabled = playWhenReady
    }
}

/** 根据媒体缓存窗口的实际字节数和时长计算媒体内容码率。 */
internal class MediaBufferBitrateEstimator {
    private var previousBytes = -1L
    private var previousBufferedPositionMs = Long.MIN_VALUE
    private var pendingBytes = 0L
    private var lastEstimate = -1L

    fun sample(totalBytes: Long, bufferedPositionMs: Long): Long {
        if (totalBytes < 0L || bufferedPositionMs < 0L ||
            bufferedPositionMs >= Long.MAX_VALUE / 2
        ) {
            return lastEstimate
        }

        if (previousBytes < 0L || previousBufferedPositionMs == Long.MIN_VALUE) {
            previousBytes = totalBytes
            previousBufferedPositionMs = bufferedPositionMs
            return lastEstimate
        }

        if (totalBytes < previousBytes ||
            bufferedPositionMs < previousBufferedPositionMs
        ) {
            // 发生 seek、切换媒体或重新建立 Range 请求时重新建立基线。
            previousBytes = totalBytes
            previousBufferedPositionMs = bufferedPositionMs
            pendingBytes = 0L
            return lastEstimate
        }

        pendingBytes += totalBytes - previousBytes
        val durationDeltaMs = bufferedPositionMs - previousBufferedPositionMs
        previousBytes = totalBytes
        previousBufferedPositionMs = bufferedPositionMs
        if (durationDeltaMs < 250L || pendingBytes <= 0L) return lastEstimate

        val estimate = (pendingBytes.toDouble() * 8_000.0 / durationDeltaMs).toLong()
        pendingBytes = 0L
        if (estimate > 0L) lastEstimate = estimate
        return lastEstimate
    }

    fun reset() {
        previousBytes = -1L
        previousBufferedPositionMs = Long.MIN_VALUE
        pendingBytes = 0L
        lastEstimate = -1L
    }
}

/**
 * 将播放状态门控放在 Media3 注入的唯一 TransferListener 上，避免同一传输被重复统计。
 *
 * ExoPlayer 会通过 BandwidthMeter.getTransferListener() 自动把监听器加入 MediaSource 的
 * DataSource，因此调用方不应再把另一个转发监听器直接挂到 HTTP 工厂。
 */
@UnstableApi
internal class GatedBandwidthMeter(
    private val delegate: BandwidthMeter,
    private val isSamplingEnabled: () -> Boolean,
) : BandwidthMeter {
    private data class TransferKey(
        val source: DataSource,
        val uri: Uri,
        val position: Long,
        val length: Long,
        val key: String?,
    )

    private val delegateTransferListener = checkNotNull(delegate.getTransferListener())
    private val activeTransfers = mutableMapOf<TransferKey, Int>()
    private val transferListener = object : TransferListener {
        override fun onTransferInitializing(
            source: DataSource,
            dataSpec: DataSpec,
            isNetwork: Boolean,
        ) {
            if (isSamplingEnabled()) {
                delegateTransferListener.onTransferInitializing(source, dataSpec, isNetwork)
            }
        }

        override fun onTransferStart(
            source: DataSource,
            dataSpec: DataSpec,
            isNetwork: Boolean,
        ) {
            if (!markTransferStarted(source, dataSpec)) return
            delegateTransferListener.onTransferStart(source, dataSpec, isNetwork)
        }

        override fun onBytesTransferred(
            source: DataSource,
            dataSpec: DataSpec,
            isNetwork: Boolean,
            bytesTransferred: Int,
        ) {
            // 暂停期间不计入新字节，但仍需结束暂停前已开始的传输，避免 meter
            // 永久保留未闭合的样本；恢复播放后新传输会重新开始计量。
            if (isSamplingEnabled() && hasActiveTransfer(source, dataSpec)) {
                delegateTransferListener.onBytesTransferred(
                    source,
                    dataSpec,
                    isNetwork,
                    bytesTransferred,
                )
            }
        }

        override fun onTransferEnd(
            source: DataSource,
            dataSpec: DataSpec,
            isNetwork: Boolean,
        ) {
            if (!markTransferEnded(source, dataSpec)) return
            delegateTransferListener.onTransferEnd(source, dataSpec, isNetwork)
        }
    }

    override fun getBitrateEstimate(): Long = delegate.getBitrateEstimate()

    override fun getTimeToFirstByteEstimateUs(): Long =
        delegate.getTimeToFirstByteEstimateUs()

    override fun getTransferListener(): TransferListener = transferListener

    override fun addEventListener(
        eventHandler: Handler,
        eventListener: BandwidthMeter.EventListener,
    ) {
        delegate.addEventListener(eventHandler, eventListener)
    }

    override fun removeEventListener(eventListener: BandwidthMeter.EventListener) {
        delegate.removeEventListener(eventListener)
    }

    private fun transferKey(source: DataSource, dataSpec: DataSpec) = TransferKey(
        source = source,
        uri = dataSpec.uri,
        position = dataSpec.position,
        length = dataSpec.length,
        key = dataSpec.key,
    )

    private fun markTransferStarted(source: DataSource, dataSpec: DataSpec): Boolean {
        if (!isSamplingEnabled()) return false
        val key = transferKey(source, dataSpec)
        synchronized(activeTransfers) {
            activeTransfers[key] = (activeTransfers[key] ?: 0) + 1
        }
        return true
    }

    private fun hasActiveTransfer(source: DataSource, dataSpec: DataSpec): Boolean =
        synchronized(activeTransfers) {
            activeTransfers[transferKey(source, dataSpec)]?.let { it > 0 } == true
        }

    private fun markTransferEnded(source: DataSource, dataSpec: DataSpec): Boolean {
        val key = transferKey(source, dataSpec)
        synchronized(activeTransfers) {
            val count = activeTransfers[key] ?: return false
            if (count <= 1) {
                activeTransfers.remove(key)
            } else {
                activeTransfers[key] = count - 1
            }
        }
        return true
    }
}

/** 使用可靠的 Android/Media3 codec 能力标记生成洞察中的硬软解文案。 */
internal fun decoderTypeFromFlags(
    hardwareAccelerated: Boolean,
    softwareOnly: Boolean,
): String = when {
    hardwareAccelerated -> "硬解"
    softwareOnly -> "软解"
    else -> "未知"
}

@UnstableApi
internal data class HdrMedia3Source(
    val qualityCode: Int,
    val video: HdrMedia3Track,
    val videoRepresentations: List<HdrMedia3Representation>,
    val audio: HdrMedia3Track?,
    val headers: Map<String, String>,
    val durationMs: Long?,
    val subtitleVtt: String?,
    val subtitleLanguage: String?,
    val subtitleLabel: String?,
) {
    companion object {
        fun from(arguments: Any?): HdrMedia3Source {
            val map = arguments as? Map<*, *> ?: error("播放参数格式错误")
            val video = parseTrack(map["video"] as? Map<*, *> ?: error("缺少视频轨道"))
            val qualityCode = (map["qualityCode"] as? Number)?.toInt()
                ?: error("缺少 qualityCode")
            val videoRepresentations = (map["videoRepresentations"] as? List<*>)
                ?.mapNotNull { item ->
                    val representation = item as? Map<*, *> ?: return@mapNotNull null
                    val track = try {
                        parseTrack(representation)
                    } catch (_: Throwable) {
                        return@mapNotNull null
                    }
                    HdrMedia3Representation(
                        id = representation["id"] as? String
                            ?: "representation-${track.codecs ?: track.mimeType ?: track.urls.first()}",
                        qualityCode = (representation["qualityCode"] as? Number)?.toInt()
                            ?: qualityCode,
                        track = track,
                    )
                }
                ?.distinctBy(HdrMedia3Representation::id)
                ?.takeIf { it.isNotEmpty() }
                ?: listOf(HdrMedia3Representation("primary", qualityCode, video))
            val audioMap = map["audio"] as? Map<*, *>
            val headers = (map["headers"] as? Map<*, *>)
                ?.mapNotNull { (key, value) ->
                    if (key is String && value is String) key to value else null
                }
                ?.toMap()
                ?: emptyMap()
            return HdrMedia3Source(
                qualityCode = qualityCode,
                video = video,
                videoRepresentations = videoRepresentations,
                audio = audioMap?.let(::parseTrack),
                headers = headers,
                durationMs = (map["durationMs"] as? Number)?.toLong(),
                subtitleVtt = map["subtitleVtt"] as? String,
                subtitleLanguage = map["subtitleLanguage"] as? String,
                subtitleLabel = map["subtitleLabel"] as? String,
            )
        }

        private fun parseTrack(map: Map<*, *>): HdrMedia3Track {
            val urls = ((map["urls"] as? List<*>) ?: emptyList<Any?>())
                .filterIsInstance<String>()
                .filter(String::isNotBlank)
                .distinct()
                .map(Uri::parse)
            if (urls.isEmpty()) error("轨道 URL 为空")
            return HdrMedia3Track(
                urls = urls,
                mimeType = map["mimeType"] as? String,
                codecs = map["codecs"] as? String,
                width = (map["width"] as? Number)?.toInt() ?: 0,
                height = (map["height"] as? Number)?.toInt() ?: 0,
                frameRate = map["frameRate"] as? String,
                bitrate = (map["bitrate"] as? Number)?.toInt(),
            )
        }
    }
}

@UnstableApi
private class HdrMedia3Session(
    private val context: Context,
    private val sessionId: String,
    private val emit: (Map<String, Any?>) -> Unit,
) : Player.Listener, AnalyticsListener {
    private val handler = Handler(Looper.getMainLooper())
    private val httpClient = OkHttpClient.Builder()
        .retryOnConnectionFailure(true)
        .build()
    private val bandwidthMeter = DefaultBandwidthMeter.Builder(context).build()
    private val bandwidthSamplingGate = BandwidthSamplingGate()
    private val mediaBytesRead = AtomicLong(0L)
    private val mediaBufferBitrateEstimator = MediaBufferBitrateEstimator()
    private val gatedBandwidthMeter = GatedBandwidthMeter(
        delegate = bandwidthMeter,
        isSamplingEnabled = { bandwidthSamplingGate.enabled },
    )
    private val player: ExoPlayer = ExoPlayer.Builder(
        context,
        DefaultRenderersFactory(context)
            // 先使用设备硬解；设备没有可用 AC-3/E-AC-3 解码器时再使用 FFmpeg 软件解码。
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
            .setEnableDecoderFallback(true),
    ).setBandwidthMeter(gatedBandwidthMeter).build().also { exoPlayer ->
        exoPlayer.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                .build(),
            false,
        )
        // Audio Focus 和 becoming-noisy 统一由 Flutter 的 AudioSessionHandler 处理，
        // Media3 只负责解码和输出，避免两套生命周期互相暂停/恢复。
        exoPlayer.setHandleAudioBecomingNoisy(false)
        exoPlayer.addListener(this)
        exoPlayer.addAnalyticsListener(this)
    }
    private var playerView: PlayerView? = null
    private var source: HdrMedia3Source? = null
    private var sourceFingerprint = ""
    private var fallbackState = RepresentationFallbackState(emptyList())
    private val fallbackHistory = mutableListOf<Map<String, Any?>>()
    private var released = false
    private var errorSent = false
    private var subtitleFontScale = 1.0f
    private var subtitleBottomPadding = 24.0f
    private var subtitleHorizontalPadding = 24.0f
    private var subtitleBackgroundOpacity = 0.67f
    private var resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
    private var hdrWindowModeEnabled = false
    private var ambientCaptureInFlight = false
    private var lastVideoFormat: Format? = null
    private var lastAudioFormat: Format? = null
    private var lastVideoCodecError = ""
    private var lastAudioCodecError = ""
    private var currentCdnUri = ""
    private var lastLoadTrackType = C.TRACK_TYPE_UNKNOWN
    private var bandwidthEstimate = -1L
    private var cumulativeDroppedFrames = 0
    private val droppedFrameSamples = ArrayDeque<DroppedFrameSample>()

    private data class DroppedFrameSample(
        val timestampMs: Long,
        val count: Int,
    )

    private val progressRunnable = object : Runnable {
        override fun run() {
            if (released) return
            // 缓冲阶段 isPlaying 可能为 false，但只要仍准备播放就要继续刷新缓冲和带宽。
            bandwidthSamplingGate.setPlayWhenReady(shouldSampleBandwidth())
            emitProgress()
            if (bandwidthSamplingGate.enabled) handler.postDelayed(this, 100)
        }
    }

    fun createView(): PlayerView {
        check(!released) { "播放器已经释放" }
        return LayoutInflater.from(context)
            .inflate(R.layout.view_hdr_player, null, false) as PlayerView
    }

    fun attach(view: PlayerView) {
        if (released) return
        playerView = view
        view.useController = false
        view.setKeepContentOnPlayerReset(true)
        view.resizeMode = resizeMode
        view.player = player
        view.alpha = 1f
        view.videoSurfaceView?.visibility = View.VISIBLE
        view.videoSurfaceView?.alpha = 1f
        view.visibility = View.VISIBLE
        applySubtitleStyle(
            view,
            subtitleFontScale,
            subtitleBottomPadding,
            subtitleHorizontalPadding,
            subtitleBackgroundOpacity,
        )
    }

    fun detach(view: PlayerView) {
        if (playerView === view) {
            hideSurface(view)
            playerView = null
        }
    }

    fun hideSurface() {
        playerView?.let(::hideSurface)
    }

    /**
     * 从 HDR SurfaceView 复制一张很小的当前帧，供 Flutter 顶部系统状态栏做环境背景。
     *
     * 这里使用 PixelCopy 只读取 SurfaceView 的画面，HDR 播放链路仍然直接输出到
     * SurfaceView，不会经过 TextureView、Flutter Texture 或软件视频合成。
     */
    fun captureAmbientFrame(width: Int, height: Int, callback: (ByteArray?) -> Unit) {
        if (released || Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            callback(null)
            return
        }
        val surfaceView = playerView?.videoSurfaceView as? SurfaceView
        if (surfaceView == null || !surfaceView.isAttachedToWindow ||
            surfaceView.width <= 0 || surfaceView.height <= 0 ||
            ambientCaptureInFlight
        ) {
            callback(null)
            return
        }

        val bitmap = try {
            Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        } catch (_: Throwable) {
            callback(null)
            return
        }
        ambientCaptureInFlight = true
        try {
            PixelCopy.request(
                surfaceView,
                bitmap,
                { copyResult ->
                    ambientCaptureInFlight = false
                    if (copyResult != PixelCopy.SUCCESS || released) {
                        bitmap.recycle()
                        callback(null)
                        return@request
                    }
                    val output = ByteArrayOutputStream()
                    val compressed = try {
                        bitmap.compress(Bitmap.CompressFormat.PNG, 90, output)
                    } catch (_: Throwable) {
                        false
                    } finally {
                        bitmap.recycle()
                    }
                    callback(if (compressed) output.toByteArray() else null)
                },
                handler,
            )
        } catch (_: Throwable) {
            ambientCaptureInFlight = false
            bitmap.recycle()
            callback(null)
        }
    }

    private fun hideSurface(view: PlayerView) {
        // SurfaceView 使用独立合成层，路由切换前必须移除其合成层，不能只清空播放器引用。
        view.visibility = View.GONE
        view.alpha = 0f
        val surfaceView = view.videoSurfaceView
        surfaceView?.visibility = View.GONE
        surfaceView?.alpha = 0f
        when (surfaceView) {
            is SurfaceView -> player.clearVideoSurfaceView(surfaceView)
            else -> player.clearVideoSurface()
        }
        view.setKeepContentOnPlayerReset(false)
        view.player = null
    }

    fun load(newSource: HdrMedia3Source, startPositionMs: Long = 0L, playWhenReady: Boolean = false) {
        check(!released) { "播放器已经释放" }
        val fingerprint = fingerprintOf(newSource)
        if (fingerprint != sourceFingerprint) {
            sourceFingerprint = fingerprint
            val representations = newSource.videoRepresentations.ifEmpty {
                listOf(HdrMedia3Representation("primary", newSource.qualityCode, newSource.video))
            }
            fallbackState = RepresentationFallbackState(representations)
            fallbackState.reset(representations.firstOrNull()?.id)
            fallbackHistory.clear()
            resetDiagnostics()
        } else {
            resetMediaConsumptionStats()
        }
        source = newSource
        errorSent = false
        setHdrWindowMode(true)
        val representation = fallbackState.current
            ?: HdrMedia3Representation("primary", newSource.qualityCode, newSource.video)
        val mediaSource = buildMediaSource(newSource, representation)
        player.setMediaSource(mediaSource, startPositionMs.coerceAtLeast(0L))
        player.playWhenReady = playWhenReady
        bandwidthSamplingGate.setPlayWhenReady(playWhenReady)
        player.prepare()
        emitEvent(
            "loading",
            mapOf(
                // 这里展示当前实际尝试的 Representation；用户目标清晰度可能在
                // 本次 session 中已经降级，不能继续使用源请求的 qualityCode。
                "qualityCode" to representation.qualityCode,
                "durationMs" to newSource.durationMs,
                "hdrSupported" to true,
                "videoMimeType" to representation.track.mimeType,
                "videoCodecs" to representation.track.codecs,
                "videoFrameRate" to representation.track.frameRate,
                "audioMimeType" to newSource.audio?.mimeType,
                "audioCodecs" to newSource.audio?.codecs,
            ) + representationData(representation) + mapOf(
                "fallbackHistory" to fallbackHistory.toList(),
            ),
        )
        startTicker()
    }

    fun play() {
        if (!released) {
            bandwidthSamplingGate.setPlayWhenReady(true)
            player.play()
            startTicker()
        }
    }

    fun pause() {
        if (!released) {
            // 先关闭采样，再让播放器停止，避免暂停边界仍把网络数据计入带宽。
            bandwidthSamplingGate.setPlayWhenReady(false)
            player.pause()
            startTicker()
        }
    }

    fun seekTo(positionMs: Long) {
        if (!released) {
            resetMediaConsumptionStats()
            player.seekTo(positionMs.coerceAtLeast(0L))
            emitProgress()
        }
    }

    fun setSpeed(speed: Float) {
        if (!released) player.setPlaybackSpeed(speed.coerceIn(0.1f, 4.0f))
    }

    fun setVolume(volume: Float) {
        if (!released) player.volume = volume.coerceIn(0.0f, 1.0f)
    }

    fun setResizeMode(mode: String) {
        resizeMode = when (mode) {
            "fill" -> AspectRatioFrameLayout.RESIZE_MODE_FILL
            "cover" -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
            "fitWidth" -> AspectRatioFrameLayout.RESIZE_MODE_FIXED_WIDTH
            "fitHeight" -> AspectRatioFrameLayout.RESIZE_MODE_FIXED_HEIGHT
            else -> AspectRatioFrameLayout.RESIZE_MODE_FIT
        }
        playerView?.resizeMode = resizeMode
    }

    fun setSubtitle(vtt: String?, language: String?, label: String?) {
        val current = source ?: return
        rebuild(
            current.copy(
                subtitleVtt = vtt,
                subtitleLanguage = language,
                subtitleLabel = label,
            ),
        )
    }

    fun setSubtitleStyle(
        fontScale: Float,
        bottomPadding: Float,
        horizontalPadding: Float,
        backgroundOpacity: Float,
    ) {
        subtitleFontScale = fontScale.coerceIn(0.5f, 2.5f)
        subtitleBottomPadding = bottomPadding.coerceIn(0.0f, 240.0f)
        subtitleHorizontalPadding = horizontalPadding.coerceIn(0.0f, 240.0f)
        subtitleBackgroundOpacity = backgroundOpacity.coerceIn(0.0f, 1.0f)
        applySubtitleStyle(
            playerView,
            subtitleFontScale,
            subtitleBottomPadding,
            subtitleHorizontalPadding,
            subtitleBackgroundOpacity,
        )
    }

    private fun rebuild(newSource: HdrMedia3Source) {
        if (released) return
        val position = player.currentPosition
        val playWhenReady = player.playWhenReady
        val speed = player.playbackParameters.speed
        load(newSource, position, playWhenReady)
        player.setPlaybackSpeed(speed)
    }

    private fun buildMediaSource(
        source: HdrMedia3Source,
        representation: HdrMedia3Representation,
    ): MediaSource {
        val candidateMap = linkedMapOf<String, List<Uri>>()
        candidateMap[representation.track.urls.first().toString()] = representation.track.urls
        source.audio?.let { candidateMap[it.urls.first().toString()] = it.urls }

        val httpFactory = OkHttpDataSource.Factory(httpClient)
            .setDefaultRequestProperties(source.headers)
        val defaultFactory = DefaultDataSource.Factory(context, httpFactory)
        val fallbackFactory = DataSource.Factory {
            MultiUriDataSource(defaultFactory, candidateMap) { bytes ->
                // 媒体窗口统计包含暂停期间已经缓存的内容；它与只统计播放时段的
                // 网络吞吐 meter 是两套独立指标。
                mediaBytesRead.addAndGet(bytes)
            }
        }
        val videoItemBuilder = MediaItem.Builder()
            .setMediaId("$sessionId-video-${representation.id}")
            .setUri(representation.track.urls.first())
        representation.track.mimeType?.takeIf(String::isNotBlank)
            ?.let(videoItemBuilder::setMimeType)
        if (!source.subtitleVtt.isNullOrBlank()) {
            val encoded = Base64.encodeToString(
                source.subtitleVtt.toByteArray(StandardCharsets.UTF_8),
                Base64.NO_WRAP,
            )
            val subtitleUri = Uri.parse("data:text/vtt;base64,$encoded")
            val subtitle = MediaItem.SubtitleConfiguration.Builder(subtitleUri)
                .setMimeType(MimeTypes.TEXT_VTT)
                .setLanguage(source.subtitleLanguage ?: "und")
                .setLabel(source.subtitleLabel)
                .setSelectionFlags(C.SELECTION_FLAG_DEFAULT)
                .build()
            videoItemBuilder.setSubtitleConfigurations(listOf(subtitle))
        }

        // B 站 DASH 返回的是分离的 fMP4，两个轨道都固定走 ProgressiveMediaSource，
        // 避免凭 URL 后缀误判媒体类型。
        val progressiveFactory = ProgressiveMediaSource.Factory(fallbackFactory)
        val videoSource = progressiveFactory.createMediaSource(videoItemBuilder.build())
        val audio = source.audio
        if (audio == null) return videoSource

        val audioItem = MediaItem.Builder()
            .setMediaId("$sessionId-audio")
            .setUri(audio.urls.first())
            .apply {
                audio.mimeType?.takeIf(String::isNotBlank)?.let(::setMimeType)
            }
            .build()
        val audioSource = ProgressiveMediaSource.Factory(fallbackFactory)
            .createMediaSource(audioItem)
        return MergingMediaSource(true, true, videoSource, audioSource)
    }

    private fun fingerprintOf(source: HdrMedia3Source): String = buildString {
        append(source.qualityCode)
        source.videoRepresentations.forEach { representation ->
            append('|')
            append(representation.id)
            append(':')
            append(representation.qualityCode)
            append(':')
            append(representation.track.urls.joinToString(","))
        }
        append('|')
        append(source.audio?.urls?.joinToString(","))
    }

    private fun resetDiagnostics() {
        lastVideoFormat = null
        lastAudioFormat = null
        lastVideoCodecError = ""
        lastAudioCodecError = ""
        currentCdnUri = ""
        lastLoadTrackType = C.TRACK_TYPE_UNKNOWN
        bandwidthEstimate = -1L
        resetMediaConsumptionStats()
        cumulativeDroppedFrames = 0
        droppedFrameSamples.clear()
    }

    private fun representationData(
        representation: HdrMedia3Representation,
    ): Map<String, Any?> {
        val track = representation.track
        val dimensions = if (track.width > 0 && track.height > 0) {
            "${track.width}x${track.height}"
        } else {
            ""
        }
        val label = listOf(
            representation.id,
            "q=${representation.qualityCode}",
            dimensions,
            track.codecs ?: track.mimeType ?: "",
        ).filter(String::isNotEmpty).joinToString(" · ")
        return mapOf(
            "representationId" to representation.id,
            "representation" to label,
            "representationQualityCode" to representation.qualityCode,
            "representationWidth" to track.width,
            "representationHeight" to track.height,
            "representationCodecs" to track.codecs,
            "representationBitrate" to track.bitrate,
        )
    }

    private fun platformDecoderInfo(decoderName: String): android.media.MediaCodecInfo? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return null
        return try {
            MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos.firstOrNull { info ->
                !info.isEncoder && info.name.equals(decoderName, ignoreCase = true)
            }
        } catch (_: Throwable) {
            null
        }
    }

    private fun decoderType(decoderName: String, format: Format?): String {
        // Android 10+ 直接提供硬件加速/纯软件 codec 标记，优先使用实际初始化的 codec。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            platformDecoderInfo(decoderName)?.let { info ->
                val type = decoderTypeFromFlags(
                    hardwareAccelerated = info.isHardwareAccelerated,
                    softwareOnly = info.isSoftwareOnly,
                )
                if (type != "未知") return type
            }
        }

        // 低版本没有 Android 标记时，使用 Media3 对同一 codec 的能力标记。
        val mimeType = format?.sampleMimeType ?: return "未知"
        val decoderInfo = try {
            MediaCodecUtil.getDecoderInfos(mimeType, false, false)
                .firstOrNull { it.name.equals(decoderName, ignoreCase = true) }
        } catch (_: Throwable) {
            null
        }
        return decoderInfo?.let {
            decoderTypeFromFlags(
                hardwareAccelerated = it.hardwareAccelerated,
                softwareOnly = it.softwareOnly,
            )
        } ?: "未知"
    }

    private fun actualCodec(mimeType: String?): String = when (mimeType) {
        MimeTypes.VIDEO_H264 -> "AVC / H.264"
        MimeTypes.VIDEO_H265 -> "HEVC / H.265"
        MimeTypes.VIDEO_AV1 -> "AV1"
        MimeTypes.VIDEO_DOLBY_VISION -> "Dolby Vision"
        MimeTypes.AUDIO_AAC -> "AAC"
        MimeTypes.AUDIO_AC3 -> "AC-3"
        MimeTypes.AUDIO_E_AC3, MimeTypes.AUDIO_E_AC3_JOC -> "E-AC-3"
        MimeTypes.AUDIO_TRUEHD -> "Dolby TrueHD"
        MimeTypes.AUDIO_FLAC -> "FLAC"
        MimeTypes.AUDIO_OPUS -> "Opus"
        MimeTypes.AUDIO_VORBIS -> "Vorbis"
        null -> ""
        else -> mimeType
    }

    private fun codecProfileLevel(format: Format): android.util.Pair<Int, Int>? = try {
        MediaCodecUtil.getCodecProfileAndLevel(format)
            ?.takeIf { it.first > 0 && it.second > 0 }
    } catch (_: Throwable) {
        null
    }

    private fun dolbyVisionProfileLevel(codecs: String?): Pair<String, String>? {
        val parts = codecs?.split('.') ?: return null
        if (parts.size < 3 || !parts[0].startsWith("dv", ignoreCase = true)) {
            return null
        }
        return parts[1] to parts[2]
    }

    private fun hdrType(format: Format): String {
        if (format.sampleMimeType == MimeTypes.VIDEO_DOLBY_VISION ||
            format.codecs?.startsWith("dv", ignoreCase = true) == true
        ) {
            return "Dolby Vision"
        }
        return when (format.colorInfo?.colorTransfer) {
            C.COLOR_TRANSFER_ST2084 -> if (format.colorInfo?.hdrStaticInfo != null) {
                "HDR10"
            } else {
                "PQ"
            }
            C.COLOR_TRANSFER_HLG -> "HLG"
            else -> ""
        }
    }

    private fun videoFormatData(format: Format): Map<String, Any?> {
        val profileLevel = codecProfileLevel(format)
        val dolbyLevel = dolbyVisionProfileLevel(format.codecs)
        val colorInfo = format.colorInfo
        return mapOf(
            "track" to "video",
            "codec" to actualCodec(format.sampleMimeType),
            "mimeType" to format.sampleMimeType,
            "codecs" to format.codecs,
            "profile" to profileLevel?.first,
            "level" to profileLevel?.second,
            "dolbyVisionProfile" to dolbyLevel?.first,
            "dolbyVisionLevel" to dolbyLevel?.second,
            "hdrType" to hdrType(format),
            "width" to format.width,
            "height" to format.height,
            "bitrate" to format.bitrate,
            "frameRate" to format.frameRate,
            "colorSpace" to colorInfo?.colorSpace,
            "colorRange" to colorInfo?.colorRange,
            "colorTransfer" to colorInfo?.colorTransfer,
            "colorBitDepth" to colorInfo?.lumaBitdepth,
        )
    }

    private fun audioFormatData(format: Format): Map<String, Any?> {
        val profileLevel = codecProfileLevel(format)
        return mapOf(
            "track" to "audio",
            "codec" to actualCodec(format.sampleMimeType),
            "mimeType" to format.sampleMimeType,
            "codecs" to format.codecs,
            "profile" to profileLevel?.first,
            "level" to profileLevel?.second,
            "bitrate" to format.bitrate,
            "sampleRate" to format.sampleRate,
            "channelCount" to format.channelCount,
            "channelMask" to format.channelMask,
            "pcmEncoding" to format.pcmEncoding,
        )
    }

    private fun trimDroppedFrameSamples(nowMs: Long = SystemClock.elapsedRealtime()) {
        val cutoff = nowMs - 30_000L
        while (droppedFrameSamples.peekFirst()?.timestampMs ?: Long.MAX_VALUE < cutoff) {
            droppedFrameSamples.pollFirst()
        }
    }

    private fun recentDroppedFrames(): Int {
        trimDroppedFrameSamples()
        return droppedFrameSamples.sumOf(DroppedFrameSample::count)
    }

    private fun isVideoRepresentationError(error: PlaybackException): Boolean {
        val eligibleCode = error.errorCode == PlaybackException.ERROR_CODE_DECODER_INIT_FAILED ||
            error.errorCode == PlaybackException.ERROR_CODE_DECODER_QUERY_FAILED ||
            error.errorCode == PlaybackException.ERROR_CODE_DECODING_FAILED ||
            error.errorCode == PlaybackException.ERROR_CODE_DECODING_FORMAT_EXCEEDS_CAPABILITIES ||
            error.errorCode == PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED ||
            error.errorCode == PlaybackException.ERROR_CODE_DECODING_RESOURCES_RECLAIMED ||
            error.errorCode == PlaybackException.ERROR_CODE_PARSING_CONTAINER_MALFORMED ||
            error.errorCode == PlaybackException.ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED
        if (!eligibleCode) return false

        val exoError = error as? ExoPlaybackException ?: return false
        if (exoError.type == ExoPlaybackException.TYPE_RENDERER) {
            val rendererType = runCatching {
                player.getRendererType(exoError.rendererIndex)
            }.getOrNull()
            return rendererType == C.TRACK_TYPE_VIDEO
        }
        if (exoError.rendererFormat?.sampleMimeType?.let(MimeTypes::isVideo) == true) {
            return true
        }
        // Source parsing errors do not carry a renderer. The active media item is
        // explicitly tagged with -video-, so audio parsing errors are not used to
        // switch the video Representation.
        return exoError.type == ExoPlaybackException.TYPE_SOURCE &&
            (lastLoadTrackType == C.TRACK_TYPE_VIDEO ||
                (lastLoadTrackType == C.TRACK_TYPE_UNKNOWN &&
                    source?.audio == null &&
                    player.currentMediaItem?.mediaId?.contains("-video-") == true))
    }

    private fun fallbackToNextRepresentation(error: PlaybackException): Boolean {
        val current = fallbackState.current ?: return false
        val next = fallbackState.markCurrentFailedAndGetNext()
        val reason = error.errorCodeName
        val message = error.message ?: lastVideoCodecError.ifEmpty { "Media3 视频解码失败" }
        val record = linkedMapOf<String, Any?>(
            "from" to current.id,
            "to" to next?.id.orEmpty(),
            "fromQualityCode" to current.qualityCode,
            "toQualityCode" to next?.qualityCode,
            "reason" to reason,
            "errorCode" to error.errorCode,
            "message" to message,
        )
        fallbackHistory += record
        val activeSource = source
        if (next == null || activeSource == null) {
            emitEvent(
                "representationFallbackExhausted",
                representationData(current) + mapOf(
                    "reason" to reason,
                    "errorCode" to error.errorCode,
                    "message" to message,
                    "fallbackHistory" to fallbackHistory.toList(),
                ),
            )
            return false
        }

        val plan = createRepresentationFallbackPlan(
            representation = next,
            positionMs = player.currentPosition,
            playWhenReady = player.playWhenReady,
            speed = player.playbackParameters.speed,
        )
        emitEvent(
            "representationFallback",
            representationData(plan.representation) + mapOf(
                "fromRepresentation" to current.id,
                "fromQualityCode" to current.qualityCode,
                "reason" to reason,
                "errorCode" to error.errorCode,
                "message" to message,
                "positionMs" to plan.positionMs,
                "fallbackHistory" to fallbackHistory.toList(),
            ),
        )
        lastVideoFormat = null
        lastVideoCodecError = ""
        resetMediaConsumptionStats()
        player.setMediaSource(
            buildMediaSource(activeSource, plan.representation),
            plan.positionMs,
        )
        player.playWhenReady = plan.playWhenReady
        bandwidthSamplingGate.setPlayWhenReady(plan.playWhenReady)
        player.prepare()
        player.setPlaybackSpeed(plan.speed)
        return true
    }

    private fun setHdrWindowMode(enabled: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val activity = context as? Activity ?: return
        try {
            activity.window.colorMode = if (enabled) {
                ActivityInfo.COLOR_MODE_HDR
            } else {
                ActivityInfo.COLOR_MODE_DEFAULT
            }
            hdrWindowModeEnabled = enabled
        } catch (_: IllegalArgumentException) {
            // 部分厂商窗口实现不接受颜色模式切换，SurfaceView 仍可独立输出 HDR。
        }
    }

    private fun applySubtitleStyle(
        view: PlayerView?,
        fontScale: Float = 1.0f,
        bottomPadding: Float = 24.0f,
        horizontalPadding: Float = 24.0f,
        backgroundOpacity: Float = 0.67f,
    ) {
        val subtitleView = view?.subtitleView ?: return
        val density = context.resources.displayMetrics.density
        subtitleView.setApplyEmbeddedStyles(false)
        subtitleView.setApplyEmbeddedFontSizes(false)
        subtitleView.setFixedTextSize(
            TypedValue.COMPLEX_UNIT_SP,
            16.0f * fontScale.coerceIn(0.5f, 2.5f),
        )
        subtitleView.setPadding(
            (horizontalPadding * density).toInt(),
            0,
            (horizontalPadding * density).toInt(),
            (bottomPadding * density).toInt(),
        )
        val background = Color.argb(
            (backgroundOpacity.coerceIn(0.0f, 1.0f) * 255.0f).toInt(),
            0,
            0,
            0,
        )
        subtitleView.setStyle(
            CaptionStyleCompat(
                Color.WHITE,
                background,
                Color.TRANSPARENT,
                CaptionStyleCompat.EDGE_TYPE_OUTLINE,
                Color.BLACK,
                null,
            ),
        )
        subtitleView.setViewType(SubtitleView.VIEW_TYPE_CANVAS)
    }

    private fun startTicker() {
        handler.removeCallbacks(progressRunnable)
        bandwidthSamplingGate.setPlayWhenReady(shouldSampleBandwidth())
        handler.post(progressRunnable)
    }

    private fun shouldSampleBandwidth(): Boolean =
        player.playWhenReady && player.playbackState != Player.STATE_ENDED

    private fun emitProgress() {
        bandwidthSamplingGate.setPlayWhenReady(shouldSampleBandwidth())
        val bufferedPositionMs = player.bufferedPosition
        val mediaBitrateEstimate = mediaBufferBitrateEstimator.sample(
            totalBytes = mediaBytesRead.get(),
            bufferedPositionMs = bufferedPositionMs,
        )
        if (bandwidthSamplingGate.enabled) {
            bandwidthMeter.getBitrateEstimate()
                .takeIf { it > 0L }
                ?.let { bandwidthEstimate = it }
        }
        val positionMs = player.currentPosition
        val durationMs = player.duration.takeIf { it != C.TIME_UNSET } ?: 0L
        emitEvent(
            "position",
            mapOf(
                "positionMs" to positionMs,
                "bufferedPositionMs" to bufferedPositionMs,
                "durationMs" to durationMs,
                "mediaBitrateEstimate" to mediaBitrateEstimate,
                "bandwidthEstimate" to bandwidthEstimate,
                "cdnUri" to currentCdnUri,
                "droppedFrames" to cumulativeDroppedFrames,
                "recentDroppedFrames" to recentDroppedFrames(),
                "playerState" to playerState(player.playbackState),
            ),
        )
        emitEvent("buffered", mapOf("positionMs" to bufferedPositionMs))
    }

    private fun emitEvent(type: String, data: Map<String, Any?> = emptyMap()) {
        emit(linkedMapOf<String, Any?>("sessionId" to sessionId, "type" to type).apply {
            putAll(data)
        })
    }

    private fun resetMediaConsumptionStats() {
        mediaBytesRead.set(0L)
        mediaBufferBitrateEstimator.reset()
    }

    private fun fail(
        code: String,
        message: String,
        extra: Map<String, Any?> = emptyMap(),
    ) {
        if (errorSent || released) return
        errorSent = true
        val current = fallbackState.current
        emitEvent(
            "error",
            mapOf("code" to code, "message" to message) +
                (current?.let(::representationData) ?: emptyMap()) +
                mapOf("fallbackHistory" to fallbackHistory.toList()) +
                extra,
        )
    }

    private fun playerState(state: Int): String = when (state) {
        Player.STATE_BUFFERING -> "缓冲中"
        Player.STATE_READY -> "已就绪"
        Player.STATE_ENDED -> "已结束"
        else -> "空闲"
    }

    private fun decoderCountersData(
        counters: DecoderCounters,
    ): Map<String, Any?> {
        counters.ensureUpdated()
        return mapOf(
            "renderedOutputBufferCount" to counters.renderedOutputBufferCount,
            "droppedBufferCount" to counters.droppedBufferCount,
            "skippedOutputBufferCount" to counters.skippedOutputBufferCount,
            "maxConsecutiveDroppedBufferCount" to counters.maxConsecutiveDroppedBufferCount,
            "droppedToKeyframeCount" to counters.droppedToKeyframeCount,
        )
    }

    override fun onPlaybackStateChanged(playbackState: Int) {
        emitEvent("state", mapOf("value" to playerState(playbackState)))
        when (playbackState) {
            Player.STATE_BUFFERING -> emitEvent("buffering", mapOf("value" to true))
            Player.STATE_READY -> {
                emitEvent(
                    "ready",
                    mapOf(
                        "durationMs" to (player.duration.takeIf { it != C.TIME_UNSET } ?: 0L),
                        "width" to player.videoSize.width,
                        "height" to player.videoSize.height,
                    ) + (fallbackState.current?.let(::representationData) ?: emptyMap()),
                )
                emitEvent("buffering", mapOf("value" to false))
            }
            Player.STATE_ENDED -> {
                bandwidthSamplingGate.setPlayWhenReady(false)
                handler.removeCallbacks(progressRunnable)
                emitProgress()
                emitEvent("completed")
            }
        }
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        emitEvent("playing", mapOf("value" to isPlaying))
        startTicker()
    }

    override fun onVideoSizeChanged(videoSize: androidx.media3.common.VideoSize) {
        emitEvent(
            "videoSize",
            mapOf("width" to videoSize.width, "height" to videoSize.height),
        )
    }

    override fun onRenderedFirstFrame() {
        emitEvent("firstFrame")
    }

    override fun onPlayerError(error: PlaybackException) {
        if (isVideoRepresentationError(error) && fallbackToNextRepresentation(error)) {
            return
        }
        fail(error.errorCodeName, error.message ?: "Media3 播放失败")
    }

    override fun onVideoInputFormatChanged(
        eventTime: AnalyticsListener.EventTime,
        format: Format,
        decoderReuseEvaluation: androidx.media3.exoplayer.DecoderReuseEvaluation?,
    ) {
        lastVideoFormat = format
        emitEvent("inputFormat", videoFormatData(format))
    }

    override fun onAudioInputFormatChanged(
        eventTime: AnalyticsListener.EventTime,
        format: Format,
        decoderReuseEvaluation: androidx.media3.exoplayer.DecoderReuseEvaluation?,
    ) {
        lastAudioFormat = format
        emitEvent("inputFormat", audioFormatData(format))
    }

    override fun onVideoDecoderInitialized(
        eventTime: AnalyticsListener.EventTime,
        decoderName: String,
        initializedTimestampMs: Long,
        initializationDurationMs: Long,
    ) {
        emitEvent(
            "decoder",
            mapOf(
                "track" to "video",
                "name" to decoderName,
                "decoderType" to decoderType(
                    decoderName,
                    lastVideoFormat ?: player.videoFormat,
                ),
            ),
        )
    }

    override fun onAudioDecoderInitialized(
        eventTime: AnalyticsListener.EventTime,
        decoderName: String,
        initializedTimestampMs: Long,
        initializationDurationMs: Long,
    ) {
        emitEvent(
            "decoder",
            mapOf(
                "track" to "audio",
                "name" to decoderName,
                "decoderType" to decoderType(
                    decoderName,
                    lastAudioFormat ?: player.audioFormat,
                ),
            ),
        )
    }

    override fun onDroppedVideoFrames(
        eventTime: AnalyticsListener.EventTime,
        droppedFrames: Int,
        elapsedMs: Long,
    ) {
        cumulativeDroppedFrames += droppedFrames.coerceAtLeast(0)
        if (droppedFrames > 0) {
            droppedFrameSamples.addLast(
                DroppedFrameSample(SystemClock.elapsedRealtime(), droppedFrames),
            )
        }
        val recent = recentDroppedFrames()
        emitEvent(
            "droppedFrames",
            mapOf(
                "count" to droppedFrames,
                "elapsedMs" to elapsedMs,
                "cumulative" to cumulativeDroppedFrames,
                "recent" to recent,
            ),
        )
    }

    override fun onLoadStarted(
        eventTime: AnalyticsListener.EventTime,
        loadEventInfo: LoadEventInfo,
        mediaLoadData: MediaLoadData,
    ) {
        lastLoadTrackType = mediaLoadData.trackType
        currentCdnUri = loadEventInfo.uri.toString()
        emitEvent(
            "loadStarted",
            mapOf(
                "uri" to currentCdnUri,
                "dataType" to mediaLoadData.dataType,
            ),
        )
    }

    override fun onLoadCompleted(
        eventTime: AnalyticsListener.EventTime,
        loadEventInfo: LoadEventInfo,
        mediaLoadData: MediaLoadData,
    ) {
        currentCdnUri = loadEventInfo.uri.toString()
        emitEvent(
            "loadCompleted",
            mapOf(
                "uri" to currentCdnUri,
                "dataType" to mediaLoadData.dataType,
                "bytesLoaded" to loadEventInfo.bytesLoaded,
            ),
        )
    }

    override fun onLoadError(
        eventTime: AnalyticsListener.EventTime,
        loadEventInfo: LoadEventInfo,
        mediaLoadData: MediaLoadData,
        error: IOException,
        wasCanceled: Boolean,
    ) {
        lastLoadTrackType = mediaLoadData.trackType
        currentCdnUri = loadEventInfo.uri.toString()
        emitEvent(
            "loadError",
            mapOf(
                "uri" to currentCdnUri,
                "dataType" to mediaLoadData.dataType,
                "trackType" to mediaLoadData.trackType,
                "message" to (error.message ?: "媒体加载失败"),
                "wasCanceled" to wasCanceled,
            ),
        )
    }

    override fun onBandwidthEstimate(
        eventTime: AnalyticsListener.EventTime,
        totalLoadTimeMs: Int,
        totalBytesLoaded: Long,
        bitrateEstimate: Long,
    ) {
        if (!bandwidthSamplingGate.enabled || !player.playWhenReady) return
        if (bitrateEstimate <= 0L) return
        bandwidthEstimate = bitrateEstimate
        emitEvent(
            "bandwidthEstimate",
            mapOf(
                "totalLoadTimeMs" to totalLoadTimeMs,
                "totalBytesLoaded" to totalBytesLoaded,
                "bitrateEstimate" to bitrateEstimate,
            ),
        )
    }

    override fun onVideoCodecError(
        eventTime: AnalyticsListener.EventTime,
        videoCodecError: Exception,
    ) {
        lastVideoCodecError = videoCodecError.message ?: "视频 Codec 错误"
        emitEvent(
            "videoCodecError",
            mapOf("message" to lastVideoCodecError),
        )
    }

    override fun onAudioCodecError(
        eventTime: AnalyticsListener.EventTime,
        audioCodecError: Exception,
    ) {
        lastAudioCodecError = audioCodecError.message ?: "音频 Codec 错误"
        emitEvent(
            "audioCodecError",
            mapOf("message" to lastAudioCodecError),
        )
    }

    override fun onVideoDisabled(
        eventTime: AnalyticsListener.EventTime,
        decoderCounters: DecoderCounters,
    ) {
        emitEvent(
            "decoderCounters",
            mapOf("track" to "video") + decoderCountersData(decoderCounters),
        )
    }

    override fun onAudioDisabled(
        eventTime: AnalyticsListener.EventTime,
        decoderCounters: DecoderCounters,
    ) {
        emitEvent(
            "decoderCounters",
            mapOf("track" to "audio") + decoderCountersData(decoderCounters),
        )
    }

    fun release() {
        if (released) return
        released = true
        bandwidthSamplingGate.setPlayWhenReady(false)
        handler.removeCallbacksAndMessages(null)
        if (hdrWindowModeEnabled) setHdrWindowMode(false)
        playerView?.let(::hideSurface)
        playerView = null
        player.removeListener(this)
        player.removeAnalyticsListener(this)
        player.release()
    }
}

/** 支持 B站主 URL、备用 URL 和断流续传的 DataSource。 */
@UnstableApi
internal class MultiUriDataSource(
    private val factory: DataSource.Factory,
    private val candidateMap: Map<String, List<Uri>>,
    private val onBytesRead: (Long) -> Unit = {},
) : DataSource {
    private val listeners = CopyOnWriteArrayList<androidx.media3.datasource.TransferListener>()
    private var current: DataSource? = null
    private var originalSpec: DataSpec? = null
    private var candidates: List<Uri> = emptyList()
    private var candidateIndex = 0
    private var bytesRead = 0L

    override fun addTransferListener(listener: androidx.media3.datasource.TransferListener) {
        listeners += listener
        current?.addTransferListener(listener)
    }

    override fun open(dataSpec: DataSpec): Long {
        originalSpec = dataSpec
        candidates = candidateMap[dataSpec.uri.toString()] ?: listOf(dataSpec.uri)
        candidateIndex = 0
        bytesRead = 0L
        return openCandidate(dataSpec, dataSpec.position, dataSpec.length)
    }

    private fun openCandidate(dataSpec: DataSpec, position: Long, length: Long): Long {
        var lastError: IOException? = null
        while (candidateIndex < candidates.size) {
            val uri = candidates[candidateIndex]
            val candidateSpec = dataSpec.buildUpon()
                .setUri(uri)
                .setPosition(position)
                .setLength(length)
                .build()
            val delegate = factory.createDataSource()
            listeners.forEach(delegate::addTransferListener)
            try {
                current = delegate
                return delegate.open(candidateSpec)
            } catch (error: IOException) {
                lastError = error
                try {
                    delegate.close()
                } catch (_: IOException) {
                    // 忽略失败候选 URL 的关闭异常，继续尝试下一个地址。
                }
                current = null
                candidateIndex++
            }
        }
        throw lastError ?: IOException("没有可用的媒体 URL")
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        while (true) {
            val delegate = current ?: throw IOException("DataSource 尚未打开")
            try {
                val count = delegate.read(buffer, offset, length)
                if (count > 0) {
                    bytesRead += count
                    onBytesRead(count.toLong())
                }
                return count
            } catch (error: IOException) {
                try {
                    delegate.close()
                } catch (_: IOException) {
                    // 读取失败后的关闭异常不应阻止备用 URL 接管。
                }
                current = null
                candidateIndex++
                if (candidateIndex >= candidates.size) throw error
                val spec = originalSpec ?: throw error
                val remaining = if (spec.length == C.LENGTH_UNSET.toLong()) {
                    C.LENGTH_UNSET.toLong()
                } else {
                    (spec.length - bytesRead).coerceAtLeast(0L)
                }
                openCandidate(
                    spec,
                    spec.position + bytesRead,
                    remaining,
                )
            }
        }
    }

    override fun getUri(): Uri? = current?.uri

    override fun getResponseHeaders(): Map<String, List<String>> =
        current?.responseHeaders ?: emptyMap()

    override fun close() {
        try {
            current?.close()
        } finally {
            current = null
            originalSpec = null
            candidates = emptyList()
        }
    }
}
