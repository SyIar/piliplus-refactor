# PiliPlus for iOS 27

把 [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) 从 Flutter 重写成的原生 SwiftUI 客户端，面向 iPhone 18 Pro / iOS 27。

菜单、底栏、首页分区、动态、我的、搜索筛选、视频操作（点赞 / 点踩 / 投币 / 收藏 / 再看 / 分享 / 三连）、播放器手势和设置项与上游保持同一套信息架构。界面使用系统 Liquid Glass（`glassEffect`、悬浮底栏、底部正在播放），跟随系统的「外观 → Liquid Glass」透明度。

## 打开

需要 Xcode 26 或更新（iOS 26 SDK，部署目标 iOS 26，在 iOS 27 上为原生液态玻璃）。

1. 用 Xcode 打开 `PiliPlus.xcodeproj`
2. 选择你的开发团队
3. 目标设备选 iPhone 18 Pro
4. 运行

## 已经接通的能力

- 首页推荐、热门、排行、直播广场（哔哩哔哩公开接口）
- 搜索（综合 / 视频筛选：排序、时长、分区、发布时间）与热搜
- 视频详情、分 P、相关视频、评论、画质取流与 `AVPlayer` 播放
- 弹幕层、高能进度条、双击快进、长按二倍速、亮度 / 音量手势
- 设置里的全部开关与选项，写入本机
- 登录入口：扫码、密码、短信、Cookie

未登录时，点赞、投币、收藏、关注、发弹幕会进入登录。Cookie 登录目前保存的是本地会话标记；把 SESSDATA 接到请求头后，即可走与上游相同的写接口。

## 说明

这是独立的 Swift 重写，不是把 Flutter 工程嵌进 iOS。上游的 gRPC 弹幕、离线下载引擎和 WebDAV 同步在对应页面留了与原版一致的操作项，播放和浏览已使用公开 HTTP 接口。
