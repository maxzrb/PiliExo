-dontwarn javax.annotation.Nullable
-dontwarn org.conscrypt.Conscrypt
-dontwarn org.conscrypt.OpenSSLProvider

# Media3 通过反射加载 FFmpeg 音频渲染器，保留其入口和 JNI 类。
-keep class androidx.media3.decoder.ffmpeg.** { *; }
