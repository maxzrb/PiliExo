package com.maxzrb.piliexo

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Test

/** 固定输入/参考输出：JNI 的空载荷 flush 必须清空上一段元数据状态。 */
class MpvVividFlushTest {
    @Test
    fun acceptsNullFlushPayload() {
        val pipeline = MpvVividPipeline()
        val samples = repoFile("test/fixtures/mpv_hdr/vivid-flush.txt").readLines(Charsets.UTF_8)
        val actual = buildString {
            for (line in samples) {
                val (id, pts, type, hex) = line.split(' ')
                val bytes = if (hex == "-") null else {
                    hex.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
                }
                pipeline.onMetadata(pts.toLong(), type.toInt(), bytes)
                append("$id=${pipeline.received},${pipeline.applied},${pipeline.unmatched}\n")
            }
        }
        assertEquals(repoFile("test/ref/fate/mpv-hdr-vivid-flush").readText(Charsets.UTF_8), actual)
    }

    private fun repoFile(path: String): File {
        var directory = File(System.getProperty("user.dir")!!)
        while (directory.parentFile != null && !File(directory, "pubspec.yaml").exists()) {
            directory = directory.parentFile!!
        }
        return File(directory, path)
    }
}
