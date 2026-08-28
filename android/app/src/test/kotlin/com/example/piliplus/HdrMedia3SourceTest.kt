package com.example.piliplus

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.TransferListener
import androidx.media3.datasource.okhttp.OkHttpDataSource
import java.io.IOException
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** HDR 参数和备用 URL 的 JVM 单测。 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE)
class HdrMedia3SourceTest {
    @Test
    fun parsesTracksAndHeaders() {
        val source = HdrMedia3Source.from(
            mapOf(
                "qualityCode" to 129,
                "headers" to mapOf("Referer" to "https://www.bilibili.com"),
                "video" to mapOf(
                    "urls" to listOf("https://video/main", "https://video/backup"),
                    "mimeType" to "video/mp4",
                    "codecs" to "hev1.2.4.L153",
                    "width" to 3840,
                    "height" to 2160,
                    "frameRate" to "60",
                ),
                "audio" to mapOf(
                    "urls" to listOf("https://audio/main"),
                    "mimeType" to "audio/mp4",
                ),
            ),
        )

        assertEquals(129, source.qualityCode)
        assertEquals(2, source.video.urls.size)
        assertEquals("hev1.2.4.L153", source.video.codecs)
        assertEquals("https://www.bilibili.com", source.headers["Referer"])
        assertEquals("https://audio/main", source.audio?.urls?.first()?.toString())
    }

    @Test
    fun opensTheNextUrlWhenThePrimaryUrlFails() {
        val source = MultiUriDataSource(
            FailingPrimaryFactory(),
            mapOf(
                "primary" to listOf(Uri.parse("primary"), Uri.parse("backup")),
            ),
        )
        val length = source.open(DataSpec.Builder().setUri("primary").build())
        val buffer = ByteArray(16)
        val read = source.read(buffer, 0, buffer.size)

        assertEquals(6L, length)
        assertEquals(6, read)
        assertEquals("backup", source.getUri()?.toString())
        assertEquals("native", String(buffer, 0, read))
        assertTrue(source.read(buffer, 0, buffer.size) == C.RESULT_END_OF_INPUT)
        source.close()
    }

    @Test
    fun retriesHttp403WithTheBackupUrl() {
        val server = MockWebServer()
        server.enqueue(MockResponse.Builder().code(403).build())
        server.enqueue(MockResponse.Builder().body("native").build())
        server.start()
        try {
            val primary = Uri.parse(server.url("/primary").toString())
            val backup = Uri.parse(server.url("/backup").toString())
            val source = MultiUriDataSource(
                OkHttpDataSource.Factory(OkHttpClient.Builder().build()),
                mapOf(primary.toString() to listOf(primary, backup)),
            )

            val length = source.open(DataSpec.Builder().setUri(primary).build())
            val buffer = ByteArray(16)
            val read = source.read(buffer, 0, buffer.size)

            assertEquals(6L, length)
            assertEquals("native", String(buffer, 0, read))
            assertEquals(backup, source.getUri())
            source.close()
        } finally {
            server.close()
        }
    }

    @Test
    fun keepsTheRangeHeaderWhenThePrimaryReturns5xx() {
        val server = MockWebServer()
        server.enqueue(MockResponse.Builder().code(502).build())
        server.enqueue(MockResponse.Builder().body("native").build())
        server.start()
        try {
            val primary = Uri.parse(server.url("/primary").toString())
            val backup = Uri.parse(server.url("/backup").toString())
            val source = MultiUriDataSource(
                OkHttpDataSource.Factory(OkHttpClient.Builder().build()),
                mapOf(primary.toString() to listOf(primary, backup)),
            )

            val length = source.open(
                DataSpec.Builder()
                    .setUri(primary)
                    .setPosition(2)
                    .setLength(3)
                    .build(),
            )
            val buffer = ByteArray(8)
            val read = source.read(buffer, 0, buffer.size)

            assertEquals(3L, length)
            assertEquals(3, read)
            assertEquals("tiv", String(buffer, 0, read))
            assertEquals("bytes=2-4", server.takeRequest().headers["Range"])
            assertEquals("bytes=2-4", server.takeRequest().headers["Range"])
            source.close()
        } finally {
            server.close()
        }
    }

    @Test
    fun resumesFromTheLastReadPositionAfterAConnectionFailure() {
        val factory = InterruptingFactory()
        val source = MultiUriDataSource(
            factory,
            mapOf(
                "primary" to listOf(Uri.parse("primary"), Uri.parse("backup")),
            ),
        )
        source.open(DataSpec.Builder().setUri("primary").build())
        val buffer = ByteArray(6)

        assertEquals(3, source.read(buffer, 0, 6))
        assertEquals(3, source.read(buffer, 3, 3))
        assertEquals("native", String(buffer))
        assertEquals(3, factory.backupPosition)
        assertEquals(Uri.parse("backup"), source.getUri())
        source.close()
    }

    private class FailingPrimaryFactory : DataSource.Factory {
        override fun createDataSource(): DataSource = FakeDataSource()
    }

    private class InterruptingFactory : DataSource.Factory {
        var backupPosition = -1

        override fun createDataSource(): DataSource = InterruptingDataSource {
            backupPosition = it
        }
    }

    private class InterruptingDataSource(
        private val onBackupOpen: (Int) -> Unit,
    ) : DataSource {
        private var uri: Uri? = null
        private var bytes = ByteArray(0)
        private var position = 0
        private var primaryRead = false

        override fun addTransferListener(transferListener: TransferListener) = Unit

        override fun open(dataSpec: DataSpec): Long {
            uri = dataSpec.uri
            bytes = "native".toByteArray()
            position = dataSpec.position.toInt()
            primaryRead = false
            if (dataSpec.uri.toString() == "backup") onBackupOpen(position)
            return (bytes.size - position).toLong()
        }

        override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
            if (uri?.toString() == "primary") {
                if (primaryRead) throw IOException("模拟断流")
                primaryRead = true
                val count = minOf(length, 3)
                bytes.copyInto(buffer, offset, 0, count)
                position = count
                return count
            }
            if (position >= bytes.size) return C.RESULT_END_OF_INPUT
            val count = minOf(length, bytes.size - position)
            bytes.copyInto(buffer, offset, position, position + count)
            position += count
            return count
        }

        override fun getUri(): Uri? = uri

        override fun close() {
            uri = null
        }
    }

    private class FakeDataSource : DataSource {
        private var uri: Uri? = null
        private var bytes = ByteArray(0)
        private var position = 0

        override fun addTransferListener(transferListener: TransferListener) = Unit

        override fun open(dataSpec: DataSpec): Long {
            if (dataSpec.uri.toString() == "primary") {
                throw IOException("HTTP 403")
            }
            uri = dataSpec.uri
            bytes = "native".toByteArray()
            position = dataSpec.position.toInt()
            return (bytes.size - position).toLong()
        }

        override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
            if (position >= bytes.size) return C.RESULT_END_OF_INPUT
            val count = minOf(length, bytes.size - position)
            bytes.copyInto(buffer, offset, position, position + count)
            position += count
            return count
        }

        override fun getUri(): Uri? = uri

        override fun close() {
            uri = null
        }
    }
}
