package com.maxzrb.piliexo

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/** 为 Android 更新器提供 Aria2-next 分片下载和 APK 安装入口。 */
class AndroidUpdatePlugin(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "com.maxzrb.piliexo/update"
        private const val ARIA2_ASSET = "aria2-next/arm64-v8a/aria2-next"
        private const val ARIA2_BINARY_SIZE = 13_121_080L
        private const val UPDATE_DIRECTORY = "update"
        private const val APK_MIME_TYPE = "application/vnd.android.package-archive"
        private const val FILE_PROVIDER_SUFFIX = ".fileprovider"
        private const val MAX_LOG_LENGTH = 4_000
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()

    @Volatile
    private var aria2Process: Process? = null

    fun register() {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "downloadAndInstall" -> downloadAndInstall(call, result)
            "prepareUpdateFile" -> {
                try {
                    val fileName = call.argument<String>("fileName") ?: error("缺少 fileName")
                    result.success(prepareUpdateFile(fileName).absolutePath)
                } catch (error: Exception) {
                    result.error("update_file_error", error.message, null)
                }
            }

            "installApk" -> {
                try {
                    val path = call.argument<String>("path") ?: error("缺少 path")
                    val expectedSha256 = call.argument<String>("expectedSha256")
                    installApk(File(path), expectedSha256)
                    result.success(true)
                } catch (error: Exception) {
                    result.error("install_failed", error.message, null)
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun downloadAndInstall(call: MethodCall, result: MethodChannel.Result) {
        val urls = (call.argument<List<*>>("urls") ?: emptyList<Any?>())
            .filterIsInstance<String>()
            .map(String::trim)
            .filter(String::isNotEmpty)
            .distinct()
        val fileName = call.argument<String>("fileName")
        val expectedSha256 = call.argument<String>("expectedSha256")

        if (urls.isEmpty() || fileName.isNullOrBlank()) {
            result.error("update_arguments", "更新下载参数不完整", null)
            return
        }

        executor.execute {
            try {
                urls.forEach(::validateDownloadUrl)
                val executable = ensureAria2Executable()
                val outputFile = prepareUpdateFile(fileName)
                val command = buildAria2Command(executable, outputFile, urls)
                val process = ProcessBuilder(command)
                    .redirectErrorStream(true)
                    .start()
                aria2Process = process

                val log = StringBuilder()
                process.inputStream.bufferedReader().useLines { lines ->
                    lines.forEach { line ->
                        if (log.length < MAX_LOG_LENGTH) {
                            log.appendLine(line.take(MAX_LOG_LENGTH - log.length))
                        }
                    }
                }
                val exitCode = process.waitFor()
                aria2Process = null

                if (exitCode != 0 || !outputFile.isFile || outputFile.length() == 0L) {
                    throw UpdateFailure(
                        "download_failed",
                        "Aria2-next 下载失败${log.takeLast(300)}",
                    )
                }

                verifySha256(outputFile, expectedSha256)
                mainHandler.post {
                    try {
                        installApk(outputFile, expectedSha256)
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("install_failed", error.message, null)
                    }
                }
            } catch (error: UpdateFailure) {
                aria2Process = null
                postError(result, error.code, error.message)
            } catch (error: Exception) {
                aria2Process = null
                postError(result, "download_failed", error.message)
            }
        }
    }

    private fun buildAria2Command(
        executable: File,
        outputFile: File,
        urls: List<String>,
    ): List<String> {
        val outputDirectory = outputFile.parentFile ?: error("更新文件目录无效")
        return buildList {
            add(executable.absolutePath)
            add("--no-conf=true")
            add("--dir=${outputDirectory.absolutePath}")
            add("--out=${outputFile.name}")
            add("--split=32")
            add("--max-connection-per-server=32")
            add("--min-split-size=1M")
            add("--continue=true")
            add("--allow-overwrite=true")
            add("--auto-file-renaming=false")
            add("--file-allocation=none")
            add("--check-integrity=true")
            add("--max-tries=5")
            add("--retry-wait=2")
            add("--connect-timeout=15")
            add("--timeout=30")
            add("--console-log-level=warn")
            add("--summary-interval=0")
            add("--download-result=hide")
            addAll(urls)
        }
    }

    private fun ensureAria2Executable(): File {
        if (!Build.SUPPORTED_64_BIT_ABIS.any { it == "arm64-v8a" }) {
            throw UpdateFailure("aria2_unavailable", "当前设备没有 Aria2-next ARM64 支持")
        }

        val executable = File(File(context.codeCacheDir, "aria2-next"), "aria2-next")
        executable.parentFile?.mkdirs()
        if (!executable.isFile || executable.length() != ARIA2_BINARY_SIZE) {
            context.assets.open(ARIA2_ASSET).use { input ->
                FileOutputStream(executable).use { output ->
                    input.copyTo(output)
                }
            }
        }
        executable.setReadable(true, false)
        executable.setExecutable(true, false)
        if (!executable.canExecute()) {
            throw UpdateFailure("aria2_unavailable", "无法启动 Aria2-next")
        }
        return executable
    }

    private fun prepareUpdateFile(fileName: String): File {
        val safeName = fileName
            .substringAfterLast('/')
            .substringAfterLast('\\')
            .replace(Regex("[^A-Za-z0-9._-]"), "_")
        if (safeName.isBlank() || !safeName.endsWith(".apk", ignoreCase = true)) {
            throw IllegalArgumentException("更新文件名无效")
        }

        val directory = File(context.cacheDir, UPDATE_DIRECTORY)
        if (!directory.exists() && !directory.mkdirs()) {
            throw IllegalStateException("无法创建更新目录")
        }
        val canonicalDirectory = directory.canonicalFile
        val file = File(canonicalDirectory, safeName).canonicalFile
        if (file.parentFile != canonicalDirectory) {
            throw IllegalArgumentException("更新文件路径无效")
        }
        return file
    }

    private fun validateDownloadUrl(rawUrl: String) {
        val uri = Uri.parse(rawUrl)
        val host = uri.host?.lowercase()
        val allowedHost = host == "github.com" ||
            host?.endsWith(".github.com") == true ||
            host == "modelscope.cn" ||
            host?.endsWith(".modelscope.cn") == true
        if (uri.scheme != "https" || !allowedHost) {
            throw UpdateFailure("update_url_rejected", "更新地址不是受信任的 HTTPS 地址")
        }
    }

    private fun verifySha256(file: File, expected: String?) {
        val normalizedExpected = expected
            ?.trim()
            ?.removePrefix("sha256:")
            ?.lowercase()
            ?.takeIf { it.matches(Regex("[0-9a-f]{64}")) }
            ?: return
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val count = input.read(buffer)
                if (count <= 0) break
                digest.update(buffer, 0, count)
            }
        }
        val actual = digest.digest().joinToString("") { byte -> "%02x".format(byte) }
        if (actual != normalizedExpected) {
            file.delete()
            File(file.parentFile, "${file.name}.aria2").delete()
            throw UpdateFailure("checksum_mismatch", "更新文件校验失败")
        }
    }

    private fun installApk(file: File, expectedSha256: String? = null) {
        val updateDirectory = File(context.cacheDir, UPDATE_DIRECTORY).canonicalFile
        val canonicalFile = file.canonicalFile
        if (canonicalFile.parentFile != updateDirectory || !canonicalFile.isFile) {
            throw IllegalArgumentException("不允许安装应用私有更新目录之外的文件")
        }
        verifySha256(canonicalFile, expectedSha256)
        val uri = FileProvider.getUriForFile(
            context,
            context.packageName + FILE_PROVIDER_SUFFIX,
            canonicalFile,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, APK_MIME_TYPE)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }
        context.startActivity(intent)
    }

    private fun postError(result: MethodChannel.Result, code: String, message: String?) {
        mainHandler.post {
            result.error(code, message ?: "更新下载失败", null)
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        aria2Process?.destroy()
        aria2Process = null
        executor.shutdownNow()
    }

    private class UpdateFailure(
        val code: String,
        override val message: String,
    ) : Exception(message)
}
