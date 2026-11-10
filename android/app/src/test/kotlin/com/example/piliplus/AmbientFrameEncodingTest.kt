package com.maxzrb.piliexo

import java.io.File
import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Test

/** 固定输入/参考输出：PixelCopy 的 ARGB 颜色必须稳定编码为 RGBA8888。 */
class AmbientFrameEncodingTest {
    @Test
    fun encodesArgbColorsAsRgbaBytes() {
        val fixtures = repoFile("test/fixtures/ambient_frame/argb-colors.json")
        val samples = JSONArray(fixtures.readText(Charsets.UTF_8))
        val actual = buildString {
            for (index in 0 until samples.length()) {
                val sample = samples.getJSONObject(index)
                val color = sample.getString("argb").removePrefix("0x").toLong(16).toInt()
                val bytes = ambientArgbToRgba(intArrayOf(color))
                append(sample.getString("id"))
                append(' ')
                bytes.forEach { append("%02X".format(it.toInt() and 255)) }
                append('\n')
            }
        }
        assertEquals(
            repoFile("test/ref/fate/ambient-frame-rgba").readText(Charsets.UTF_8),
            actual,
        )
    }

    private fun repoFile(path: String): File {
        var directory = File(System.getProperty("user.dir")!!)
        while (directory.parentFile != null && !File(directory, "pubspec.yaml").exists()) {
            directory = directory.parentFile!!
        }
        return File(directory, path)
    }
}
