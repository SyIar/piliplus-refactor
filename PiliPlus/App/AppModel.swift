import SwiftUI
import AVFoundation

enum Route: Hashable {
    case search
    case video(String)
    case live(Int)
    case settings
    case setting(String)
    case messages
    case login
    case feature(String)
    case user(Int, String)
}

enum ThemeChoice: String, CaseIterable, Identifiable {
    case system, light, dark, black
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        case .black: "纯黑"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    let client = BiliClient()
    /// Each tab owns its stack. A single path outside `TabView` cannot host a search-role tab.
    var homePath = NavigationPath()
    var dynamicsPath = NavigationPath()
    var minePath = NavigationPath()
    var searchPath = NavigationPath()
    var toast: String?
    var feed: [VideoItem] = []
    var hot: [VideoItem] = []
    var rank: [VideoItem] = []
    var lives: [LiveRoom] = []
    var dynamics: [DynamicItem] = []
    var hotwords: [HotWord] = []
    var loadingFeed = false
    var selectedTab = 0
    var homeTab = "推荐"
    var nowPlaying: VideoItem?
    var player: AVPlayer?
    var isPlaying = false
    var playbackSeconds: Double = 0
    var playbackRate: Float = 1
    private var timeObserver: Any?
    var qualityName = "高清 720P"
    var danmakuOn = true
    private let softHaptic = UIImpactFeedbackGenerator(style: .soft)
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    var liked: Set<String> = []
    var disliked: Set<String> = []
    var coined: Set<String> = []
    var favored: Set<String> = []
    var later: Set<String> = []
    var loggedIn = false
    var userName = "点击登录"
    var anonymity = false
    var theme: ThemeChoice = .system
    var toggles: [String: Bool] = [:]
    var values: [String: String] = [:]
    var homeTabs = ["直播", "推荐", "热门", "分区", "番剧", "影视"]
    var navItems = ["首页", "动态", "我的"]
    var history: [VideoItem] = []
    var searchHistory: [String] = []
    var favFolders = ["默认收藏夹", "稍后再看精选", "学习"]
    var coinCount = 0
    var level = 0
    var exp = 0
    var nextExp = 200
    var following = 0
    var followers = 0
    var dynamicCount = 0
    var unreadReply = 2
    var unreadAt = 1
    var unreadLike = 3

    var colorScheme: ColorScheme? {
        switch theme {
        case .system: nil
        case .light: .light
        case .dark, .black: .dark
        }
    }

    init() {
        load()
        if toggles.isEmpty { seedDefaults() }
        switch LaunchMode.screen {
        case "dynamics": selectedTab = 1
        case "mine": selectedTab = 2
        default: break
        }
        softHaptic.prepare()
        lightHaptic.prepare()
    }

    func applyFixtures() {
        let gallery = FixtureGallery.make()
        feed = gallery.videos
        hot = gallery.videos
        rank = Array(gallery.videos.reversed())
        lives = gallery.lives
        hotwords = gallery.words
        dynamics = gallery.dynamics
        history = Array(gallery.videos.prefix(4))
        for item in gallery.videos { store(item) }
        loadingFeed = false
        let covers = gallery.videos.map(\.cover)
        Task { await ImageStore.shared.prepare(urls: covers, maxPixel: 560) }
    }

    func seedDefaults() {
        let on = [
            "弹幕开关", "启用点击弹幕", "自动播放", "双击快退/快进", "左右侧滑动调节亮度/音量",
            "调节系统亮度", "中间滑动进入/退出全屏", "自动启用字幕", "全屏显示锁定按钮",
            "全屏显示截图按钮", "观看人数", "后台播放", "开启硬解", "免登录1080P",
            "显示视频评论", "显示番剧评论", "视频页显示相关视频", "显示视频分段信息",
            "显示高能进度条", "搜索建议", "记录搜索历史", "大家都在搜", "搜索发现",
            "搜索默认词", "震动反馈", "检查更新", "显示会员彩色弹幕", "启用AI总结",
            "动态未读标记", "消息未读标记", "首页顶栏收起", "悬浮底栏", "展示追番时间表",
            "显示热门推荐", "评论区搜索关键词", "展示头像/评论/动态装饰", "显示粉丝勋章",
            "滑动跳转预览视频缩略图", "记录评论", "发评反诈", "侧滑关闭二级页面",
            "动态页显示所有已关注UP主", "动态页展开正在直播UP列表", "预览 Live Photo"
        ]
        for key in on { toggles[key] = true }
        values["默认画质"] = "高清 1080P"
        values["蜂窝网络画质"] = "高清 720P"
        values["默认音质"] = "高码率"
        values["默认倍速"] = "1.0x"
        values["默认长按倍速"] = "2.0x"
        values["播放顺序"] = "自动连播"
        values["主题模式"] = "跟随系统"
        values["默认全屏方向"] = "不改变当前方向"
        values["底部进度条展示"] = "常驻"
        values["图片质量"] = "80%"
        values["用户页默认展示TAB"] = "投稿"
        values["首页标签页"] = homeTabs.joined(separator: " / ")
        values["默认启动页"] = "首页"
        values["评论展示"] = "按热度"
        values["动态展示"] = "全部"
        values["字幕选择偏好"] = "自动"
        values["首选解码格式"] = "av1"
        values["硬解模式"] = "auto"
        values["番剧片头/片尾跳过类型"] = "始终跳过"
        values["SuperChat (醒目留言) 显示类型"] = "滚动"
    }

    func flag(_ key: String) -> Bool { toggles[key] ?? false }

    func setFlag(_ key: String, _ value: Bool) {
        toggles[key] = value
        if key == "弹幕开关" { danmakuOn = value }
        save()
        if flag("震动反馈") {
            lightHaptic.impactOccurred()
        }
    }

    func open(_ route: Route) {
        if case .search = route {
            selectedTab = 3
            return
        }
        switch selectedTab {
        case 1: dynamicsPath.append(route)
        case 2: minePath.append(route)
        case 3: searchPath.append(route)
        default: homePath.append(route)
        }
    }

    func pop() {
        switch selectedTab {
        case 1: if !dynamicsPath.isEmpty { dynamicsPath.removeLast() }
        case 2: if !minePath.isEmpty { minePath.removeLast() }
        case 3: if !searchPath.isEmpty { searchPath.removeLast() }
        default: if !homePath.isEmpty { homePath.removeLast() }
        }
    }

    func show(_ text: String) {
        toast = text
        if flag("震动反馈") {
            softHaptic.impactOccurred()
        }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if toast == text { toast = nil }
        }
    }

    func requireLogin(_ action: String) -> Bool {
        guard loggedIn else {
            show("请先登录后再\(action)")
            open(.login)
            return false
        }
        return true
    }

    func refreshHome() async {
        loadingFeed = true
        do {
            let popular = try await client.popular()
            feed = popular
            hot = popular
            loadingFeed = false
            Task { await ImageStore.shared.prepare(urls: popular.map(\.cover), maxPixel: 560) }
            await Task.yield()
            async let ranking = client.ranking()
            async let rooms = client.liveRooms()
            async let words = client.hotwords()
            rank = (try? await ranking) ?? rank
            lives = (try? await rooms) ?? lives
            hotwords = (try? await words) ?? hotwords
            dynamics = BiliClient.dynamics(from: popular)
            for item in feed + rank { store(item) }
        } catch {
            loadingFeed = false
            show(error.localizedDescription)
        }
    }

    func remember(_ video: VideoItem) {
        // cache lives in a side dictionary via history uniqueness of latest copies
    }

    private var cache: [String: VideoItem] = [:]

    func store(_ video: VideoItem) {
        cache[video.bvid] = video
    }

    func video(_ bvid: String) -> VideoItem? {
        cache[bvid] ?? feed.first { $0.bvid == bvid } ?? rank.first { $0.bvid == bvid } ?? hot.first { $0.bvid == bvid }
    }

    func play(_ video: VideoItem) {
        nowPlaying = video
        store(video)
        if !history.contains(where: { $0.bvid == video.bvid }) {
            history.insert(video, at: 0)
        }
        guard let urlString = video.playURL, let url = URL(string: urlString) else { return }
        let headers = [
            "Referer": "https://www.bilibili.com/video/\(video.bvid)",
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 27_0 like Mac OS X) AppleWebKit/605.1.15"
        ]
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        if player == nil {
            player = AVPlayer(playerItem: item)
        } else {
            player?.replaceCurrentItem(with: item)
        }
        if flag("自动播放") {
            player?.play()
            isPlaying = true
        }
        player?.rate = playbackRate
        if let player {
            if let timeObserver { player.removeTimeObserver(timeObserver) }
            let interval = CMTime(seconds: 0.4, preferredTimescale: 600)
            timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                Task { @MainActor in
                    self?.playbackSeconds = time.seconds
                }
            }
        }
    }

    func toggleLike(_ bvid: String) {
        guard requireLogin("点赞") else { return }
        if liked.contains(bvid) { liked.remove(bvid); show("已取消点赞") }
        else { liked.insert(bvid); disliked.remove(bvid); show("点赞成功") }
    }

    func toggleDislike(_ bvid: String) {
        guard requireLogin("点踩") else { return }
        if disliked.contains(bvid) { disliked.remove(bvid) } else { disliked.insert(bvid); liked.remove(bvid) }
        show(disliked.contains(bvid) ? "已点踩" : "已取消点踩")
    }

    func coin(_ bvid: String, count: Int, alsoLike: Bool) {
        guard requireLogin("投币") else { return }
        coined.insert(bvid)
        coinCount = max(0, coinCount - count)
        if alsoLike { liked.insert(bvid) }
        show("投了 \(count) 枚硬币")
    }

    func favorite(_ bvid: String, folder: String) {
        guard requireLogin("收藏") else { return }
        favored.insert(bvid)
        show("已加入「\(folder)」")
    }

    func watchLater(_ bvid: String) {
        guard requireLogin("添加稍后再看") else { return }
        if later.contains(bvid) { later.remove(bvid); show("已移出稍后再看") }
        else { later.insert(bvid); show("已添加至稍后再看") }
    }

    func triple(_ bvid: String) {
        guard requireLogin("一键三连") else { return }
        liked.insert(bvid)
        coined.insert(bvid)
        favored.insert(bvid)
        show("三连成功")
    }

    func login(as name: String) {
        loggedIn = true
        userName = name
        level = 4
        coinCount = 286
        exp = 8420
        nextExp = 10800
        following = 128
        followers = 36
        dynamicCount = 12
        show("已登录 \(name)")
        save()
    }

    func logout() {
        loggedIn = false
        userName = "点击登录"
        anonymity = false
        show("已退出登录")
        save()
    }

    private let defaultsKey = "piliplus.settings.v1"

    func save() {
        let payload: [String: Any] = [
            "toggles": toggles,
            "values": values,
            "theme": theme.rawValue,
            "loggedIn": loggedIn,
            "userName": userName,
            "homeTabs": homeTabs,
            "navItems": navItems,
            "searchHistory": searchHistory,
            "anonymity": anonymity
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        toggles = object["toggles"] as? [String: Bool] ?? [:]
        values = object["values"] as? [String: String] ?? [:]
        if let raw = object["theme"] as? String, let choice = ThemeChoice(rawValue: raw) { theme = choice }
        loggedIn = object["loggedIn"] as? Bool ?? false
        userName = object["userName"] as? String ?? "点击登录"
        homeTabs = object["homeTabs"] as? [String] ?? homeTabs
        navItems = object["navItems"] as? [String] ?? navItems
        searchHistory = object["searchHistory"] as? [String] ?? []
        anonymity = object["anonymity"] as? Bool ?? false
        danmakuOn = flag("弹幕开关") || toggles["弹幕开关"] == nil
    }
}
