package com.maxzrb.piliexo

import android.content.Context
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.os.Build
import android.view.Display
import android.view.Surface
import androidx.annotation.Keep
import com.huawei.hms.videokit.hdrvivid.render.HdrVividRender
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.TreeMap

/** 按设备声明选择杜比解码器，不以厂商名或 HEVC Main10 冒充动态 HDR 能力。 */
internal object MpvDynamicHdrCapabilities {
    fun supportsDolby(display: Display, profile: Int, level: Int): Boolean {
        val hdrTypes = display.hdrCapabilities?.supportedHdrTypes ?: return false
        if (profile !in 1..9 || level !in 1..13 ||
            Display.HdrCapabilities.HDR_TYPE_DOLBY_VISION !in hdrTypes) return false
        return runCatching {
            MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.any { codec ->
                !codec.isEncoder && codec.supportedTypes.any { type ->
                    type.equals("video/dolby-vision", true) &&
                        codec.getCapabilitiesForType(type).profileLevels.any {
                            it.profile == dolbyProfileConstant(profile) &&
                                it.level >= (1 shl (level - 1))
                        }
                }
            }
        }.getOrDefault(false)
    }

    fun hasHevc10BitDecoder(): Boolean = runCatching {
        MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.any { codec ->
            !codec.isEncoder && codec.supportedTypes.any { type ->
                type.equals("video/hevc", true) && codec.getCapabilitiesForType(type).profileLevels.any {
                    it.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10 ||
                        it.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10 ||
                        (Build.VERSION.SDK_INT >= 29 &&
                            it.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10Plus)
                }
            }
        }
    }.getOrDefault(false)

    private fun dolbyProfileConstant(profile: Int): Int = when (profile) {
        0 -> 1
        1 -> 2
        4 -> 4
        5 -> 8
        7 -> 16
        8 -> 32
        else -> -1
    }
}

/** 使用帧时间戳匹配元数据；队列有界，seek 清空，旧会话不会向新会话投递。 */
@Keep
internal class MpvVividPipeline {
    private val metadata = TreeMap<Long, ByteArray>()
    private var mastering: ByteArray? = null
    private var light: ByteArray? = null
    private var renderer: HdrVividRender? = null
    private var input: Surface? = null
    @Volatile var received = 0L
        private set
    @Volatile var applied = 0L
        private set
    @Volatile var unmatched = 0L
        private set
    @Volatile var error: String? = null
        private set

    @Keep
    @Synchronized fun onMetadata(ptsUs: Long, type: Int, bytes: ByteArray) {
        when (type) {
            0 -> { metadata.clear(); mastering = null; light = null }
            137 -> mastering = bytes
            144 -> light = bytes
            4 -> {
                metadata[ptsUs] = bytes
                received++
                while (metadata.size > 128) metadata.pollFirstEntry()
            }
        }
    }

    fun start(output: Surface, width: Int, height: Int, outWidth: Int, outHeight: Int): Surface {
        check(width > 0 && height > 0) { "HDR Vivid 缺少源视频尺寸" }
        val render = HdrVividRender()
        renderer = render
        check(render.init()) { "当前设备无法初始化 HDR Vivid 动态渲染" }
        // 源传递函数在首帧前由原生诊断更新；Vivid 在线 PQ 轨道的初始值为 PQ。
        checkStatus(render.setTransFunc(HdrVividRender.TRANSFUNC_PQ))
        checkStatus(render.setInputVideoSize(width, height))
        render.setScreenHdr(true)
        checkStatus(render.setOutputSurfaceSize(outWidth, outHeight))
        val surface = checkNotNull(render.createInputSurface())
        input = surface
        checkStatus(render.configure(surface, { _, pts -> applyMetadata(pts) }, output, null))
        checkStatus(render.start())
        return surface
    }

    @Synchronized private fun applyMetadata(ptsUs: Long): Int {
        val render = renderer ?: return -1
        val bytes = metadata.remove(ptsUs)
        // 不能把邻帧数据套在当前帧上；帧重排、跳帧和 seek 必须按原始 PTS 匹配。
        metadata.headMap(ptsUs, false).clear()
        if (bytes == null) { unmatched++; return 0 }
        val m = mastering
        val c = light
        if (m != null && m.size == 24) {
            val buffer = ByteBuffer.wrap(m).order(ByteOrder.BIG_ENDIAN)
            fun u16() = buffer.short.toInt() and 65535
            val info = HdrVividRender.StaticMetaData().apply {
                gDisplayPrimariesX = u16(); gDisplayPrimariesY = u16()
                bDisplayPrimariesX = u16(); bDisplayPrimariesY = u16()
                rDisplayPrimariesX = u16(); rDisplayPrimariesY = u16()
                whitePointX = u16(); whitePointY = u16()
                maxDisplayMasteringLum = buffer.int
                minDisplayMasteringLum = buffer.int
                if (c != null && c.size == 4) {
                    val cll = ByteBuffer.wrap(c).order(ByteOrder.BIG_ENDIAN)
                    maxContentLightLevel = cll.short.toInt() and 65535
                    maxPicAverageLightLevel = cll.short.toInt() and 65535
                }
            }
            val result = render.setStaticMetaData(info)
            if (result != 0) { error = "HDR Vivid 静态元数据提交失败：$result"; return result }
        }
        val buffer = ByteBuffer.allocateDirect(bytes.size).order(ByteOrder.nativeOrder())
        buffer.put(bytes).rewind()
        val result = render.setDynamicMetaData(ptsUs, buffer)
        if (result == 0) applied++ else error = "HDR Vivid 动态元数据提交失败：$result"
        return result
    }

    fun resize(width: Int, height: Int) { renderer?.setOutputSurfaceSize(width, height) }

    fun release() {
        // stop 可能等待 SDK 回调，不在队列锁中调用。
        val render = renderer
        renderer = null
        render?.stop()
        render?.release()
        input?.release()
        input = null
        synchronized(this) { metadata.clear(); mastering = null; light = null }
    }

    private fun checkStatus(result: Int) { check(result == 0) { "HDR Vivid 渲染配置失败：$result" } }
}
