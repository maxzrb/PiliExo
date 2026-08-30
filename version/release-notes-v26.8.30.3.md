[新增] Media3 明确视频解码/容器错误时按同清晰度 codec、再按更低清晰度切换 Representation，并记录本次播放 session 的 fallback 历史。
[修复] Representation fallback 避免重复尝试，切换时尽量保持播放位置、播放状态、倍速和当前音轨；不再因设备能力预判提前屏蔽 DVH1 等轨道，也不因未报错黑屏主动降级。
[新增] 播放器洞察统一接入 Media3 AnalyticsListener、Format、DecoderCounters 和 mpv/media-kit 实际数据，补充视频/音频 Codec、Codec String、Profile/Level、Dolby Vision、HDR、分辨率/帧率、码率、解码器硬软解、声道、CDN、带宽、掉帧和 fallback 历史。
[新增] 播放设置增加“音频焦点接管”开关，默认开启；关闭时忽略 Audio Focus interruption，但耳机或蓝牙音频断开仍自动暂停。
[更改] Media3 不再独立接管 Audio Focus 或 becoming-noisy，Media3、mpv/media-kit 继续统一使用现有 PlPlayerController 和 AudioSessionHandler。
[测试] 补充 Representation 不循环、同清晰度优先、位置恢复、Telemetry 数据和音频焦点设置相关测试。
