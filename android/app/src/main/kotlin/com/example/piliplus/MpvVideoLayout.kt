package com.maxzrb.piliexo

import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

internal enum class MpvResizeMode(
    val wireName: String,
    private val fixedRatio: Double? = null,
) {
    FIT("fit"),
    FILL("fill"),
    COVER("cover"),
    FIT_WIDTH("fitWidth"),
    FIT_HEIGHT("fitHeight"),
    RATIO_4X3("4:3", 4.0 / 3),
    RATIO_16X9("16:9", 16.0 / 9);

    // 固定比例由 Surface 尺寸决定，GPU 输出应填满该尺寸。
    val keepAspect: Boolean get() = this != FILL && fixedRatio == null

    fun surfaceSize(width: Int, height: Int, videoWidth: Int, videoHeight: Int): Pair<Int, Int>? {
        if (width <= 0 || height <= 0) return null
        if (this == FILL) return width to height
        val ratio = fixedRatio ?: if (videoWidth > 0 && videoHeight > 0) {
            videoWidth.toDouble() / videoHeight
        } else {
            return null
        }
        val targetHeight = when (this) {
            COVER -> max(width / ratio, height.toDouble())
            FIT_WIDTH -> width / ratio
            FIT_HEIGHT -> height.toDouble()
            else -> min(width / ratio, height.toDouble())
        }
        return (targetHeight * ratio).roundToInt().coerceAtLeast(1) to
            targetHeight.roundToInt().coerceAtLeast(1)
    }

    companion object {
        fun fromWire(name: String?): MpvResizeMode =
            entries.firstOrNull { it.wireName == name } ?: FIT
    }
}
