package com.maxzrb.piliexo

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.Display
import android.view.PixelCopy
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.widget.FrameLayout
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.ByteArrayOutputStream
import org.json.JSONObject
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** 所有 mpv 同步调用放到独立线程，避免 Surface 生命周期阻塞主线程。 */
internal object MpvSurfaceNative {
    init { System.loadLibrary("piliexo_mpv_surface") }
    external fun create(handle: Long, directOutput: Boolean): Long
    external fun option(pointer: Long, name: String, value: String)
    external fun metadata(pointer: Long, sink: MpvVividPipeline?, nativeDolby: Boolean)
    external fun attach(pointer: Long, surface: Surface, width: Int, height: Int)
    external fun resize(pointer: Long, width: Int, height: Int)
    external fun snapshot(pointer: Long): String
    external fun detach(pointer: Long)
    external fun release(pointer: Long)
}

class MpvHdrPlugin(private val activity: Activity, engine: FlutterEngine) {
    private val messenger = engine.dartExecutor.binaryMessenger
    private val methods = MethodChannel(messenger, "com.maxzrb.piliexo/mpv_hdr")
    private val events = EventChannel(messenger, "com.maxzrb.piliexo/mpv_hdr/events")
    private val main = Handler(Looper.getMainLooper())
    private val thread = HandlerThread("piliexo-mpv-surface").apply { start() }
    private val worker = Handler(thread.looper)
    private var sink: EventChannel.EventSink? = null
    private val sessions = mutableMapOf<String, Session>()

    init {
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) { sink = eventSink }
            override fun onCancel(arguments: Any?) { sink = null }
        })
        methods.setMethodCallHandler(::onMethod)
        engine.platformViewsController.registry.registerViewFactory(
            "piliexo/mpv_hdr_surface", object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
                override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
                    val id = (args as Map<*, *>)["sessionId"] as String
                    return OutputView(context, checkNotNull(sessions[id]))
                }
            },
        )
    }

    private fun onMethod(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("sessionId") ?: return result.error("session", "缺少会话", null)
        if (call.method == "create") {
            if (Build.VERSION.SDK_INT < 28) return result.error("unsupported", "mpv HDR 需要 Android 9 或更高版本", null)
            if (sessions.containsKey(id)) return result.error("session", "会话已存在", null)
            val handle = call.argument<Number>("handle")?.toLong()
                ?: return result.error("handle", "缺少播放实例", null)
            val session = Session(id)
            sessions[id] = session
            val options = (call.argument<Map<String, String>>("options") ?: emptyMap()).toMutableMap()
            @Suppress("DEPRECATION")
            val display = activity.windowManager.defaultDisplay
            val capabilities = display.hdrCapabilities
            if (capabilities == null || !capabilities.supportedHdrTypes.any {
                it == Display.HdrCapabilities.HDR_TYPE_HDR10 ||
                    it == Display.HdrCapabilities.HDR_TYPE_HDR10_PLUS ||
                    it == Display.HdrCapabilities.HDR_TYPE_HLG ||
                    it == Display.HdrCapabilities.HDR_TYPE_DOLBY_VISION
            }) {
                sessions.remove(id)
                return result.error("unsupported", "当前显示器没有报告 HDR 输出能力", null)
            }
            val hardware = call.argument<Boolean>("hardwareEnabled") == true
            val dv = Regex("^(?:dvh1|dvhe)\\.(\\d+)\\.(\\d+)", RegexOption.IGNORE_CASE)
                .find(call.argument<String>("codecs") ?: "")
            val profile = dv?.groupValues?.get(1)?.toIntOrNull()
            val level = dv?.groupValues?.get(2)?.toIntOrNull()
            session.nativeDolby = hardware && profile != null && level != null &&
                MpvDynamicHdrCapabilities.supportsDolby(display, profile, level)
            var direct = call.argument<Boolean>("directOutput") == true
            if (profile != null) {
                direct = session.nativeDolby || (hardware && profile != 5)
                options["hwdec"] = if (direct) "mediacodec" else "no"
                session.dynamicMode = when {
                    session.nativeDolby -> "dolby-system"
                    profile != 5 -> "dolby-hdr10"
                    else -> "dolby-software"
                }
            }
            if (call.argument<Number>("qualityCode")?.toInt() == 129) {
                if (!hardware || !MpvDynamicHdrCapabilities.hasHevc10BitDecoder()) {
                    sessions.remove(id)
                    return result.error("unsupported", "HDR Vivid 动态渲染需要 10 位 HEVC 硬解", null)
                }
                direct = true
                options["hwdec"] = "mediacodec"
                session.vivid = MpvVividPipeline()
                session.dynamicMode = "vivid-sdk"
                session.sourceWidth = call.argument<Number>("width")?.toInt() ?: 0
                session.sourceHeight = call.argument<Number>("height")?.toInt() ?: 0
            }
            worker.post {
                try {
                    Log.i("PiliMpvHdr", "创建原生 HDR 输出会话 $id")
                    session.pointer = MpvSurfaceNative.create(handle, direct)
                    options.forEach { (name, value) -> MpvSurfaceNative.option(session.pointer, name, value) }
                    MpvSurfaceNative.metadata(session.pointer, session.vivid, session.nativeDolby)
                    main.post { result.success(null) }
                } catch (error: Throwable) {
                    Log.e("PiliMpvHdr", "原生 HDR 输出初始化失败", error)
                    if (session.pointer != 0L) MpvSurfaceNative.release(session.pointer)
                    session.pointer = 0L
                    main.post {
                        sessions.remove(id)
                        result.error("native", error.message, null)
                    }
                }
            }
            return
        }
        val session = sessions[id] ?: return result.success(null)
        when (call.method) {
            "videoSize" -> {
                session.videoWidth = call.argument<Number>("width")?.toInt() ?: 0
                session.videoHeight = call.argument<Number>("height")?.toInt() ?: 0
                session.view?.layoutVideo()
                result.success(null)
            }
            "resizeMode" -> {
                session.mode = call.argument<String>("mode") ?: "fit"
                session.view?.layoutVideo()
                result.success(null)
            }
            "captureAmbientFrame" -> {
                val width = (call.argument<Number>("width")?.toInt() ?: 96)
                    .coerceIn(16, 256)
                val height = (call.argument<Number>("height")?.toInt() ?: 54)
                    .coerceIn(16, 256)
                session.captureAmbientFrame(
                    width,
                    height,
                    call.argument<String>("format") == "rgba8888",
                ) { result.success(it) }
            }
            "hide" -> {
                session.view?.hide()
                worker.post {
                    if (session.pointer != 0L) MpvSurfaceNative.detach(session.pointer)
                    main.post { result.success(null) }
                }
            }
            "release" -> {
                sessions.remove(id)
                session.released = true
                session.view?.hide()
                worker.removeCallbacks(session.poll)
                worker.post {
                    if (session.pointer != 0L) MpvSurfaceNative.release(session.pointer)
                    session.pointer = 0L
                    session.vivid?.release()
                    main.post { result.success(null) }
                }
            }
            else -> result.notImplemented()
        }
    }

    private inner class Session(val id: String) {
        var pointer = 0L
        @Volatile var released = false
        var failed = false
        @Volatile var view: OutputView? = null
        var videoWidth = 0
        var videoHeight = 0
        var mode = "fit"
        var polls = 0
        var lastSnapshot = ""
        var nativeDolby = false
        var dynamicMode = "static"
        var vivid: MpvVividPipeline? = null
        var sourceWidth = 0
        var sourceHeight = 0
        val poll = object : Runnable {
            override fun run() {
                if (released || failed || pointer == 0L) return
                try {
                    val raw = MpvSurfaceNative.snapshot(pointer)
                    val json = JSONObject(raw)
                    json.put("dynamicMode", dynamicMode)
                    vivid?.let {
                        it.error?.let { error -> throw IllegalStateException(error) }
                        json.put("vividMetadataReceived", it.received)
                        json.put("vividMetadataApplied", it.applied)
                        json.put("vividMetadataUnmatched", it.unmatched)
                        // 只在真正按 PTS 提交过动态载荷后显示动态处理已激活。
                        json.put("dynamicMetadataActive", it.applied > 0)
                    }
                    val snapshot = json.toString()
                    val error = json.optString("error")
                    if (error.isNotEmpty()) throw IllegalStateException(error)
                    if (json.optInt("videoWidth") > 0 && !json.optBoolean("configured") && ++polls > 24) {
                        throw IllegalStateException("mpv HDR 视频输出初始化超时")
                    }
                    if (snapshot != lastSnapshot) {
                        lastSnapshot = snapshot
                        val data = json.keys().asSequence().associateWith { json.get(it) }.toMutableMap()
                        data["sessionId"] = id
                        data["type"] = "output"
                        main.post { if (!released) sink?.success(data) }
                        Log.i("PiliMpvHdr", "output $snapshot")
                    }
                    worker.postDelayed(this, 500)
                } catch (error: Throwable) { fail(error) }
            }
        }

        fun captureAmbientFrame(
            width: Int,
            height: Int,
            rawPixels: Boolean,
            callback: (Any?) -> Unit,
        ) {
            view?.captureAmbientFrame(width, height, rawPixels, callback) ?: callback(null)
        }

        fun fail(error: Throwable) {
            if (released || failed) return
            failed = true
            Log.e("PiliMpvHdr", "HDR 输出失败", error)
            main.post {
                if (!released) sink?.success(mapOf("sessionId" to id, "type" to "error", "message" to error.message))
            }
        }
    }

    private inner class OutputView(context: Context, private val session: Session) : PlatformView, SurfaceHolder.Callback {
        val surface = SurfaceView(context).apply {
            setZOrderOnTop(false)
            holder.addCallback(this@OutputView)
        }
        private var ambientCaptureInFlight = false
        private val root = object : FrameLayout(context) {
            override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
                super.onSizeChanged(w, h, oldw, oldh)
                layoutVideo()
            }
        }.apply {
            setBackgroundColor(Color.BLACK)
            clipChildren = true
            addView(surface, FrameLayout.LayoutParams(-1, -1, Gravity.CENTER))
        }

        init { session.view = this }
        override fun getView(): View = root

        fun hide() {
            // 连黑色父容器一起隐藏，避免 Surface 消失后仍留下缩小的黑窗。
            root.alpha = 0f
            root.visibility = View.GONE
            surface.visibility = View.GONE
        }

        /**
         * 从 mpv 原生 SurfaceView 复制一张很小的当前帧，供顶部状态栏做环境背景。
         * 只读取画面，不改变 HDR 直出或 GPU 输出链路。
         */
        fun captureAmbientFrame(
            width: Int,
            height: Int,
            rawPixels: Boolean,
            callback: (Any?) -> Unit,
        ) {
            if (session.released || Build.VERSION.SDK_INT < Build.VERSION_CODES.N ||
                !surface.isAttachedToWindow || surface.width <= 0 || surface.height <= 0 ||
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
                    surface,
                    bitmap,
                    { copyResult ->
                        ambientCaptureInFlight = false
                        if (copyResult != PixelCopy.SUCCESS || session.released) {
                            bitmap.recycle()
                            callback(null)
                            return@request
                        }
                        if (rawPixels) {
                            val message = try {
                                val colors = IntArray(width * height)
                                bitmap.getPixels(colors, 0, width, 0, 0, width, height)
                                val pixels = ambientArgbToRgba(colors)
                                mapOf(
                                    "format" to "rgba8888",
                                    "width" to width,
                                    "height" to height,
                                    "rowBytes" to width * 4,
                                    "pixels" to pixels,
                                )
                            } catch (_: Throwable) {
                                null
                            } finally {
                                bitmap.recycle()
                            }
                            callback(message)
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
                    main,
                )
            } catch (_: Throwable) {
                ambientCaptureInFlight = false
                bitmap.recycle()
                callback(null)
            }
        }

        fun layoutVideo() {
            val width = root.width
            val height = root.height
            if (width <= 0 || height <= 0 || session.videoWidth <= 0 || session.videoHeight <= 0) return
            val ratio = session.videoWidth.toDouble() / session.videoHeight
            val scale = when (session.mode) {
                "cover" -> max(width / ratio, height.toDouble())
                "fitWidth" -> width / ratio
                "fitHeight" -> height.toDouble()
                else -> min(width / ratio, height.toDouble())
            }
            val targetWidth = if (session.mode == "fill") width else (scale * ratio).roundToInt()
            val targetHeight = if (session.mode == "fill") height else scale.roundToInt()
            val params = surface.layoutParams as FrameLayout.LayoutParams
            if (params.width != targetWidth || params.height != targetHeight) {
                surface.layoutParams = FrameLayout.LayoutParams(targetWidth, targetHeight, Gravity.CENTER)
            }
        }

        override fun surfaceCreated(holder: SurfaceHolder) {
            val width = holder.surfaceFrame.width().coerceAtLeast(1)
            val height = holder.surfaceFrame.height().coerceAtLeast(1)
            worker.post {
                if (session.released || session.view !== this || session.pointer == 0L) return@post
                try {
                    val input = session.vivid?.start(holder.surface, session.sourceWidth,
                        session.sourceHeight, width, height) ?: holder.surface
                    MpvSurfaceNative.attach(session.pointer, input, width, height)
                    session.polls = 0
                    worker.removeCallbacks(session.poll)
                    worker.post(session.poll)
                } catch (error: Throwable) { session.fail(error) }
            }
        }

        override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            worker.post {
                if (!session.released && session.view === this && session.pointer != 0L) {
                    MpvSurfaceNative.resize(session.pointer, width, height)
                    session.vivid?.resize(width, height)
                }
            }
        }

        override fun surfaceDestroyed(holder: SurfaceHolder) {
            worker.post {
                if (!session.released && session.view === this && session.pointer != 0L) {
                    worker.removeCallbacks(session.poll)
                    MpvSurfaceNative.detach(session.pointer)
                    session.vivid?.release()
                }
            }
        }

        override fun dispose() {
            hide()
            if (session.view === this) {
                session.view = null
                worker.post {
                    if (!session.released && session.view == null && session.pointer != 0L) {
                        worker.removeCallbacks(session.poll)
                        MpvSurfaceNative.detach(session.pointer)
                    }
                }
            }
            surface.holder.removeCallback(this)
        }
    }

    fun dispose() {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        sessions.values.forEach { session ->
            session.released = true
            worker.removeCallbacks(session.poll)
            worker.post {
                if (session.pointer != 0L) MpvSurfaceNative.release(session.pointer)
                session.pointer = 0L
                session.vivid?.release()
            }
        }
        sessions.clear()
        worker.post { thread.quitSafely() }
    }
}
