-dontwarn javax.annotation.Nullable
-dontwarn org.conscrypt.Conscrypt
-dontwarn org.conscrypt.OpenSSLProvider

# Media3 通过反射加载 FFmpeg 音频渲染器，保留其入口和 JNI 类。
-keep class androidx.media3.decoder.ffmpeg.** { *; }

# 原生视频桥接由 JNI 按类名和方法名调用。
-keep class com.maxzrb.piliexo.MpvSurfaceNative { *; }
-keep class com.huawei.hms.videokit.hdrvivid.** { *; }
-keep class com.maxzrb.piliexo.MpvVividPipeline { *; }
