# PiliExo

PiliExo 是基于 [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) 的 Android fork，面向 Android 在线 UGC/PGC 视频提供原生 HDR 播放能力。包名为 `com.maxzrb.piliexo`，可与原版 PiliPlus 共存；SDR、直播和离线播放使用 mpv。

## 项目状态

- 当前正式版本：[v26.10.7.2](https://github.com/maxzrb/PiliExo/releases/tag/v26.10.7.2)（2026-10-07）。
- Flutter 工具链：`3.47.6`，版本以 `.fvmrc` 和 `pubspec.yaml` 为准。
- 发布源码分支：[`merge/upstream-2.1.4-20260913`](https://github.com/maxzrb/PiliExo/tree/merge/upstream-2.1.4-20260913)。编译当前版本请使用该分支或对应 Release 标签。
- 仅构建和发布 Android；正式 APK 提供 `arm64-v8a` 和 `armeabi-v7a`。其他平台代码随上游保留。
- PiliPlus 上游改动已审查至 `4ed5968f3`（2.1.6），最近一轮合入 41 项功能、修复和依赖更新，保留 PiliExo 的播放器与界面定制。

## PiliExo 的实际修改

- Android 在线 UGC/PGC 的 HDR 播放使用 Media3 原生 `SurfaceView`；支持符合设备能力的 HDR10、Dolby Vision 和 HDR Vivid，播放失败时保留 mpv 回退。
- 修复高采样率 FLAC 音轨导致 HDR 播放失败的问题：从音轨元数据补齐真实采样率，按每条音轨的最大帧大小配置输入缓冲。
- 播放器洞察提供概览、视频、音频、播放和事件详情，显示编码、解码器、分辨率、码率、音频参数和回退原因。
- 顶栏、底栏和浮动底栏支持磨砂半透明，可关闭或选择轻薄、标准、浓厚效果；设置页面状态栏图标随顶栏背景明暗适配。
- 播放手势支持可配置的震动反馈和强度；播放中调整画质、移动数据画质或音质只作用于当前播放，不回写默认设置。
- 首页推荐支持 Web/App 混合比例，按 10% 步进调整；下次刷新生效，结果交错、去重，并在单路请求失败时兜底。
- 检查更新优先使用 ModelScope，失败时回退 GitHub；ARM64 更新支持 Aria2-next 分片下载、断点续传、SHA-256 校验、进度显示、取消和系统安装器。
- 同步上游离线片段跳过和 UGC 合集缓存，改善收藏夹、番剧多季度切换、直播、黑名单过滤、图片缩放手势与媒体通知切换视频。
- 选中文字默认提供站内搜索，选中网址可直接打开，同时保留调用方自定义菜单。

## 下载与更新

- [最新正式版](https://github.com/maxzrb/PiliExo/releases/latest) · [全部 GitHub Releases](https://github.com/maxzrb/PiliExo/releases)
- [ModelScope 镜像数据集](https://modelscope.cn/datasets/AerithDream/PiliExo)
- [版本迭代记录](https://github.com/maxzrb/PiliExo/blob/merge/upstream-2.1.4-20260913/version/版本迭代记录.md) · [Android 发布流程](https://github.com/maxzrb/PiliExo/blob/merge/upstream-2.1.4-20260913/docs/发布流程.md) · [本机工具链说明](https://github.com/maxzrb/PiliExo/blob/merge/upstream-2.1.4-20260913/docs/本机发布工具链.md)

APK 文件名包含架构；按设备支持的 ABI 选择 `arm64-v8a` 或 `armeabi-v7a`。需要的画质和内容权限仍取决于账号、视频和设备支持。

## 构建与发布维护

当前发布使用 Flutter `3.47.6` 和项目补丁集。请按 Android 发布流程完成依赖获取、插件注册检查、测试、签名与 APK 校验；Windows Android 构建不能忽略 `flutter pub get` 的符号链接错误。

每次正式发布必须更新本 README 的版本、工具链、功能说明和下载入口，并执行 `lib/scripts/verify_readme.ps1`。构建元数据脚本与 Android CI 会校验 README 中的版本、Flutter 版本是否与项目配置一致；发布后还需同步 GitHub 默认分支的 README。

本项目是个人为了兴趣而开发的第三方自用修改版，仅用于学习和测试，请于下载后 24 小时内删除。所用 API 皆从官方网站收集，不提供任何破解内容。

下方为 PiliPlus 上游 README 快照，取自提交 [`4ed5968f3`](https://github.com/bggRGjQaUbCoE/PiliPlus/tree/4ed5968f37af8b4aa7e0f13178cb8d8c2f86defc)。其中的平台支持和项目计划属于原项目，PiliExo 的发布范围见上方说明。

---

## 以下为原项目 README 内容

<div align="center">
    <img width="200" height="200" src="assets/images/logo/logo.png">
</div>



<div align="center">
    <h1>PiliPlus</h1>
<div align="center">

中文 | [English](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/4ed5968f37af8b4aa7e0f13178cb8d8c2f86defc/README.en.md)

![GitHub repo size](https://img.shields.io/github/repo-size/bggRGjQaUbCoE/PiliPlus)
![GitHub Repo stars](https://img.shields.io/github/stars/bggRGjQaUbCoE/PiliPlus)
![GitHub all releases](https://img.shields.io/github/downloads/bggRGjQaUbCoE/PiliPlus/total)
</div>
    <p>使用Flutter开发的BiliBili第三方客户端</p>

<img src="assets/screenshots/510shots_so.png" width="32%" alt="home" />
<img src="assets/screenshots/174shots_so.png" width="32%" alt="home" />
<img src="assets/screenshots/850shots_so.png" width="32%" alt="home" />
<br/>
<img src="assets/screenshots/main_screen.png" width="96%" alt="home" />
<br/>
</div>


<br/>

## 适配平台

- [x] Android
- [x] iOS
- [x] Pad
- [x] Windows
- [x] Linux

[![Packaging status](https://repology.org/badge/vertical-allrepos/piliplus.svg)](https://repology.org/project/piliplus/versions)

## refactor

- [ ] gRPC [wip]
- [x] 用户界面
- [x] 其他

## feat

- [x] 编辑动态
- [x] DLNA 投屏
- [x] 离线缓存/播放
- [x] 移动端支持点击弹幕悬停，点赞、复制、举报 by [@My-Responsitories](https://github.com/My-Responsitories)
- [x] 播放音频
- [x] 跳过番剧片头/片尾
- [x] 安卓端 `loudnorm` 适配 by [@My-Responsitories](https://github.com/My-Responsitories)
- [x] Win/Mac 支持极验、短信登录 by [@My-Responsitories](https://github.com/My-Responsitories)
- [x] 视频截取动图 by [@My-Responsitories](https://github.com/My-Responsitories)
- [x] AI 原声翻译
- [x] SuperChat
- [x] 播放课堂视频
- [x] 发起投票
- [x] 发布动态/评论支持`富文本编辑`/`表情显示`/`@用户`
- [x] 修改消息设置
- [x] 修改聊天设置
- [x] 展示折叠消息
- [x] 查看用户图文
- [x] 动态话题
- [x] 直播分区
- [x] 分享`视频`/`番剧`/`动态`/`专栏`/`直播`至消息
- [x] 创建/修改/删除关注分组
- [x] 移除粉丝
- [x] 直播弹幕发送表情
- [x] 收藏夹排序
- [x] 稍后再看 ~~`未看`~~ / `未看完` / ~~`已看完`~~ 分类
- [x] WebDAV 备份/恢复设置
- [x] 保存评论/动态
- [x] 高级弹幕 by [@My-Responsitories](https://github.com/My-Responsitories)
- [x] 取消/置顶评论
- [x] 记笔记
- [x] 多账号支持 by [@My-Responsitories](https://github.com/My-Responsitories)
- [x] 屏蔽带货动态/评论
- [x] 互动视频
- [x] 发评/动态反诈
- [x] 高能进度条
- [x] 滑动跳转预览视频缩略图
- [x] Live Photo
- [x] 复制/移动/排序收藏夹/稍后再看视频
- [x] 超分辨率
- [x] 合并弹幕
- [x] 会员彩色弹幕
- [x] 播放全部/继续播放/倒序播放
- [x] Cookie登录
- [x] 显示视频分段信息
- [x] 调节字幕大小
- [x] 调节全屏弹幕大小
- [x] 收藏夹/稍后再看多选删除
- [x] 搜索用户动态
- [x] 直播弹幕
- [x] 修改头像/用户名/签名/性别/生日
- [x] 创建/编辑/删除收藏夹
- [x] 评论楼中楼查看对话
- [x] 评论楼中楼定位点击查看的评论
- [x] 评论楼中楼按热度/时间排序
- [x] 评论点踩
- [x] 私信发图
- [x] 投币动画
- [x] 取消/追番，更新追番状态
- [x] 取消/订阅合集
- [x] SponsorBlock
- [x] 显示视频完整合集
- [x] 三连动画
- [x] 番剧三连
- [x] 带图评论
- [x] 视频TAG
- [x] 筛选搜索
- [x] 转发动态
- [x] 合集图片
- [x] 删除/置顶/撤回私信
- [x] 举报用户/评论/视频/动态
- [x] 删除/发布/置顶文本/图片动态
- [x] 其他

## opt

- [x] 专栏界面
- [x] 私信界面
- [x] 收藏面板
- [x] PIP
- [x] 视频封面
- [x] 回复界面
- [x] 系统通知
- [x] 评论显示
- [x] 亮度调节
- [x] 视频播放
- [x] 视频staff
- [x] 防止bottomsheet遮挡全屏视频
- [x] 其他

## fix

- [x] 番剧分集点赞/投币/收藏
- [x] bugs

<br/>

## 功能

- [x] 推荐视频列表(app端)
- [x] 最热视频列表
- [x] 热门直播
- [x] 番剧列表
- [x] 屏蔽黑名单内用户视频
- [x] 无痕模式（播放视为未登录）
- [x] 游客模式（推荐视为未登录）

- [x] 用户相关
  - [x] 粉丝、关注用户、拉黑用户查看
  - [x] 用户主页查看
  - [x] 关注/取关用户
  - [x] 离线缓存
  - [x] 稍后再看
  - [x] 观看记录
  - [x] 我的收藏
  - [x] 站内私信

- [x] 动态相关
  - [x] 全部、投稿、番剧分类查看
  - [x] 动态评论查看
  - [x] 动态评论回复功能

- [x] 视频播放相关
  - [x] 双击快进/快退
  - [x] 双击播放/暂停
  - [x] 垂直方向调节亮度/音量
  - [x] 垂直方向上滑全屏、下滑退出全屏
  - [x] 水平方向手势快进/快退
  - [x] 全屏方向设置
  - [x] 倍速选择/长按2倍速
  - [x] 硬件加速（视机型而定）
  - [x] 画质选择（高清画质未解锁）
  - [x] 音质选择（视视频而定）
  - [x] 解码格式选择（视视频而定）
  - [x] 弹幕
  - [x] 字幕
  - [x] 记忆播放
  - [x] 视频比例：高度/宽度适应、填充、包含等

- [x] 搜索相关
  - [x] 热搜
  - [x] 搜索历史
  - [x] 默认搜索词
  - [x] 投稿、番剧、直播间、用户搜索
  - [x] 视频搜索排序、按时长筛选

- [x] 视频详情页相关
  - [x] 视频选集(分p)切换
  - [x] 点赞、投币、收藏/取消收藏
  - [x] 相关视频查看
  - [x] 评论用户身份标识
  - [x] 评论(排序)查看、二楼评论查看
  - [x] 主楼、二楼评论回复功能
  - [x] 评论点赞
  - [x] 评论笔记图片查看、保存

- [x] 设置相关
  - [x] 画质、音质、解码方式预设
  - [x] 图片质量设定
  - [x] 主题模式：亮色/暗色/跟随系统
  - [x] 震动反馈(可选)
  - [x] 高帧率
  - [x] 自动全屏
  - [x] 横屏适配
- [ ] 等等

<br/>

## 下载

可以从 [Releases](https://github.com/bggRGjQaUbCoE/PiliPlus/releases) 下载，或克隆仓库拉取代码后在本地编译。

<br/>

## 声明

此项目（PiliPlus）是个人为了兴趣而开发，仅用于学习和测试，请于下载后24小时内删除。
所用API皆从官方网站收集，不提供任何破解内容。
在此致敬原作者：[guozhigq/pilipala](https://github.com/guozhigq/pilipala)
在此致敬上游作者：[orz12/PiliPalaX](https://github.com/orz12/PiliPalaX)
本仓库做了更激进的修改，感谢原作者的开源精神。

感谢使用


<br/>

## 致谢

- [bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect)
- [flutter_meedu_videoplayer](https://github.com/zezo357/flutter_meedu_videoplayer)
- [media-kit](https://github.com/media-kit/media-kit)
- [dio](https://pub.dev/packages/dio)
- 等等

<br/>
<br/>
<br/>

## Star History

<a href="https://star-history.dera.page/#bggRGjQaUbCoE/PiliPlus&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://star-history.dera.page/svg?repos=bggRGjQaUbCoE/PiliPlus&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://star-history.dera.page/svg?repos=bggRGjQaUbCoE/PiliPlus&type=Date" />
   <img alt="Star History Chart" src="https://star-history.dera.page/svg?repos=bggRGjQaUbCoE/PiliPlus&type=Date" />
 </picture>
</a>
