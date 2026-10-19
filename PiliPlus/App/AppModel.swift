import SwiftUI
import AVFoundation

enum Route: Hashable {
    case search
    case video(String)
    case live(Int)
    case settings
    case setting(String)
    case messages
    case notices(String)
    case chat(Int, String)
    case login
    case feature(String)
    case folder(Int)
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
    let downloads = DownloadCenter()
    /// Each tab owns its stack. A single path outside `TabView` cannot host a search-role tab.
    var homePath = NavigationPath()
    var dynamicsPath = NavigationPath()
    var minePath = NavigationPath()
    var searchPath = NavigationPath()
    var toast: String?
    var feed: [VideoItem] = []
    var feedPage = 0
    var feedHasMore = true
    var feedSource = ""
    var loadingMore = false
    var hot: [VideoItem] = []
    var rank: [VideoItem] = []
    var zoneName = "全站"
    var zoneRid = 0
    var zoneFeed: [VideoItem] = []
    var zonePage = 0
    var zoneHasMore = false
    var bangumi: [SeasonItem] = []
    var cinema: [SeasonItem] = []
    var bangumiSchedule: [String: Int] = [:]
    var lives: [LiveRoom] = []
    var liveArea = "推荐"
    var livePage = 0
    var liveHasMore = true
    var loadingLive = false
    var liveError = ""
    var liveOffers: [Int: LiveOffer] = [:]
    private var liveGeneration = 0
    var dynamics: [DynamicItem] = []
    var dynamicOffset = ""
    var dynamicHasMore = false
    var loadingDynamics = false
    var hotwords: [HotWord] = []
    var loadingFeed = false
    var selectedTab = 0
    var homeTab = "推荐"
    var nowPlaying: VideoItem?
    /// True while a video page is the visible screen, so the mini player stays hidden.
    var videoPageVisible = false
    var player: AVPlayer?
    var isPlaying = false
    var playbackSeconds: Double = 0
    var playbackAnchorSeconds: Double = 0
    var playbackAnchorWall: TimeInterval = 0
    var playbackRate: Float = 1
    private var timeObserver: Any?
    private var playGeneration = 0
    var qualityName = "高清 720P"
    var danmakuOn = true
    var offlineTarget: String?
    var offlineAsset = ""
    var offlineDanmaku = 0
    private let softHaptic = UIImpactFeedbackGenerator(style: .soft)
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    var liked: Set<String> = []
    var disliked: Set<String> = []
    var coined: Set<String> = []
    var favored: Set<String> = []
    var later: Set<String> = []
    var loggedIn = false
    var userName = "点击登录"
    var userFace = ""
    var session: BiliSession?
    var anonymity = false
    var theme: ThemeChoice = .system
    var toggles: [String: Bool] = [:]
    var values: [String: String] = [:]
    var homeTabs = ["直播", "推荐", "热门", "分区", "番剧", "影视"]
    var navItems = ["首页", "动态", "我的"]
    var history: [VideoItem] = []
    var historyHasMore = false
    var historyCursorMax = 0
    var historyCursorViewAt = 0
    var historyBusiness = ""
    var historyPaused = false
    var loadingHistory = false
    var laterVideos: [VideoItem] = []
    var loadingLater = false
    var searchHistory: [String] = []
    var favFolders: [FavFolder] = []
    var folderVideos: [Int: [VideoItem]] = [:]
    var folderPage: [Int: Int] = [:]
    var folderHasMore: [Int: Bool] = [:]
    var loadingFolders = false
    var coinCount = 0
    var level = 0
    var exp = 0
    var nextExp = 200
    var following = 0
    var followers = 0
    var dynamicCount = 0
    var unreadReply = 0
    var unreadAt = 0
    var unreadLike = 0
    var unreadSystem = 0

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
        if let stored = KeychainStore.load() {
            SessionVault.shared.install(stored)
            apply(stored)
        } else if loggedIn {
            // Older builds stored a local name without a cookie.
            loggedIn = false
            userName = "点击登录"
            clearProfile()
            save()
        }
        downloads.bind(client)
        switch LaunchMode.screen {
        case "dynamics": selectedTab = 1
        case "guest-dynamics":
            selectedTab = 1
            loggedIn = false
            dynamics = []
        case "search", "search-video", "search-user", "search-bangumi", "search-live", "search-article":
            selectedTab = 3
        case "mine", "history", "later", "fav", "guest-history", "guest-later", "guest-fav", "downloads", "offline":
            selectedTab = 2
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
        history = Array(gallery.videos.prefix(6)).enumerated().map { index, item in
            var copy = item
            copy.progress = index == 0 ? -1 : 48 + index * 20
            copy.viewAt = 1_700_000_000 - index * 120
            return copy
        }
        laterVideos = Array(gallery.videos.dropFirst(6).prefix(5))
        later = Set(laterVideos.map(\.bvid))
        favFolders = [
            FavFolder(id: 11001, title: "默认收藏夹", count: 4, favored: true),
            FavFolder(id: 11002, title: "稍后再看精选", count: 2, favored: false),
            FavFolder(id: 11003, title: "学习", count: 3, favored: false)
        ]
        folderVideos[11001] = Array(gallery.videos.prefix(4))
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
        if key == "后台播放" || key == "后台画中画" { applyBackgroundPolicy() }
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

    func followOwner(mid: Int) async {
        guard requireLogin("关注") else { return }
        show("已关注")
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
        await loadRecommend(reset: true)
        guard !LaunchMode.perfScroll else { return }
        async let popular = client.popular()
        async let rooms = client.liveRooms()
        async let words = client.hotwords()
        if let popular = try? await popular {
            hot = popular
            Task { await ImageStore.shared.prepare(urls: popular.map(\.cover), maxPixel: 560) }
        }
        if let fetched = try? await rooms, liveArea == "推荐", livePage <= 1 {
            lives = fetched
            if !fetched.isEmpty { livePage = 1 }
            liveHasMore = fetched.count >= 8
        }
        hotwords = (try? await words) ?? hotwords
        if zoneFeed.isEmpty { await loadZone(zoneName, reset: true) }
    }

    func loadLive(area: String, reset: Bool) async {
        guard !LaunchMode.perfScroll, !LaunchMode.perfStartup else { return }
        if !reset {
            guard liveHasMore, !loadingLive, liveArea == area else { return }
        }
        liveGeneration += 1
        let generation = liveGeneration
        if reset, area != liveArea {
            lives = []
        }
        liveArea = area
        if reset {
            livePage = 0
            liveHasMore = true
            liveError = ""
        }
        loadingLive = true
        let next = livePage + 1
        do {
            let page = try await client.liveList(area: area, page: next)
            guard generation == liveGeneration else { return }
            if reset {
                lives = page
                liveHasMore = page.count >= 8
            } else {
                let known = Set(lives.map(\.id))
                let fresh = page.filter { !known.contains($0.id) }
                lives.append(contentsOf: fresh)
                liveHasMore = !fresh.isEmpty && page.count >= 8
            }
            livePage = next
            liveError = ""
            loadingLive = false
            Task { await ImageStore.shared.prepare(urls: page.map(\.cover), maxPixel: 560) }
        } catch {
            guard generation == liveGeneration else { return }
            liveError = error.localizedDescription
            loadingLive = false
            if reset { show(error.localizedDescription) }
        }
    }

    func openFirstLive() async {
        let rooms = await busiestLiveRooms()
        if lives.isEmpty {
            lives = rooms
            livePage = rooms.isEmpty ? 0 : 1
            liveHasMore = rooms.count >= 8
        }
        let deadline = Date().addingTimeInterval(100)
        var best: (room: LiveRoom, offer: LiveOffer, count: Int)?
        var seen: Set<Int> = []
        func consider(_ room: LiveRoom) async -> Bool {
            if Date() >= deadline || seen.contains(room.id) { return false }
            guard let offer = try? await client.livePlay(room: room.id, qn: 10_000),
                  offer.protocolName == "hls",
                  URL(string: offer.url) != nil,
                  let info = try? await client.liveDanmuInfo(room: room.id) else { return false }
            seen.insert(room.id)
            let count = await LiveSocket.sample(room: room.id, token: info.token, hosts: info.hosts, seconds: 6)
            print("live probe \(room.id) online \(room.online) danmu \(count)")
            if count > (best?.count ?? -1) {
                best = (room, offer, count)
            }
            return true
        }
        var taken = 0
        for room in rooms {
            if taken >= 4 || Date() >= deadline { break }
            if await consider(room) { taken += 1 }
        }
        if (best?.count ?? 0) == 0 {
            var extra = 0
            for room in rooms where !seen.contains(room.id) {
                if extra >= 2 || Date() >= deadline { break }
                if await consider(room) { extra += 1 }
            }
        }
        if let best {
            liveOffers[best.room.id] = best.offer
            print("live open \(best.room.id) online \(best.room.online) probe \(best.count) \(best.offer.selectedName)")
            open(.live(best.room.id))
            return
        }
        if let first = rooms.first { open(.live(first.id)) }
    }

    /// The busiest room in each area comes first, then the rest by online count.
    private func busiestLiveRooms() async -> [LiveRoom] {
        let areas = ["推荐", "网游", "娱乐", "虚拟主播", "电台"]
        var lists: [[LiveRoom]] = []
        for area in areas {
            lists.append((try? await client.liveList(area: area, page: 1)) ?? [])
        }
        var ordered: [LiveRoom] = []
        var seen: Set<Int> = []
        func push(_ room: LiveRoom) {
            guard seen.insert(room.id).inserted else { return }
            ordered.append(room)
        }
        for list in lists {
            if let room = list.max(by: { $0.online < $1.online }) { push(room) }
        }
        for room in lists.flatMap({ $0 }).sorted(by: { $0.online > $1.online }) { push(room) }
        let preview = ordered.prefix(5).map { "\($0.id):\($0.online)" }.joined(separator: " ")
        print("live candidates \(ordered.count) \(preview)")
        return ordered
    }

    func sendLiveDanmaku(room: Int, message: String) async -> Bool {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        guard let csrf = csrf(for: "发送弹幕") else { return false }
        do {
            try await client.sendLiveDanmaku(room: room, message: text, csrf: csrf)
            show("弹幕已发送")
            return true
        } catch {
            show(error.localizedDescription)
            return false
        }
    }

    func loadDynamics(kind: String, reset: Bool) async {
        if LaunchMode.usesFixtures || LaunchMode.screen == "guest-dynamics" { return }
        guard loggedIn else { return }
        if reset {
            dynamicOffset = ""
            dynamicHasMore = true
        }
        guard dynamicHasMore, !loadingDynamics else { return }
        loadingDynamics = true
        defer { loadingDynamics = false }
        do {
            let page = try await client.followDynamics(type: SocialRequest.dynamicType(for: kind), offset: dynamicOffset)
            if reset {
                dynamics = page.items
            } else {
                let known = Set(dynamics.map(\.id))
                dynamics.append(contentsOf: page.items.filter { !known.contains($0.id) })
            }
            for item in page.items {
                if let video = item.video { store(video) }
            }
            dynamicOffset = page.offset
            dynamicHasMore = page.hasMore
            Task { await ImageStore.shared.prepare(urls: page.items.compactMap { $0.video?.cover }, maxPixel: 560) }
        } catch {
            if reset { show(error.localizedDescription) }
        }
    }

    func followUser(mid: Int, follow: Bool) async -> Bool {
        guard mid > 0 else { return false }
        guard let csrf = csrf(for: follow ? "关注" : "取消关注") else { return false }
        do {
            try await client.submit(SpaceRequest.relation(mid: mid, follow: follow, csrf: csrf))
            show(follow ? "已关注" : "已取消关注")
            return true
        } catch {
            show(error.localizedDescription)
            return false
        }
    }

    func sendComment(aid: Int, message: String, root: Int, parent: Int) async -> Bool {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        guard let csrf = csrf(for: "评论") else { return false }
        do {
            try await client.submit(SocialRequest.replyAdd(oid: aid, message: text, root: root, parent: parent, csrf: csrf))
            show("评论已发送")
            return true
        } catch {
            show(error.localizedDescription)
            return false
        }
    }

    func loadRecommend(reset: Bool) async {
        if !reset {
            guard !LaunchMode.perfScroll, feedHasMore, !loadingMore, !loadingFeed else { return }
        }
        if reset {
            feedPage = 0
            feedHasMore = true
            loadingFeed = true
        } else {
            loadingMore = true
        }
        let next = feedPage + 1
        do {
            let page = try await client.recommend(idx: next)
            if reset {
                feed = page
            } else {
                let known = Set(feed.map(\.bvid))
                feed.append(contentsOf: page.filter { !known.contains($0.bvid) })
            }
            feedPage = next
            feedHasMore = page.count >= 8
            feedSource = "rcmd"
            for item in page { store(item) }
            let covers = (reset ? feed : page).map(\.cover)
            if LaunchMode.perfScroll {
                await ImageStore.shared.prepare(urls: covers, maxPixel: 560)
            } else {
                Task { await ImageStore.shared.prepare(urls: covers, maxPixel: 560) }
            }
        } catch {
            if reset { show(error.localizedDescription) }
            feedSource = feed.isEmpty ? "error" : feedSource
        }
        loadingFeed = false
        loadingMore = false
    }

    /// Moves a one-line title next to a two-line title for the home alignment shot.
    func promoteAlignPair() async -> (short: String, long: String) {
        func real(_ video: VideoItem) -> Bool {
            let title = video.title
            let folded = title.lowercased()
            return video.bvid.hasPrefix("BV")
                && !title.isEmpty
                && !title.contains("液态玻璃")
                && !title.contains("玻璃试验")
                && !folded.contains("fixture")
        }
        for _ in 0..<3 {
            let usable = feed.filter(real)
            if usable.contains(where: { $0.title.count <= 12 }), usable.contains(where: { $0.title.count >= 16 }) {
                break
            }
            await loadRecommend(reset: false)
        }
        let usable = feed.filter(real)
        let short = usable.filter { $0.title.count <= 12 }.min { $0.title.count < $1.title.count }
            ?? usable.min { $0.title.count < $1.title.count }
        let long = usable.filter { $0.title.count >= 16 }.max { $0.title.count < $1.title.count }
            ?? usable.max { $0.title.count < $1.title.count }
        guard let short, let long, short.bvid != long.bvid else {
            return (feed.first?.title ?? "", feed.dropFirst().first?.title ?? "")
        }
        let rest = feed.filter { $0.bvid != short.bvid && $0.bvid != long.bvid }
        feed = [short, long] + rest
        return (short.title, long.title)
    }

    func loadZone(_ name: String, reset: Bool) async {
        if !reset {
            guard zoneHasMore, !loadingMore else { return }
        }
        let rid = Menus.rankRid(name)
        if reset {
            zoneName = name
            zoneRid = rid
            zonePage = 0
            zoneHasMore = rid != 0
            loadingMore = false
        } else {
            loadingMore = true
        }
        let next = zonePage + 1
        do {
            let page: [VideoItem]
            if rid == 0 {
                page = try await client.ranking(rid: 0)
                zoneHasMore = false
            } else if reset {
                page = try await client.region(rid: rid, page: next)
                zoneHasMore = page.count >= 20
            } else {
                page = try await client.region(rid: rid, page: next)
                zoneHasMore = page.count >= 20
            }
            if reset || rid == 0 {
                zoneFeed = page
            } else {
                let known = Set(zoneFeed.map(\.bvid))
                zoneFeed.append(contentsOf: page.filter { !known.contains($0.bvid) })
            }
            zonePage = next
            rank = zoneFeed
            for item in page { store(item) }
        } catch {
            if reset { show(error.localizedDescription) }
        }
        loadingMore = false
    }

    func loadSeasons(_ kind: String) async {
        do {
            if kind == "影视" {
                cinema = try await client.seasons(type: 2)
                Task { await ImageStore.shared.prepare(urls: cinema.map(\.cover), maxPixel: 560) }
                return
            }
            async let shows = client.seasons(type: 1)
            async let schedule = client.bangumiSchedule()
            bangumi = try await shows
            bangumiSchedule = (try? await schedule) ?? bangumiSchedule
            Task { await ImageStore.shared.prepare(urls: bangumi.map(\.cover), maxPixel: 560) }
        } catch {
            show(error.localizedDescription)
        }
    }

    func seasons(for kind: String) -> [SeasonItem] {
        kind == "影视" ? cinema : bangumi
    }

    func dislike(_ video: VideoItem) async {
        feed.removeAll { $0.bvid == video.bvid }
        zoneFeed.removeAll { $0.bvid == video.bvid }
        guard loggedIn, let csrf = session?.csrf, !csrf.isEmpty else {
            show("已减少此类推荐")
            return
        }
        do {
            try await client.dislike(aid: video.aid, csrf: csrf)
            show("已减少此类推荐")
        } catch {
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

    func cacheLimitBytes() -> Int64? {
        switch values["最大缓存大小"] {
        case "2GB": return 2 * 1_024 * 1_024 * 1_024
        case "8GB": return 8 * 1_024 * 1_024 * 1_024
        case "16GB": return 16 * 1_024 * 1_024 * 1_024
        default: return nil
        }
    }

    func playOffline(_ item: OfflineItem) {
        offlineTarget = item.id
        offlineDanmaku = item.danmakuCount
        open(.video(item.bvid))
    }

    func playLocal(_ video: VideoItem, file: URL, audio: URL? = nil) {
        guard !LaunchMode.perfScroll, !LaunchMode.perfStartup else { return }
        nowPlaying = video
        store(video)
        offlineAsset = file.absoluteString
        configurePlaybackSession()
        playGeneration += 1
        let generation = playGeneration
        let rate = playbackRate
        Task {
            let item: AVPlayerItem
            if let audio, FileManager.default.fileExists(atPath: audio.path) {
                item = await StreamComposer.item(videoURL: file, audioURL: audio, headers: [:])
            } else {
                item = AVPlayerItem(asset: AVURLAsset(url: file))
            }
            guard generation == playGeneration else { return }
            if player == nil {
                player = AVPlayer(playerItem: item)
            } else {
                player?.replaceCurrentItem(with: item)
            }
            player?.automaticallyWaitsToMinimizeStalling = false
            await player?.seek(to: .zero)
            guard generation == playGeneration else { return }
            notePlaybackTime(0)
            attachTimeObserver()
            player?.playImmediately(atRate: rate)
            isPlaying = true
            watchPlayback(item, generation: generation, codec: video.streamCodec)
        }
    }

    func play(_ video: VideoItem) {
        guard !LaunchMode.perfScroll, !LaunchMode.perfStartup else { return }
        nowPlaying = video
        store(video)
        guard let urlString = video.playURL, let url = URL(string: urlString) else { return }
        let audioURL = video.audioURL.flatMap(URL.init(string:))
        let headers = BiliHTTP.assetHeaders(bvid: video.bvid)
        configurePlaybackSession()
        playGeneration += 1
        let generation = playGeneration
        let resume = player?.currentTime() ?? .zero
        let shouldPlay = isPlaying || (player == nil && flag("自动播放"))
        let rate = playbackRate
        Task {
            let item = await StreamComposer.item(videoURL: url, audioURL: audioURL, headers: headers)
            guard generation == playGeneration else { return }
            if player == nil {
                player = AVPlayer(playerItem: item)
            } else {
                player?.replaceCurrentItem(with: item)
            }
            applyBackgroundPolicy()
            if let player, resume.isValid, resume.seconds > 0.5 {
                await player.seek(to: resume, toleranceBefore: .zero, toleranceAfter: .zero)
            }
            guard generation == playGeneration else { return }
            notePlaybackTime(resume.isValid ? resume.seconds : 0)
            attachTimeObserver()
            if shouldPlay {
                player?.playImmediately(atRate: rate)
                isPlaying = true
            } else {
                isPlaying = false
            }
            watchPlayback(item, generation: generation, codec: video.streamCodec)
        }
    }

    private func watchPlayback(_ item: AVPlayerItem, generation: Int, codec: String) {
        Task { @MainActor in
            for _ in 0..<24 {
                try? await Task.sleep(for: .milliseconds(500))
                guard generation == playGeneration else { return }
                if item.status == .readyToPlay { return }
                if item.status == .failed {
                    let ns = item.error as NSError?
                    let message = ns.map { "\($0.localizedDescription) \($0.domain) \($0.code)" } ?? "播放失败"
                    if LaunchMode.screen == "offline" { print("offline player \(message)") }
                    PlaybackProof.record(seconds: 0, quality: qualityName, codec: codec, error: message)
                    if LaunchMode.screen == "offline", let offline = downloads.item(offlineTarget ?? "") ?? downloads.latestReady {
                        OfflineProof.playback(item: offline, asset: offlineAsset, seconds: 0, danmaku: offlineDanmaku, error: message)
                    }
                    return
                }
            }
        }
    }

    func openFirstPlayable() async {
        let qn = QualityMap.qn(for: values["默认画质"] ?? "高清 1080P")
        let codec = LaunchMode.playbackCodec(preferred: values["首选解码格式"] ?? "av1")
        let audio = values["默认音质"] ?? "高码率"
        let tryLook = flag("免登录1080P") || qn >= 80
        // The screenshot pass only waits about two minutes. Stop hunting after
        // one slow streak and open a video so the player can still start.
        let deadline = Date().addingTimeInterval(45)
        for item in (feed + rank).prefix(6) where !item.bvid.isEmpty {
            if LaunchMode.screen == "playback", Date() >= deadline { break }
            guard let detail = try? await client.detail(bvid: item.bvid) else { continue }
            let cid = detail.pages.first?.cid ?? detail.cid
            guard cid > 0 else { continue }
            guard let offer = try? await client.playback(
                bvid: detail.bvid,
                cid: cid,
                qn: qn,
                tryLook: tryLook,
                codecPreference: codec,
                audioPreference: audio
            ) else { continue }
            var playable = detail
            playable.apply(offer)
            qualityName = offer.selectedName
            store(playable)
            open(.video(playable.bvid))
            return
        }
        if let first = feed.first { open(.video(first.bvid)) }
    }

    private func configurePlaybackSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
    }

    private func applyBackgroundPolicy() {
        let allow = flag("后台播放") || flag("后台画中画")
        player?.audiovisualBackgroundPlaybackPolicy = allow ? .continuesIfPossible : .pauses
    }

    private func notePlaybackTime(_ seconds: Double) {
        playbackSeconds = seconds
        playbackAnchorSeconds = seconds
        playbackAnchorWall = Date().timeIntervalSinceReferenceDate
        PlaybackProof.record(
            seconds: seconds,
            quality: qualityName,
            codec: nowPlaying?.streamCodec ?? "",
            error: ""
        )
        if LaunchMode.screen == "offline", let item = downloads.item(offlineTarget ?? "") ?? downloads.latestReady {
            OfflineProof.playback(
                item: item,
                asset: offlineAsset,
                seconds: seconds,
                danmaku: offlineDanmaku,
                error: offlineAsset.hasPrefix("file:") ? "" : "播放地址不是本地文件"
            )
        }
    }

    private func attachTimeObserver() {
        guard let player else { return }
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.notePlaybackTime(time.seconds)
            }
        }
    }

    func toggleLike(_ bvid: String) {
        guard let video = video(bvid), video.aid > 0 else { show("还不能点赞"); return }
        guard let csrf = csrf(for: "点赞") else { return }
        let next = !liked.contains(bvid)
        if next { liked.insert(bvid); disliked.remove(bvid) } else { liked.remove(bvid) }
        Task {
            do {
                try await client.submit(AccountRequest.like(aid: video.aid, liked: next, csrf: csrf))
                show(next ? "点赞成功" : "已取消点赞")
            } catch {
                if next { liked.remove(bvid) } else { liked.insert(bvid) }
                show(error.localizedDescription)
            }
        }
    }

    func toggleDislike(_ bvid: String) {
        guard requireLogin("点踩") else { return }
        if disliked.contains(bvid) { disliked.remove(bvid) } else { disliked.insert(bvid); liked.remove(bvid) }
        show(disliked.contains(bvid) ? "已点踩" : "已取消点踩")
    }

    func coin(_ bvid: String, count: Int, alsoLike: Bool) {
        guard let video = video(bvid), video.aid > 0 else { show("还不能投币"); return }
        guard let csrf = csrf(for: "投币") else { return }
        let multiply = count == 2 ? 2 : 1
        Task {
            do {
                try await client.submit(AccountRequest.coin(aid: video.aid, multiply: multiply, alsoLike: alsoLike, csrf: csrf))
                coined.insert(bvid)
                if alsoLike { liked.insert(bvid) }
                let synced = await refreshCoins()
                if !synced { coinCount = max(0, coinCount - multiply) }
                show("投了 \(multiply) 枚硬币")
            } catch {
                show(error.localizedDescription)
            }
        }
    }

    func favoriteQuick(_ video: VideoItem) {
        guard csrf(for: "收藏") != nil else { return }
        Task {
            if favFolders.isEmpty { await loadFolders(rid: video.aid) }
            guard let folder = favFolders.first else {
                show("还没有收藏夹")
                return
            }
            if favored.contains(video.bvid) {
                await dealFavorite(video, add: [], remove: [folder.id])
            } else {
                await dealFavorite(video, add: [folder.id], remove: [])
            }
        }
    }

    func dealFavorite(_ video: VideoItem, add: [Int], remove: [Int]) async {
        guard video.aid > 0 else { show("还不能收藏"); return }
        guard !add.isEmpty || !remove.isEmpty else { return }
        if LaunchMode.accountPreview {
            if !add.isEmpty { favored.insert(video.bvid) }
            if add.isEmpty { favored.remove(video.bvid) }
            show(add.isEmpty ? "已移出收藏" : "已加入收藏")
            return
        }
        guard let csrf = csrf(for: "收藏") else { return }
        do {
            try await client.submit(AccountRequest.dealFavorite(aid: video.aid, add: add, remove: remove, csrf: csrf))
            if !add.isEmpty { favored.insert(video.bvid) }
            if add.isEmpty, !remove.isEmpty { favored.remove(video.bvid) }
            for id in add {
                if let index = favFolders.firstIndex(where: { $0.id == id }) { favFolders[index].favored = true }
            }
            for id in remove {
                if let index = favFolders.firstIndex(where: { $0.id == id }) { favFolders[index].favored = false }
                folderVideos[id]?.removeAll { $0.bvid == video.bvid }
            }
            show(add.isEmpty ? "已移出收藏" : "已更新收藏")
        } catch {
            show(error.localizedDescription)
        }
    }

    func createFolder(_ title: String) async {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if LaunchMode.accountPreview {
            let next = (favFolders.map(\.id).max() ?? 11000) + 1
            favFolders.append(FavFolder(id: next, title: name, count: 0, favored: false))
            show("已新建收藏夹")
            return
        }
        guard let csrf = csrf(for: "新建收藏夹") else { return }
        do {
            _ = try await client.submit(AccountRequest.createFolder(title: name, csrf: csrf))
            show("已新建收藏夹")
            await loadFolders(rid: nil)
        } catch {
            show(error.localizedDescription)
        }
    }

    func watchLater(_ bvid: String) {
        guard let video = video(bvid), video.aid > 0 else { show("还不能加入稍后再看"); return }
        if later.contains(bvid) {
            Task { await removeLater(video) }
        } else {
            guard let csrf = csrf(for: "添加稍后再看") else { return }
            Task {
                do {
                    try await client.submit(AccountRequest.addWatchLater(aid: video.aid, csrf: csrf))
                    later.insert(bvid)
                    if !laterVideos.contains(where: { $0.bvid == bvid }) {
                        laterVideos.insert(video, at: 0)
                    }
                    show("已添加至稍后再看")
                } catch {
                    show(error.localizedDescription)
                }
            }
        }
    }

    func removeLater(_ video: VideoItem) async {
        if LaunchMode.accountPreview {
            later.remove(video.bvid)
            laterVideos.removeAll { $0.bvid == video.bvid }
            return
        }
        guard let csrf = csrf(for: "移出稍后再看") else { return }
        do {
            try await client.submit(AccountRequest.removeWatchLater(aid: video.aid, csrf: csrf))
            later.remove(video.bvid)
            laterVideos.removeAll { $0.bvid == video.bvid }
            show("已移出稍后再看")
        } catch {
            show(error.localizedDescription)
        }
    }

    func clearLater() async {
        if LaunchMode.accountPreview {
            later.removeAll()
            laterVideos.removeAll()
            return
        }
        guard let csrf = csrf(for: "清空稍后再看") else { return }
        do {
            try await client.submit(AccountRequest.clearWatchLater(csrf: csrf))
            later.removeAll()
            laterVideos.removeAll()
            show("已清空稍后再看")
        } catch {
            show(error.localizedDescription)
        }
    }

    func triple(_ bvid: String) {
        guard let video = video(bvid), video.aid > 0 else { show("还不能三连"); return }
        guard let csrf = csrf(for: "一键三连") else { return }
        Task {
            do {
                let data = try await client.submit(AccountRequest.triple(aid: video.aid, csrf: csrf))
                let likedOK = data["data"]["like"].bool ?? true
                let coinedOK = data["data"]["coin"].bool ?? true
                let favOK = data["data"]["fav"].bool ?? true
                if likedOK { liked.insert(bvid) }
                if coinedOK { coined.insert(bvid) }
                if favOK { favored.insert(bvid) }
                if coinedOK { await refreshCoins() }
                show("三连成功")
            } catch {
                show(error.localizedDescription)
            }
        }
    }

    func loadHistory(reset: Bool) async {
        if LaunchMode.accountPreview { return }
        guard loggedIn else { return }
        if reset {
            historyCursorMax = 0
            historyCursorViewAt = 0
            historyBusiness = ""
            historyHasMore = true
        }
        guard historyHasMore, !loadingHistory else { return }
        loadingHistory = true
        defer { loadingHistory = false }
        do {
            let page = try await client.history(max: historyCursorMax, viewAt: historyCursorViewAt, business: historyBusiness)
            if reset {
                history = page.items
            } else {
                let known = Set(history.map(\.bvid))
                history.append(contentsOf: page.items.filter { !known.contains($0.bvid) })
            }
            for item in page.items { store(item) }
            historyCursorMax = page.max
            historyCursorViewAt = page.viewAt
            historyBusiness = page.business
            historyHasMore = !page.items.isEmpty && page.items.count >= 20 && page.max > 0
            Task { await ImageStore.shared.prepare(urls: page.items.map(\.cover), maxPixel: 320) }
        } catch {
            if reset { show(error.localizedDescription) }
        }
    }

    func deleteHistory(_ video: VideoItem) async {
        if LaunchMode.accountPreview {
            history.removeAll { $0.bvid == video.bvid }
            return
        }
        guard video.aid > 0, let csrf = csrf(for: "删除记录") else { return }
        do {
            try await client.submit(AccountRequest.deleteHistory(aid: video.aid, csrf: csrf))
            history.removeAll { $0.bvid == video.bvid }
        } catch {
            show(error.localizedDescription)
        }
    }

    func clearHistory() async {
        if LaunchMode.accountPreview {
            history.removeAll()
            return
        }
        guard let csrf = csrf(for: "清空观看记录") else { return }
        do {
            try await client.submit(AccountRequest.clearHistory(csrf: csrf))
            history.removeAll()
            historyHasMore = false
            show("已清空观看记录")
        } catch {
            show(error.localizedDescription)
        }
    }

    func loadHistoryPause() async {
        if LaunchMode.accountPreview || !loggedIn { return }
        historyPaused = (try? await client.historyPaused()) ?? historyPaused
    }

    func setHistoryPaused(_ paused: Bool) async {
        if LaunchMode.accountPreview {
            historyPaused = paused
            show(paused ? "已暂停记录观看历史" : "已继续记录观看历史")
            return
        }
        guard let csrf = csrf(for: "暂停记录") else { return }
        do {
            try await client.submit(AccountRequest.pauseHistory(paused: paused, csrf: csrf))
            historyPaused = paused
            show(paused ? "已暂停记录观看历史" : "已继续记录观看历史")
        } catch {
            show(error.localizedDescription)
        }
    }

    func loadLater() async {
        if LaunchMode.accountPreview || !loggedIn { return }
        guard !loadingLater else { return }
        loadingLater = true
        defer { loadingLater = false }
        do {
            let page = try await client.watchLater()
            laterVideos = page
            later = Set(page.map(\.bvid))
            for item in page { store(item) }
            Task { await ImageStore.shared.prepare(urls: page.map(\.cover), maxPixel: 320) }
        } catch {
            show(error.localizedDescription)
        }
    }

    func loadFolders(rid: Int?) async {
        if LaunchMode.accountPreview || !loggedIn { return }
        guard !loadingFolders, let mid = session?.mid, mid > 0 else { return }
        loadingFolders = true
        defer { loadingFolders = false }
        do {
            favFolders = try await client.folders(mid: mid, rid: rid)
        } catch {
            show(error.localizedDescription)
        }
    }

    func loadFolder(_ id: Int, reset: Bool) async {
        if LaunchMode.accountPreview || !loggedIn { return }
        if !reset, folderHasMore[id] == false { return }
        let next = reset ? 1 : (folderPage[id] ?? 0) + 1
        do {
            let page = try await client.folderVideos(mediaID: id, page: next)
            if reset || folderVideos[id] == nil {
                folderVideos[id] = page.items
            } else {
                let known = Set((folderVideos[id] ?? []).map(\.bvid))
                folderVideos[id, default: []].append(contentsOf: page.items.filter { !known.contains($0.bvid) })
            }
            folderPage[id] = next
            folderHasMore[id] = page.hasMore
            for item in page.items { store(item) }
            Task { await ImageStore.shared.prepare(urls: page.items.map(\.cover), maxPixel: 320) }
        } catch {
            if reset { show(error.localizedDescription) }
        }
    }

    private func csrf(for action: String) -> String? {
        guard requireLogin(action) else { return nil }
        guard let csrf = session?.csrf, !csrf.isEmpty else {
            show("登录状态缺少 bili_jct")
            return nil
        }
        return csrf
    }

    private func refreshCoins() async -> Bool {
        guard let header = session?.cookieHeader else { return false }
        guard let nav = try? await client.nav(cookieHeader: header) else { return false }
        coinCount = nav.coins
        if var stored = session {
            stored.coins = nav.coins
            session = stored
            SessionVault.shared.replace(stored)
        }
        return true
    }

    func apply(_ stored: BiliSession) {
        session = stored
        loggedIn = stored.hasLoginCookie
        userName = stored.name.isEmpty ? "已登录" : stored.name
        userFace = stored.face
        level = stored.level
        coinCount = stored.coins
        exp = stored.exp
        nextExp = max(stored.nextExp, 1)
        following = stored.following
        followers = stored.followers
        dynamicCount = stored.dynamicCount
    }

    func clearProfile() {
        session = nil
        userFace = ""
        level = 0
        coinCount = 0
        exp = 0
        nextExp = 200
        following = 0
        followers = 0
        dynamicCount = 0
    }

    /// Saves cookies, then replaces the placeholder profile with `nav` and `nav/stat`.
    func adopt(_ incoming: BiliSession) async {
        var stored = incoming
        let header = stored.cookieHeader
        do {
            let nav = try await client.nav(cookieHeader: header)
            guard nav.isLogin else {
                show("登录未通过，请检查 SESSDATA 和 bili_jct")
                return
            }
            stored.mid = nav.mid == 0 ? stored.mid : nav.mid
            stored.name = nav.name
            stored.face = nav.face
            stored.level = nav.level
            stored.exp = nav.exp
            stored.nextExp = nav.nextExp
            stored.coins = nav.coins
            SessionVault.shared.install(stored)
            if let stat = try? await client.navStat() {
                stored.following = stat.following
                stored.followers = stat.followers
                stored.dynamicCount = stat.dynamicCount
            }
            SessionVault.shared.replace(stored)
            apply(stored)
            save()
            show("已登录 \(userName)")
        } catch {
            SessionVault.shared.replace(stored)
            apply(stored)
            save()
            show("已保存登录，资料稍后同步")
        }
    }

    func refreshProfile() async {
        guard loggedIn else {
            await client.refreshMixinKey()
            return
        }
        guard let header = session?.cookieHeader else { return }
        do {
            let nav = try await client.nav(cookieHeader: header)
            guard nav.isLogin else {
                logout(remote: false, announce: false)
                show("登录已失效")
                return
            }
            var stored = session ?? BiliSession.make(cookies: [:], mid: nav.mid)
            stored.mid = nav.mid
            stored.name = nav.name
            stored.face = nav.face
            stored.level = nav.level
            stored.exp = nav.exp
            stored.nextExp = nav.nextExp
            stored.coins = nav.coins
            SessionVault.shared.install(stored)
            if let stat = try? await client.navStat() {
                stored.following = stat.following
                stored.followers = stat.followers
                stored.dynamicCount = stat.dynamicCount
            }
            SessionVault.shared.replace(stored)
            apply(stored)
            save()
        } catch {
            // Keep the keychain profile when the network is down.
        }
    }

    func logout(remote: Bool = true, announce: Bool = true) {
        let csrf = session?.csrf ?? ""
        let header = session?.cookieHeader ?? ""
        SessionVault.shared.replace(nil)
        clearProfile()
        loggedIn = false
        userName = "点击登录"
        anonymity = false
        save()
        if announce { show("已退出登录") }
        if remote, !csrf.isEmpty {
            Task { await client.logout(csrf: csrf, cookieHeader: header) }
        }
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
