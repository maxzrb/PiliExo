# Media3 FFmpeg 音频扩展

`media3-decoder-ffmpeg-1.11.0-ac3-eac3-truehd.aar` 基于 AndroidX Media 1.11.0 的官方 `decoder_ffmpeg` 模块构建，从 [mpv 的源码清单](../../../patches/mpv/sources.json) 读取同一 FFmpeg 提交，当前为 `9.1.git`（`bf11bea4dcb4578b53906d1f5290f5b6bcae2dc2`），仅启用以下音频解码器：

- AC-3（`ac3`）
- E-AC-3 / E-AC-3-JOC 核心（`eac3`）
- Dolby TrueHD（`truehd`）

AAR 只包含 `arm64-v8a` 和 `armeabi-v7a` 的 `libffmpegJNI.so`。播放器仍优先使用设备硬件解码器；只有硬件不支持对应格式时，Media3 才会选择 FFmpeg 软件解码器。

E-AC-3-JOC 在软件回退路径中解码为 PCM 音频，目标是避免不支持 Dolby 音频的设备完全无声；支持 Dolby 直通的设备仍由硬件路径负责保留原生输出能力。

来源与许可：

- AndroidX Media：<https://github.com/androidx/media/tree/1.11.0/libraries/decoder_ffmpeg>，Apache License 2.0。
- FFmpeg：<https://github.com/FFmpeg/FFmpeg/tree/bf11bea4dcb4578b53906d1f5290f5b6bcae2dc2>，按本构建配置使用 LGPL 许可组件。

## 与 mpv 同步构建

在项目根目录运行：

```powershell
python tools/mpv-0.42.0-upgrade/build_media3_ffmpeg.py
```

脚本校验共用的 FFmpeg 源码归档和 Media3 JNI 源码，在 `tmp/` 生成双 ABI AAR。用输出的 AAR 替换此目录下的同名文件，再构建候选包。验收包含三种音频格式的 PCM 解码与跳转重置，以及 Media3 强制走软件音频解码时的 HDR 分轨前后跳转。
