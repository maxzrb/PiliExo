# PiliExo

[![GitHub release](https://img.shields.io/github/v/release/maxzrb/PiliExo?label=release)](https://github.com/maxzrb/PiliExo/releases/latest)
[![GitHub all releases](https://img.shields.io/github/downloads/maxzrb/PiliExo/total)](https://github.com/maxzrb/PiliExo/releases)

PiliExo 是基于 [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) 的 Android 分支，提供在线视频与番剧的原生 HDR 播放，并补充了音视频解码、播放洞察和交互设置。采用独立包名 `com.maxzrb.piliexo`，可与原版 PiliPlus 共存安装。

## 特色功能

### HDR 与播放内核

- **原生 HDR 播放**：支持 **HDR10**、**HDR Vivid** 等主流 HDR 格式的原生高动态范围显示。
- **三条播放路线切换**：提供 **Media3 原生 HDR**、**mpv 原生 HDR** 与 **mpv 兼容播放** 三种路线，可在播放页「更多」菜单直接切换，保留当前进度、播放状态与倍速。
- **mpv / FFmpeg 播放改进**：补齐 HDR 动态元数据传递、高采样率 FLAC 缓冲与 Android 在线分轨拖动跳转处理。

### 音视频与播放辅助

- **多语言配音**：支持选择视频提供的多语言配音，可在「翻译与字幕」面板分别选择配音与字幕，音质独立设置，切换音轨时保留当前画面。
- **画质与音质管理**：播放设置中的画质、音质选项集中到「画质与音质」二级菜单，可分别设置半屏、全屏、移动数据和直播的默认画质，以及默认音质。
- **应用内音量**：可单独调节播放音量，开启音量增强后最高可调至 200%。
- **视频 CDN**：可选择地区节点、添加自定义域名，并在设置或播放页对比延迟和下载速度。
- **高能进度条**：根据弹幕密度生成平滑曲线，帮助定位弹幕集中的片段。
- **多声道与无损音频软解**：Media3 与 mpv 同步集成 FFmpeg 软件音频解码支持，补充多声道环绕声与高规格无损音轨的播放能力。
- **播放器洞察**：查看帧率、视音频编码、解码器、分辨率、码率、网络带宽与实际输出丢帧，支持常驻显示、起播或掉帧时自动弹出及背景透明度调节。
- **蓝牙延迟补偿**：支持自动估算蓝牙音频延迟，可在弹窗内视听校准并手动微调，断开蓝牙音频时自动暂停补偿。
- **音频焦点设置**：可选择其他应用发声打断时，播放器是否自动暂停和恢复。

### 首页推荐与动态

- **动态搜索 UP 主**：在动态筛选栏点「搜索UP」，输入昵称的一部分即可查找已关注的 UP 主，选中后直接查看对方的动态。
- **首页推荐来源**：可选 Web 推荐、App 推荐，或用滑块调整两者的混合比例。保存后下拉刷新首页即可生效。
- **推荐过滤**：可按 UP 主昵称或 UID 过滤推荐，设置白名单，并将过滤规则应用到热门和排行。

### 界面与交互

- **状态栏环境光与磨砂栏**：播放页顶部状态栏可跟随视频画面显示环境色与模糊背景；顶栏、底栏与浮动底栏提供轻薄、标准、浓厚三档磨砂半透明效果。
- **Android 14+ 预测性返回**：支持跟手滑动返回预览，可调整滑动方向、位移、圆角与缩放幅度，原生 HDR 返回时使用当前视频帧过渡。
- **震动反馈调节**：底栏与侧栏导航、全屏手势，以及播放页滑动调节音量与亮度均支持按刻度触发震动反馈，可调节强度与触发间隔。
- **播放手势**：长按后上滑可锁定倍速，全屏锁定按钮可移到右侧。
- **字体按需管理**：界面字体默认跟随系统，可在设置内下载、离线使用或删除 HarmonyOS Sans SC、MiSans 和萝莉体第二版，也可导入本地字体（[鸿蒙字体许可](assets/fonts/harmonyos_sans/LICENSE.txt) · [MiSans 字体许可](https://hyperos.mi.com/font/download)）。
- **应用内镜像更新**：检查更新优先使用 ModelScope 国内镜像（失败时回退 GitHub），支持多线程分片下载、断点续传与 SHA-256 校验。

### 鸣谢

应用内音量、半屏与全屏画质预设、全屏锁定按钮位置、上滑锁定倍速、高能进度条、推荐过滤及视频 CDN 适配参考了开源项目 [PiliNara](https://github.com/Starfallan/PiliNara)。

## 下载与安装

- **GitHub Releases**：[下载最新正式版](https://github.com/maxzrb/PiliExo/releases/latest) · [查看全部版本](https://github.com/maxzrb/PiliExo/releases)
- **ModelScope 国内镜像**：[AerithDream/PiliExo](https://modelscope.cn/datasets/AerithDream/PiliExo)

安装包提供 `arm64-v8a`（64 位设备）与 `armeabi-v7a` 两种架构，按设备架构下载安装即可；也可在应用「关于」页面检查更新和查看当前版本说明。

## 项目信息

- 适用平台：Android（`arm64-v8a` / `armeabi-v7a`）
- 上游同步：跟进 [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) Android 端更新（当前至 `2.2.1`）
- Flutter 工具链：`3.47.9`

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
