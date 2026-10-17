import Foundation

struct SettingRow: Identifiable, Hashable {
    var id: String { title }
    let title: String
    let subtitle: String
    let kind: Kind

    enum Kind: Hashable {
        case toggle
        case options([String])
        case text
    }
}

enum Menus {
    static let settingSections: [(title: String, subtitle: String, system: String)] = [
        ("隐私设置", "黑名单", "hand.raised"),
        ("推荐流设置", "推荐来源（web/app）、刷新保留内容、过滤器", "sparkles"),
        ("音视频设置", "画质、音质、解码、缓冲、音频输出等", "waveform"),
        ("播放器设置", "双击/长按、全屏、后台播放、弹幕、字幕、底部进度条等", "play.rectangle"),
        ("外观设置", "横屏适配（平板）、侧栏、列宽、首页、动态红点、主题、字号、图片、帧率等", "paintpalette"),
        ("其它设置", "震动、搜索、收藏、ai、评论、动态、代理、更新检查等", "slider.horizontal.3"),
        ("WebDAV 设置", "备份与恢复设置", "externaldrive"),
        ("关于", "PiliPlus Swift", "info.circle")
    ]

    static let settings: [String: [SettingRow]] = [
        "隐私设置": [
            .init(title: "黑名单管理", subtitle: "已拉黑用户", kind: .text),
            .init(title: "了解账号模式", subtitle: "查看各个账号模式作用的 API 列表", kind: .text)
        ],
        "推荐流设置": [
            .init(title: "buvid", subtitle: "设备标识，点击复制", kind: .text),
            .init(title: "首页使用app端推荐", subtitle: "若 web 端推荐不太符合预期，可尝试切换至 app 端推荐", kind: .toggle),
            .init(title: "保留首页推荐刷新", subtitle: "下拉刷新时保留上次内容", kind: .toggle),
            .init(title: "显示上次看到位置提示", subtitle: "保留上次推荐时，在上次刷新位置显示提示", kind: .toggle),
            .init(title: "点赞率", subtitle: "低于该点赞率的视频将被过滤，0 即不过滤", kind: .options(["不过滤", "1%", "3%", "5%", "8%"])),
            .init(title: "标题关键词过滤", subtitle: "命中标题的推荐将被隐藏", kind: .text),
            .init(title: "分区关键词过滤", subtitle: "命中分区名的推荐将被隐藏", kind: .text),
            .init(title: "视频时长", subtitle: "过滤过短或过长的视频", kind: .options(["不过滤", "短于 30 秒", "短于 1 分钟", "长于 60 分钟"])),
            .init(title: "播放量", subtitle: "过滤播放量过低的视频", kind: .options(["不过滤", "低于 1千", "低于 1万"])),
            .init(title: "已关注UP豁免推荐过滤", subtitle: "推荐中已关注用户发布的内容不会被过滤", kind: .toggle),
            .init(title: "过滤器也应用于详情页相关视频", subtitle: "其它（如热门、搜索）均不受过滤器影响", kind: .toggle)
        ],
        "音视频设置": [
            .init(title: "开启硬解", subtitle: "以较低功耗播放视频，若异常卡死请关闭", kind: .toggle),
            .init(title: "免登录1080P", subtitle: "免登录查看 1080P 视频", kind: .toggle),
            .init(title: "B站定向流量支持", subtitle: "若套餐含 B 站定向流量，则会自动使用", kind: .toggle),
            .init(title: "CDN 设置", subtitle: "选择视频 CDN", kind: .options(["默认", "镜像 1", "镜像 2", "自定义"])),
            .init(title: "直播 CDN 设置", subtitle: "选择直播 CDN", kind: .options(["默认", "线路 1", "线路 2"])),
            .init(title: "CDN 测速", subtitle: "测速通过模拟加载视频实现，注意流量消耗，结果仅供参考", kind: .text),
            .init(title: "音频不跟随 CDN 设置", subtitle: "直接采用备用 URL，可解决部分视频无声", kind: .toggle),
            .init(title: "默认画质", subtitle: "Wi-Fi 默认画质", kind: .options(["自动", "流畅 360P", "高清 720P", "高清 1080P", "高清 1080P60", "超清 4K"])),
            .init(title: "蜂窝网络画质", subtitle: "蜂窝网络默认画质", kind: .options(["自动", "流畅 360P", "高清 720P", "高清 1080P"])),
            .init(title: "默认音质", subtitle: "默认音质", kind: .options(["64K", "132K", "192K", "杜比全景声", "Hi-Res"])),
            .init(title: "蜂窝网络音质", subtitle: "蜂窝网络音质", kind: .options(["64K", "132K", "192K"])),
            .init(title: "直播默认画质", subtitle: "直播默认画质", kind: .options(["流畅", "高清", "超清", "蓝光", "原画"])),
            .init(title: "蜂窝网络直播默认画质", subtitle: "蜂窝直播画质", kind: .options(["流畅", "高清", "超清"])),
            .init(title: "首选解码格式", subtitle: "优先请求的编码", kind: .options(["av1", "hev1", "avc1"])),
            .init(title: "蜂窝网络首选解码格式", subtitle: "蜂窝优先编码", kind: .options(["avc1", "hev1", "av1"])),
            .init(title: "音频输出设备", subtitle: "当前输出设备", kind: .options(["系统默认", "扬声器", "听筒"])),
            .init(title: "缓冲大小", subtitle: "播放器缓冲大小", kind: .options(["16MB", "32MB", "64MB", "128MB"])),
            .init(title: "缓冲时长", subtitle: "播放器缓冲时长", kind: .options(["2s", "5s", "10s", "20s"])),
            .init(title: "自动同步", subtitle: "mpv --autosync", kind: .options(["0", "10", "30"])),
            .init(title: "视频同步", subtitle: "mpv --video-sync", kind: .options(["audio", "display-resample", "display-vdrop"])),
            .init(title: "硬解模式", subtitle: "mpv --hwdec", kind: .options(["auto", "videotoolbox", "no"]))
        ],
        "播放器设置": [
            .init(title: "弹幕开关", subtitle: "是否展示弹幕", kind: .toggle),
            .init(title: "启用点击弹幕", subtitle: "点击弹幕悬停，支持点赞、复制、举报", kind: .toggle),
            .init(title: "倍速设置", subtitle: "设置视频播放速度", kind: .options(["0.5x", "0.75x", "1.0x", "1.25x", "1.5x", "2.0x", "3.0x"])),
            .init(title: "倾斜角度阈值", subtitle: "重力感应进入全屏的角度", kind: .options(["20°", "30°", "40°", "关闭"])),
            .init(title: "自动播放", subtitle: "进入详情页自动播放", kind: .toggle),
            .init(title: "全屏显示锁定按钮", subtitle: "全屏时显示锁定", kind: .toggle),
            .init(title: "全屏显示截图按钮", subtitle: "全屏时显示截图", kind: .toggle),
            .init(title: "全屏显示电池电量", subtitle: "全屏顶栏显示电量", kind: .toggle),
            .init(title: "双击快退/快进", subtitle: "左侧双击快退 / 右侧双击快进，关闭则双击均为暂停", kind: .toggle),
            .init(title: "左右侧滑动调节亮度/音量", subtitle: "左侧亮度，右侧音量", kind: .toggle),
            .init(title: "调节系统亮度", subtitle: "亮度手势调节系统亮度", kind: .toggle),
            .init(title: "中间滑动进入/退出全屏", subtitle: "播放器中部上下滑动切换全屏", kind: .toggle),
            .init(title: "播放器音量", subtitle: "播放器内音量", kind: .options(["50%", "80%", "100%"])),
            .init(title: "最高音量", subtitle: "音量增益上限", kind: .options(["100%", "125%", "150%"])),
            .init(title: "双击快进/快退时长", subtitle: "双击跳转秒数", kind: .options(["5 秒", "10 秒", "15 秒", "30 秒"])),
            .init(title: "滑动快进/快退使用相对时长", subtitle: "按视频总时长比例跳转", kind: .toggle),
            .init(title: "滑动快进/快退时长", subtitle: "从播放器一端滑到另一端的时长", kind: .options(["60 秒", "90 秒", "180 秒"])),
            .init(title: "自动启用字幕", subtitle: "进入播放自动打开字幕", kind: .toggle),
            .init(title: "字幕选择偏好", subtitle: "优先字幕语言", kind: .options(["自动", "简中", "繁中", "英语", "日语"])),
            .init(title: "最小化时暂停/还原时播放", subtitle: "桌面窗口行为", kind: .toggle),
            .init(title: "启用键盘控制", subtitle: "空格暂停，方向键快进", kind: .toggle),
            .init(title: "SuperChat (醒目留言) 显示类型", subtitle: "直播 SC 样式", kind: .options(["滚动", "顶部固定", "关闭"])),
            .init(title: "全屏 SC 大小", subtitle: "醒目留言大小", kind: .options(["小", "中", "大"])),
            .init(title: "竖屏扩大展示", subtitle: "小屏竖屏视频宽高比由 16:9 扩大至 1:1", kind: .toggle),
            .init(title: "自动全屏", subtitle: "视频开始播放时进入全屏", kind: .toggle),
            .init(title: "自动退出全屏", subtitle: "视频结束播放时退出全屏", kind: .toggle),
            .init(title: "延长播放控件显示时间", subtitle: "开启后延长至 30 秒", kind: .toggle),
            .init(title: "后台播放", subtitle: "进入后台时继续播放", kind: .toggle),
            .init(title: "后台画中画", subtitle: "进入后台时以小窗播放", kind: .toggle),
            .init(title: "画中画不加载弹幕", subtitle: "小窗屏蔽弹幕", kind: .toggle),
            .init(title: "全屏手势反向", subtitle: "默认向上全屏、向下退出", kind: .toggle),
            .init(title: "全屏展示点赞/投币/收藏等操作按钮", subtitle: "全屏底栏操作", kind: .toggle),
            .init(title: "观看人数", subtitle: "展示同时在看人数", kind: .toggle),
            .init(title: "默认全屏方向", subtitle: "进入全屏时的方向", kind: .options(["跟随视频", "强制横屏", "强制竖屏", "不改变当前方向"])),
            .init(title: "底部进度条展示", subtitle: "详情页底部进度条", kind: .options(["常驻", "跟随控件", "关闭"])),
            .init(title: "后台音频服务", subtitle: "避免画中画没有播放暂停功能", kind: .toggle),
            .init(title: "播放顺序", subtitle: "列表连播方式", kind: .options(["自动连播", "单集循环", "列表循环", "播完暂停", "倒序播放"])),
            .init(title: "播放器设置仅对当前生效", subtitle: "弹幕、字幕及部分设置除外", kind: .toggle)
        ],
        "外观设置": [
            .init(title: "横屏适配", subtitle: "启用横屏布局，平板、折叠屏可开启", kind: .toggle),
            .init(title: "改用侧边栏", subtitle: "开启后底栏与顶栏被替换", kind: .toggle),
            .init(title: "App字体设置", subtitle: "点击设置", kind: .options(["系统默认", "更小", "默认", "更大", "特大"])),
            .init(title: "界面缩放", subtitle: "整体界面缩放", kind: .options(["0.85", "1.00", "1.10", "1.20"])),
            .init(title: "页面过渡动画", subtitle: "页面切换动画", kind: .options(["系统", "淡入", "滑动", "缩放"])),
            .init(title: "优化平板导航栏", subtitle: "平板使用更宽的导航", kind: .toggle),
            .init(title: "MD3样式底栏", subtitle: "关闭后底栏更窄。iOS 使用液态玻璃底栏", kind: .toggle),
            .init(title: "悬浮底栏", subtitle: "底栏悬浮为玻璃胶囊", kind: .toggle),
            .init(title: "列表宽度（dp）限制", subtitle: "多列时单列最大宽度", kind: .options(["180", "220", "240", "280"])),
            .init(title: "播放页移除安全边距", subtitle: "播放器贴边", kind: .toggle),
            .init(title: "视频播放页使用深色主题", subtitle: "播放页强制深色", kind: .toggle),
            .init(title: "动态页启用瀑布流", subtitle: "关闭会显示为单列", kind: .toggle),
            .init(title: "动态页UP主显示位置", subtitle: "UP 名称位置", kind: .options(["头像右侧", "卡片底部"])),
            .init(title: "动态页显示所有已关注UP主", subtitle: "顶部展示全部关注", kind: .toggle),
            .init(title: "动态页展开正在直播UP列表", subtitle: "展开直播中的 UP", kind: .toggle),
            .init(title: "动态未读标记", subtitle: "底栏动态红点", kind: .toggle),
            .init(title: "消息未读标记", subtitle: "顶栏消息红点", kind: .toggle),
            .init(title: "消息未读类型", subtitle: "计入红点的消息类型", kind: .options(["全部", "回复我的", "@我", "私信"])),
            .init(title: "顶/底栏收起类型", subtitle: "滑动时如何收起", kind: .options(["即时", "动画"])),
            .init(title: "首页顶栏收起", subtitle: "首页列表滑动时收起顶栏", kind: .toggle),
            .init(title: "首页底栏收起", subtitle: "首页列表滑动时收起底栏", kind: .toggle),
            .init(title: "图片质量", subtitle: "列表图片清晰度，上限 100%", kind: .options(["40%", "60%", "80%", "100%"])),
            .init(title: "查看大图质量", subtitle: "大图清晰度", kind: .options(["80%", "100%", "原图"])),
            .init(title: "深色下图片颜色叠加", subtitle: "显示颜色 = 图片原色 × 所选颜色", kind: .toggle),
            .init(title: "气泡提示不透明度", subtitle: "Toast 不透明度", kind: .options(["70%", "85%", "100%"])),
            .init(title: "主题模式", subtitle: "浅色 / 深色 / 跟随系统", kind: .options(["跟随系统", "浅色", "深色", "纯黑"])),
            .init(title: "纯黑主题", subtitle: "深色下使用纯黑背景", kind: .toggle),
            .init(title: "应用主题", subtitle: "动态取色或指定颜色", kind: .options(["哔哩粉", "动态取色", "蓝色", "绿色"])),
            .init(title: "我的页卡片", subtitle: "我的页展示哪些卡片", kind: .options(["收藏", "收藏+历史", "收藏+历史+稍后再看+订阅"])),
            .init(title: "默认启动页", subtitle: "冷启动打开的页面", kind: .options(["首页", "动态", "我的"])),
            .init(title: "滑动动画弹簧参数", subtitle: "列表回弹手感", kind: .options(["系统", "更软", "更脆"])),
            .init(title: "首页标签页", subtitle: "删除或调换首页标签页", kind: .text),
            .init(title: "Navbar编辑", subtitle: "删除或调换底栏", kind: .text),
            .init(title: "返回时直接退出", subtitle: "主页任意 tab 按返回都直接退出", kind: .toggle),
            .init(title: "屏幕帧率", subtitle: "限制或跟随屏幕刷新率", kind: .options(["自动", "60Hz", "120Hz", "ProMotion"]))
        ],
        "其它设置": [
            .init(title: "空降助手", subtitle: "点击配置 SponsorBlock", kind: .text),
            .init(title: "番剧片头/片尾跳过类型", subtitle: "OP / ED 跳过策略", kind: .options(["始终跳过", "询问", "关闭"])),
            .init(title: "检查未读动态", subtitle: "点击设置检查周期", kind: .options(["关闭", "5 分钟", "15 分钟", "30 分钟"])),
            .init(title: "显示视频分段信息", subtitle: "播放页展示章节", kind: .toggle),
            .init(title: "视频页显示相关视频", subtitle: "详情页相关推荐", kind: .toggle),
            .init(title: "显示视频评论", subtitle: "视频评论区", kind: .toggle),
            .init(title: "显示番剧评论", subtitle: "番剧评论区", kind: .toggle),
            .init(title: "默认展开视频简介", subtitle: "进入详情即展开简介", kind: .toggle),
            .init(title: "横屏自动展开视频简介", subtitle: "横屏时展开简介", kind: .toggle),
            .init(title: "横屏分P/合集列表显示在Tab栏", subtitle: "分 P 放入 Tab", kind: .toggle),
            .init(title: "横屏播放页在侧栏打开UP主页", subtitle: "横屏侧栏打开 UP", kind: .toggle),
            .init(title: "横屏在侧栏打开图片预览", subtitle: "横屏侧栏看图", kind: .toggle),
            .init(title: "评论折叠行数", subtitle: "0 行为不折叠", kind: .options(["0", "3", "6", "8"])),
            .init(title: "弹幕行高", subtitle: "默认 1.6", kind: .options(["1.2", "1.6", "2.0"])),
            .init(title: "显示视频警告/争议信息", subtitle: "争议稿件提示", kind: .toggle),
            .init(title: "显示动态警告/争议信息", subtitle: "争议动态提示", kind: .toggle),
            .init(title: "分P/合集：倒序播放从首集开始播放", subtitle: "倒序时是否跳到首集", kind: .toggle),
            .init(title: "禁用 SSL 证书验证", subtitle: "谨慎开启，禁用容易受到中间人攻击", kind: .toggle),
            .init(title: "显示继续播放分P提示", subtitle: "切 P 前提示", kind: .toggle),
            .init(title: "评论关键词过滤", subtitle: "命中则折叠评论", kind: .text),
            .init(title: "动态关键词过滤", subtitle: "命中则隐藏动态", kind: .text),
            .init(title: "使用外部浏览器打开链接", subtitle: "链接交给 Safari", kind: .toggle),
            .init(title: "横向滑动阈值", subtitle: "判定横向滑动的距离", kind: .options(["系统默认", "更灵敏", "更迟钝"])),
            .init(title: "刷新指示器高度", subtitle: "下拉刷新高度", kind: .options(["紧凑", "默认", "宽松"])),
            .init(title: "显示会员彩色弹幕", subtitle: "大会员彩色弹幕", kind: .toggle),
            .init(title: "合并弹幕", subtitle: "合并一段时间内相同弹幕", kind: .toggle),
            .init(title: "显示热门推荐", subtitle: "热门页显示每周必看等入口", kind: .toggle),
            .init(title: "音量均衡", subtitle: "loudnorm", kind: .toggle),
            .init(title: "超分辨率", subtitle: "播放时超分", kind: .options(["关闭", "质量优先", "性能优先"])),
            .init(title: "提前初始化播放器", subtitle: "相对减少手动播放加载时间", kind: .toggle),
            .init(title: "首页切换页面动画", subtitle: "首页 Tab 切换动画", kind: .toggle),
            .init(title: "搜索建议", subtitle: "输入时展示搜索建议", kind: .toggle),
            .init(title: "记录搜索历史", subtitle: "保存搜索关键词", kind: .toggle),
            .init(title: "展示头像/评论/动态装饰", subtitle: "装扮与粉丝牌", kind: .toggle),
            .init(title: "点击表情显示 Tooltip", subtitle: "表情释义", kind: .toggle),
            .init(title: "显示粉丝勋章", subtitle: "评论与直播勋章", kind: .toggle),
            .init(title: "预览 Live Photo", subtitle: "以视频形式预览 Live Photo", kind: .toggle),
            .init(title: "滑动跳转预览视频缩略图", subtitle: "拖动进度条时预览", kind: .toggle),
            .init(title: "显示高能进度条", subtitle: "弹幕密度进度条", kind: .toggle),
            .init(title: "记录评论", subtitle: "记住评论草稿", kind: .toggle),
            .init(title: "发评反诈", subtitle: "发送评论后检查是否可见", kind: .toggle),
            .init(title: "使用「哔哩发评反诈」检查评论", subtitle: "使用反诈接口", kind: .toggle),
            .init(title: "发布/转发动态反诈", subtitle: "发布后检查动态是否可见", kind: .toggle),
            .init(title: "屏蔽带货动态", subtitle: "隐藏带货动态", kind: .toggle),
            .init(title: "屏蔽带货评论", subtitle: "隐藏带货评论", kind: .toggle),
            .init(title: "侧滑关闭二级页面", subtitle: "边缘滑动返回", kind: .toggle),
            .init(title: "启用双指缩小视频", subtitle: "双指缩放画面", kind: .toggle),
            .init(title: "动态/专栏详情页展示底部操作栏", subtitle: "点赞评论转发栏", kind: .toggle),
            .init(title: "启用拖拽字幕调整底部边距", subtitle: "拖动字幕位置", kind: .toggle),
            .init(title: "展示追番时间表", subtitle: "番剧页时间表", kind: .toggle),
            .init(title: "静默下载图片", subtitle: "不显示下载 Loading", kind: .toggle),
            .init(title: "长按/右键显示图片菜单", subtitle: "保存、复制图片", kind: .toggle),
            .init(title: "震动反馈", subtitle: "请确定系统设置中已开启触感", kind: .toggle),
            .init(title: "大家都在搜", subtitle: "是否展示「大家都在搜」", kind: .toggle),
            .init(title: "搜索发现", subtitle: "是否展示「搜索发现」", kind: .toggle),
            .init(title: "搜索默认词", subtitle: "是否展示搜索框默认词", kind: .toggle),
            .init(title: "快速收藏", subtitle: "点按收藏至默认，长按选择文件夹", kind: .text),
            .init(title: "评论区搜索关键词", subtitle: "展示评论区搜索关键词", kind: .toggle),
            .init(title: "启用AI总结", subtitle: "视频详情页开启 AI 总结", kind: .toggle),
            .init(title: "消息页禁用\"收到的赞\"功能", subtitle: "禁止打开入口", kind: .toggle),
            .init(title: "默认展示评论区", subtitle: "详情页默认切到评论", kind: .toggle),
            .init(title: "启用HTTP/2", subtitle: "网络使用 HTTP/2", kind: .toggle),
            .init(title: "连接重试次数", subtitle: "为 0 时禁用", kind: .options(["0", "2", "3", "5"])),
            .init(title: "连接重试间隔", subtitle: "实际间隔 = 间隔 × 第 x 次重试", kind: .options(["200ms", "500ms", "1000ms"])),
            .init(title: "评论展示", subtitle: "评论排序", kind: .options(["按热度", "按时间"])),
            .init(title: "楼中楼评论展示", subtitle: "子评论排序", kind: .options(["按热度", "按时间"])),
            .init(title: "动态展示", subtitle: "动态列表类型", kind: .options(["全部", "投稿", "番剧", "专栏"])),
            .init(title: "显示动态互动内容", subtitle: "卡片底部显示热评、好友点赞", kind: .toggle),
            .init(title: "用户页默认展示TAB", subtitle: "进入 UP 主页优先 Tab", kind: .options(["主页", "动态", "投稿", "合集", "收藏"])),
            .init(title: "显示UP主页小店TAB", subtitle: "UP 小店", kind: .toggle),
            .init(title: "设置代理", subtitle: "host:port", kind: .text),
            .init(title: "最大缓存大小", subtitle: "离线缓存上限", kind: .options(["2GB", "8GB", "16GB", "不限制"])),
            .init(title: "检查更新", subtitle: "每次启动时检查是否需要更新", kind: .toggle)
        ],
        "WebDAV 设置": [
            .init(title: "WebDAV 地址", subtitle: "https://example.com/dav", kind: .text),
            .init(title: "用户名", subtitle: "账号", kind: .text),
            .init(title: "密码", subtitle: "不会上传到仓库", kind: .text),
            .init(title: "备份设置", subtitle: "把当前设置写入 WebDAV", kind: .text),
            .init(title: "恢复设置", subtitle: "从 WebDAV 拉回设置", kind: .text)
        ]
    ]

    static let videoMore: [(String, String)] = [
        ("clock.badge.plus", "添加至「稍后再看」"),
        ("note.text", "查看笔记"),
        ("arrow.down.circle", "离线缓存"),
        ("photo", "保存封面"),
        ("timer", "定时关闭"),
        ("link", "播放地址"),
        ("arrow.clockwise", "重载视频"),
        ("sparkles", "超分辨率"),
        ("speaker.wave.2", "播放器音量"),
        ("server.rack", "CDN 设置"),
        ("tv", "选择画质"),
        ("waveform", "选择音质"),
        ("cpu", "解码格式"),
        ("list.number", "播放顺序"),
        ("text.bubble", "弹幕列表"),
        ("slider.horizontal.3", "弹幕设置"),
        ("captions.bubble", "字幕设置"),
        ("text.badge.plus", "加载字幕"),
        ("square.and.arrow.down", "保存字幕"),
        ("info.circle", "播放信息"),
        ("flag", "举报")
    ]

    static let replyMenu = ["回复", "复制", "点赞", "点踩", "分享", "举报", "拉黑", "置顶", "删除", "保存到笔记"]
    static let dynamicMenu = ["转发", "复制动态", "分享", "收藏", "不感兴趣", "举报", "删除", "置顶"]
    static let imageMenu = ["保存图片", "复制图片", "分享", "查看原图"]
    static let shareTargets = ["动态", "消息", "复制链接", "复制 BV 号", "生成海报", "系统分享"]
    static let searchTabs = ["综合", "番剧", "影视", "直播间", "用户", "专栏", "视频"]
    static let videoOrders = [
        ("默认排序", "totalrank"),
        ("播放多", "click"),
        ("新发布", "pubdate"),
        ("弹幕多", "dm"),
        ("收藏多", "stow"),
        ("评论多", "scores")
    ]
    static let durations = [
        ("全部时长", 0),
        ("0-10分钟", 1),
        ("10-30分钟", 2),
        ("30-60分钟", 3),
        ("60分钟+", 4)
    ]
    static let zones: [(String, Int)] = [
        ("全部", 0), ("动画", 1), ("番剧", 13), ("国创", 167), ("音乐", 3), ("舞蹈", 129),
        ("游戏", 4), ("知识", 36), ("科技", 188), ("运动", 234), ("汽车", 223), ("生活", 160),
        ("美食", 221), ("动物", 217), ("鬼畜", 119), ("时尚", 115), ("资讯", 202), ("娱乐", 5),
        ("影视", 181), ("记录", 177), ("电影", 23), ("电视", 11)
    ]
    static let pubTimes = ["不限", "最近一天", "最近一周", "最近半年"]
    static let favTabs = ["视频", "追番", "追剧", "专栏", "笔记", "话题", "课堂"]
    static let laterFilters = ["全部", "未看完", "已看完"]
    static let memberTabs = ["主页", "动态", "投稿", "合集", "收藏", "追番", "课堂", "小店"]
    static let messageTabs = ["回复我的", "@我", "收到的赞", "系统通知"]
    static let liveAreas = ["推荐", "网游", "手游", "单机", "娱乐", "电台", "虚拟主播", "生活", "知识", "赛事"]
    static let pgcTabs = ["追番", "追剧", "时间表", "索引", "入站必刷", "每周必看"]
    static let rankZones = ["全站", "动画", "音乐", "舞蹈", "游戏", "知识", "科技", "生活", "美食", "鬼畜", "时尚", "娱乐", "影视"]

    static let pages: [(group: String, title: String, hint: String, actions: [String])] = [
        ("首页", "推荐", "首页推荐流", ["刷新", "不感兴趣", "查看详情"]),
        ("首页", "热门", "全站热门", ["每周必看", "入站必刷", "排行榜"]),
        ("首页", "分区", "分区排行与入口", ["动画", "音乐", "游戏", "知识", "生活"]),
        ("首页", "番剧", "番剧推荐与时间表", ["追番", "索引", "点评"]),
        ("首页", "影视", "电影与电视剧", ["追剧", "索引"]),
        ("首页", "直播", "直播广场", ["分区", "关注的直播", "搜索直播"]),
        ("动态", "全部动态", "关注的全部动态", ["发布", "话题", "转发"]),
        ("动态", "投稿", "关注 UP 的视频", ["播放", "稍后", "不感兴趣"]),
        ("动态", "番剧动态", "追番更新", ["继续播放", "取消追番"]),
        ("动态", "专栏", "关注的专栏", ["阅读", "收藏", "转发"]),
        ("动态", "发布动态", "图文、投票、预约", ["话题", "提及", "投票", "预约", "表情"]),
        ("动态", "话题", "话题详情与推荐话题", ["关注话题", "发布"]),
        ("视频", "视频详情", "简介、分 P、相关、评论", ["点赞", "点踩", "投币", "收藏", "再看", "分享"]),
        ("视频", "评论", "热度 / 时间、楼中楼", ["回复", "点赞", "举报", "置顶"]),
        ("视频", "弹幕", "弹幕列表与屏蔽", ["点赞弹幕", "复制", "举报", "屏蔽词"]),
        ("视频", "笔记", "视频笔记", ["新建", "编辑", "删除"]),
        ("视频", "离线缓存", "已下载与下载中", ["暂停", "删除", "搜索"]),
        ("视频", "稍后再看", "稍后播放列表", ["全部", "未看完", "已看完", "删除"]),
        ("视频", "投屏", "DLNA 设备", ["搜索设备", "断开"]),
        ("视频", "空降助手", "片头片尾跳过", ["同步 YouTube", "跳过 OP", "跳过 ED"]),
        ("直播", "直播间", "弹幕、醒目留言、榜单", ["发送弹幕", "表情", "醒目留言", "关注", "分享"]),
        ("直播", "贡献榜", "高能榜与大航海", ["日榜", "周榜", "月榜"]),
        ("直播", "直播弹幕屏蔽", "关键词与用户", ["添加", "删除"]),
        ("消息", "私信", "会话列表", ["置顶", "删除", "撤回", "免打扰", "发送图片"]),
        ("消息", "回复我的", "评论回复", ["查看", "回复"]),
        ("消息", "@我", "提到我的", ["查看"]),
        ("消息", "收到的赞", "点赞通知", ["查看"]),
        ("消息", "系统通知", "系统消息", ["查看", "删除"]),
        ("我的", "我的收藏", "视频、追番、专栏、笔记、话题、课堂", ["新建收藏夹", "排序", "搜索", "多选删除"]),
        ("我的", "观看记录", "播放历史", ["搜索", "清空", "删除"]),
        ("我的", "我的订阅", "合集与剧集订阅", ["取消订阅", "搜索"]),
        ("我的", "关注", "关注分组", ["新建分组", "排序", "搜索", "特别关注", "悄悄关注"]),
        ("我的", "粉丝", "粉丝列表", ["移除粉丝", "回关"]),
        ("我的", "黑名单", "已拉黑用户", ["取消拉黑"]),
        ("我的", "我的评论", "发出的评论", ["删除", "置顶"]),
        ("我的", "硬币记录", "硬币流水", ["筛选"]),
        ("我的", "经验记录", "经验流水", ["筛选"]),
        ("我的", "登录设备", "登录中的设备", ["下线"]),
        ("我的", "登录记录", "登录日志", ["查看"]),
        ("我的", "编辑资料", "头像、昵称、签名、性别、生日", ["保存"]),
        ("我的", "空间设置", "空间隐私", ["保存"]),
        ("用户", "用户主页", "主页、动态、投稿、合集、收藏、追番、课堂、小店", ["关注", "私信", "拉黑", "分享"]),
        ("用户", "最近点赞", "用户最近点赞的视频", ["播放"]),
        ("用户", "最近投币", "用户最近投币的视频", ["播放"]),
        ("搜索", "搜索", "综合、番剧、影视、直播、用户、专栏、视频", ["历史", "热搜", "筛选"]),
        ("搜索", "搜索设置", "在设置项里搜索", ["搜索"]),
        ("设置", "关于", "版本、开源说明、日志", ["日志", "检查更新", "复制 buvid"])
    ]
}
