# Media3 FFmpeg 音频扩展

`media3-decoder-ffmpeg-1.11.0-ac3-eac3-truehd.aar` 基于 AndroidX Media 1.11.0 的官方 `decoder_ffmpeg` 模块构建，使用 FFmpeg 6.0，仅启用以下音频解码器：

- AC-3（`ac3`）
- E-AC-3 / E-AC-3-JOC 核心（`eac3`）
- Dolby TrueHD（`truehd`）

AAR 只包含 `arm64-v8a` 和 `armeabi-v7a` 的 `libffmpegJNI.so`。播放器仍优先使用设备硬件解码器；只有硬件不支持对应格式时，Media3 才会选择 FFmpeg 软件解码器。

E-AC-3-JOC 在软件回退路径中解码为 PCM 音频，目标是避免不支持 Dolby 音频的设备完全无声；支持 Dolby 直通的设备仍由硬件路径负责保留原生输出能力。

来源与许可：

- AndroidX Media：<https://github.com/androidx/media/tree/1.11.0/libraries/decoder_ffmpeg>，Apache License 2.0。
- FFmpeg 6.0：<https://ffmpeg.org/download.html>，按本构建配置使用 LGPL 许可组件。
