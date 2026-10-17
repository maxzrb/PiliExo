run `dart run tool/jnigen.dart`

## 长按倍速实验

实验构建通过 `--dart-define=PILI_PLAYBACK_DIAGNOSTICS=true` 开启诊断；
基线包使用 `--dart-define=PILI_MPV_OPERATING_RATE=0`，对照包使用 `180`。
两个构建开关独立，功耗测试可关闭诊断并显式保留 `PILI_MPV_OPERATING_RATE`。
普通构建默认关闭诊断和原生日志；运行速率开关默认 `-1`，使用素材帧率乘以
基础倍速/长按倍速较大值规划需求，例如30fps×3为90、60fps×3为180。
`0` 关闭覆盖用于回归对照，正数强制指定运行速率。仅作用于 Android mpv 硬解点播，
未知帧率、直播、纯音频和软解保留原策略。参数写入本次 Media 的文件局部选项，
在解码初始化之前生效；不能在每次长按时重新创建播放器。
此策略为每段视频预留已知最大需求，尚未实现运行中按手势降低硬件运行速率。
`--dart-define=PILI_MPV_NATIVE_LOGS=true` 仅用于精确库排查，日常和功耗复测关闭。

洞察在 HUD 完全隐藏时继续处理快照和新掉帧事件，只跳过不可见界面重建。
Android mpv 通过独立客户端订阅输出/解码掉帧及缓存窗口属性，复用播放中的1Hz刷新，
不消费 media-kit 事件队列，也不在界面 getter 中同步查询。暂停停止采样，销毁前释放客户端；
属性不可用时显示“暂不可用”。这些计数是 mpv 可见的丢帧，并非屏幕实际呈现帧或厂商内部全部丢帧。

同一源码分别构建两个包并保存，核对包名、版本和签名后安装。
先备份手机原安装包，保留应用数据，完成实验后恢复原包。

```powershell
$env:PYTHONIOENCODING = 'utf-8'
python tool/playback_experiment.py --output tools/diagnostics/long-press-20261015/phase1/baseline
python tool/playback_experiment.py --output tools/diagnostics/long-press-20261015/phase1/operating-rate-180
```

每次执行需先安装对应包。脚本使用 ADB 冷启动固定视频，从60秒开始，
依次正常播放8秒、长按10秒、松手恢复20秒，重复三轮。
默认坐标 `(800, 400)` 对应本次 1080×2340 竖屏设备的播放器内部，
更换设备或布局后必须先查看屏幕，再通过 `--x`、`--y` 指定实际坐标。
脚本会停止并重启应用，日志和统计保留在指定目录，结束时停止实验应用。
目录中的每轮必须使用新路径，避免覆盖既有实验结果。

统计中的 Codec Rendered 是送显计数；Surface 合成帧和源视频帧率均不能
替代实际视频呈现帧率。2Hz PTS采样可识别持续追帧，不能证明150ms以内的
切换延迟。判断参数效果还需要核对日志中实际收到的 operating-rate，
实际播放速度、音画偏差、缓存情况及相同素材的多轮一致性。

每轮另存 `context-before.json` 与 `context-after.json`，记录电池充电状态、温度与系统热状态。
上下文用于识别条件差异；USB充电期间的电池变化不能作为整机耗电。

多设备连接时先设置 `$env:ANDROID_SERIAL = '目标设备序列号'`，脚本及其logcat继承同一目标。
接入已打开的播放页可使用 `--attach --rounds 1 --start-seconds 0`；该模式不冷启动，
必须事先核对视频、播放位置和状态。不同起点的补测单列，不混入固定起点主表。
当前布局若原长按点被叠层影响，可重新查看后指定坐标，本机补测使用 `(800, 450)`。
脚本要求记录gesture_start/gesture_end，且长按稳态速度等于 `--expected-rate`（默认3）。
未通过时在summary写入valid=false和validationErrors，保存原始日志并停止后续轮次。


## 正常播放开销归因

研究包使用 `--dart-define=PILI_POWER_PROBE=true`，仅在BV1a2pr6aEC1上自动运行。
不要与 `PILI_PLAYBACK_DIAGNOSTICS` 或原生日志同时开启。默认构建不开启实验。
它会重复60秒附近片段，预热到实际68秒后测20秒，环境帧开/关按ABBA顺序运行；
mpv另做display-resample/audio的ABBA，结束恢复同步属性与环境帧，不改持久设置。
`--dart-define=PILI_POWER_MEDIA3_SDR=true` 额外将该视频的同一主轨道送入现有Media3
SurfaceView后端，只用于对照（不提供编码/画质备选，避免隐式切换素材）。
这不是普通SDR后端的正式设置或完整兼容验收。

```powershell
python tool/playback_power_probe.py --serial AEFUUT1715006716 --output C:/Temp/pili-power-mpv --aligned-window
python tool/playback_power_probe.py --serial AEFUUT1715006716 --output C:/Temp/pili-power-media3 --expected-phases 4 --aligned-window
```

脚本只接入正在/即将从界面打开的播放页，不负责冷启动或导航。先在新目录启动采集，
随后进入指定视频，研究包自动跳转；采集中不要手动切速/拖动/切页。CPU为单核等效，
100%表示一个核；读取各线程stat不会得到GPU功率，也不能把CPU百分比换算成W。
临时输出写入C盘等非同步目录，结束再归档。最后必须恢复已验证的日常候选，不能留下会自动跳转的研究包。

初次mpv pilot使用固定8秒墙钟预热，首窗约64.8秒开始，后续窗约67.8秒；
该轮保存为pilot，首窗位置差必须披露，不能称为严格同位置对照。


视频计数必须按**实际视频解码器名称和PID**筛选。本机默认`--video-decoder c2.qti.hevc.decoder`；
更换AVC等素材需显式传入实际名称。Media3同进程还有AAC音频解码器，其Rendered=0不能混入
视频均值。旧`media3-rejected-30fps`是采集器混入音频造成的错误记录，已由`media3-corrected`取代。

## 界面开销归因

`ui_power_probe.py`接入日常Release包，保存线程CPU、显示/锁屏/前台状态和前后截图，
可用于推荐页/我的页/暂停页静置与离开播放页后的观察。静置和滚动必须人工核对截图所处页面；
包名相同不能证明仍是推荐页。静置前后屏幕ON、已解锁且应用可见前台，否则valid=false。
默认30秒；`--scroll`为7次往返，坐标只适用已核对的1080×2340本机布局。
SurfaceFlinger数据为有限环形缓冲观测下界，不是完整FPS统计；没有数据不能声称零绘制。

```powershell
python tool/ui_power_probe.py --serial AEFUUT1715006716 --output C:/Temp/pili-ui-idle --seconds 30
```

手势可能因顶底栏自动隐藏造成列表位置漂移，不能仅凭相同ADB坐标当作严格同位置实验。
严格对照使用`--dart-define=PILI_UI_POWER_PROBE=true`的独立研究构建；不要同时开播放侧研究。
该开关默认false，普通构建不注册研究回调。研究从首页推荐列表开始，12秒等待加载，预热两次，
静置/滚动分别做磨砂开/关ABBA，各窗20秒。滚动精确100↔550逻辑像素10次往返，
相同缓存卡片、同起止位置；记录FrameTiming的build/raster P95及超8.333ms数量，
不限制源帧率或系统刷新率。它是程序化固定路径基准，不替代真实触摸/复杂内容的完整流畅度验收。

```powershell
python tool/ui_power_experiment.py --serial AEFUUT1715006716 --output C:/Temp/pili-ui-abba --launch
python -m unittest discover -s tool -p test_*power*.py
```

采集器单独统计各窗中间CPU样本，校验时长、位置、往返次数和最后前台/解锁状态，
研究包切页/切后台自动取消。磨砂覆盖只在内存，完成/取消恢复初始设置与列表位置。
实验前确认自动息屏足够长；如临时修改必须记录原值并在结束后恢复。本机原值120000ms。
研究后必须重新安装已验证的日常候选，并停止应用，避免自动研究影响用户使用。


## 保留效果的优化对照（2026-10-17）

`PILI_POWER_PROBE=true` 与 `PILI_POWER_COMPARE_AMBIENT=true` 组合后，环境光始终开启，
同一视频按旧取图/新实现 ABBA 对照；mpv另加 `PILI_AMBIENT_GPU_TEXTURE=true` 才使用现有纹理，
Media3比较PNG与原生明确通道顺序的RGBA。上述开关默认false。
`PILI_AMBIENT_RAW_RGBA=true` 可单独开启Media3原生像素路径，默认false；研究尚未证明稳定收益。
纹理复用虽省去读回和截图，但可能增加栅格/GPU工作，不能只凭CPU下降认定省电。
采集增加 `--screenshots` 可保存窗口结束后的效果图；图像不是同一视频帧，不能当作逐像素对照。

界面对照使用 `PILI_UI_POWER_PROBE=true` 与 `PILI_UI_POWER_COMPARE_UNIFORM=true`，
两组都开启磨砂，A保留纯色背景的模糊，B跳过该项并以RepaintBoundary隔离顶栏；底栏等动态背景仍正常模糊。
普通包仅对首页三个已确认纯色背景的顶栏材质启用这一优化，不降低刷新率、画质或弹幕。
测试中材质内部与文字像素一致，圆角边缘存在少量抗锯齿混合差异，详见性能报告。


两个分阶段采集器可选 `--gpu-busy`，保存KGSL gpubusy原始busy/total和可用时的频率。
缺少权限、零区间和非法数值记为未知，不当作零负载；统计排除首个可能跨界的读数。
输出是整机GPU滚动窗口的采样比例，可能存在重叠/空隙，并非完整积分或应用独占利用率。
本机GPU频率节点权限拒绝，不能由忙碌比例换算W或认定两组频率一致。
`ui-uniform-abba`/`ui-uniform-repeat-abba`为只跳过滤镜的旧原型，
`ui-boundary-abba`为增加顶栏重绘隔离的实现，比较数据时必须区分APK和实现版本。


## 正常播放的硬解预留速率研究

研究构建组合 `PILI_POWER_PROBE=true` 与 `PILI_POWER_COMPARE_OPERATING_RATE=true`，
其余环境光实现对照开关关闭，日常默认为false。仅mpv固定M417，180/60/60/180四窗，
各窗前通过暂时关闭/恢复原视频轨道重建解码器，再seek并预热到同一68秒位置。
这是1倍速正常播放的开销对照，不是运行中无缝切换方案，不能用于长按手势。
低预留组不能直接用作日常默认，否则可能恢复老机倍速掉帧。

```powershell
python tool/playback_power_probe.py --serial AEFUUT1715006716 --output C:/Temp/pili-decoder-reserve --expected-phases 4 --aligned-window --gpu-busy --codec-config
```

`--codec-config`保留原生CCodec/CCodecConfig日志。采集器将组件名称与线程绑定，仅接受
同一PID的视频解码器algo.rate变化；每窗前最后值必须等于目标，且硬解状态和选项回读匹配。
缺少原生证据时valid=false；不会把AAC速率、其他进程、未知或已复用的线程当成证据。
完成/取消时恢复原选项和视频轨道，仍必须重新安装日常候选并复核哈希。


`--display-context`还会为每个phase_start保存显示/亮度、解锁和前台状态，并参与有效性校验。
它核对系统状态，不自动证明各窗口的模式/亮度一致，比较时仍需审阅每窗display.json。
原生algo.rate证据代表配置值，不代表实际解码速度/功率；正常播放仍应校验60送显/秒。
本机两轮180/60对照未支持降低预留作为省电方案，日常需求规划不变。


## 视频合成与调度追踪

`composition_trace.py`默认只采当前前台状态，不导航或解锁。先人工核对同一片源、倍速、显示/亮度，
采集前后保存图层、前台、热状态和截图；不会自动将不同状态判断为可比，也不输出瓦数。
分析需Python包perfetto及官方trace_processor_shell，允许显式指定已核验的二进制路径。

```powershell
python tool/composition_trace.py capture --serial AEFUUT1715006716 --output C:/Temp/pili-texture-A1 --gpu-busy
python tool/composition_trace.py analyze --trace C:/Temp/pili-texture-A1/trace.pftrace --output C:/Temp/pili-texture-A1 --trace-processor C:/Tools/trace_processor_shell.exe
```

捕获命令等待追踪完成再拉文件，防止未落盘的空数据；22秒/128MiB默认保留紧凑调度。
看唤醒者时必须加`--wakers`（非紧凑/256MiB），旧紧凑数据的null不能当作定时器唤醒。
显式`--hold 1900 500 --seconds 30 --wakers`会在第6秒于所给坐标长按4秒，仅用于已核对横屏布局的备用机。
`--start-seconds`/`--end-seconds`可以按追踪起点裁剪分析窗口；logcat标记用REALTIME时钟快照对齐。
工具保留解析错误、丢失统计和前台/显示原文，比较前必须审阅；FrameTimeline缺少视频Surface条目不能当作零掉帧。
`--gpu-busy`仍只是整机滚动采样，首尾跨界读数应排除，不能比较为应用独占功耗。

后端研究构建组合`PILI_POWER_PROBE=true`、`PILI_POWER_TRACE_ONLY=true`与`PILI_POWER_MEDIA3_SDR=true`，
traceOnly令实验run立即返回，不执行ABBA、seek或采样回调；仅保留M417测试后端选择。
全部默认false，结束必须恢复已验证日常包、核对安装哈希及原始息屏设置。
