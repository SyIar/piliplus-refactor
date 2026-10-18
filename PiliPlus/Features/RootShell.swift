import SwiftUI

struct RootShell: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("首页", systemImage: "house.fill", value: 0) {
                NavigationStack(path: $model.homePath) {
                    HomeFeed()
                        .navigationDestination(for: Route.self) { destination($0) }
                }
            }
            Tab("动态", systemImage: "dot.radiowaves.left.and.right", value: 1) {
                NavigationStack(path: $model.dynamicsPath) {
                    Group {
                        if model.selectedTab == 1 {
                            DynamicsFeed()
                        } else {
                            Color.clear
                        }
                    }
                    .navigationDestination(for: Route.self) { destination($0) }
                }
            }
            .badge(model.flag("动态未读标记") ? 1 : 0)
            Tab("我的", systemImage: "person.fill", value: 2) {
                NavigationStack(path: $model.minePath) {
                    Group {
                        if model.selectedTab == 2 {
                            MineSpace()
                        } else {
                            Color.clear
                        }
                    }
                    .navigationDestination(for: Route.self) { destination($0) }
                }
            }
            Tab("搜索", systemImage: "magnifyingglass", value: 3, role: .search) {
                NavigationStack(path: $model.searchPath) {
                    SearchStudio()
                        .navigationDestination(for: Route.self) { destination($0) }
                }
            }
        }
        .tabBarMinimizeBehavior(model.flag("首页底栏收起") ? .onScrollDown : .never)
        .tabViewBottomAccessory(isEnabled: model.nowPlaying != nil && !model.videoPageVisible) {
            if let video = model.nowPlaying {
                NowPlayingPill(video: video)
            }
        }
        .overlay(alignment: .top) {
            if let toast = model.toast {
                ToastBanner(text: toast)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: model.toast)
        .task { await boot() }
    }

    private func boot() async {
        if LaunchMode.perfStartup { return }
        if LaunchMode.screen == "accountProof" {
            AccountRequestProof.writeAndExit()
        }
        if LaunchMode.screen == "socialProof" {
            SocialRequestProof.writeAndExit()
        }
        if LaunchMode.screen == "spaceProof" {
            SpaceRequestProof.writeAndExit()
        }
        if LaunchMode.screen == "liveProof" {
            LiveRequestProof.writeAndExit()
        }
        if LaunchMode.screen == "messageProof" {
            MessageRequestProof.writeAndExit()
        }
        if LaunchMode.screen == "playbackExtra" {
            PlaybackRequestProof.writeAndExit()
        }
        if LaunchMode.screen == "guest-messages" || LaunchMode.screen == "messages" {
            await LaunchClock.waitForFirstFrame()
            if LaunchMode.screen == "guest-messages" { model.loggedIn = false }
            model.open(.messages)
            return
        }
        if LaunchMode.screen == "guest-chat" {
            await LaunchClock.waitForFirstFrame()
            model.loggedIn = false
            model.open(.chat(0, "私信"))
            return
        }
        if LaunchMode.screen == "guest-dynamics" {
            await LaunchClock.waitForFirstFrame()
            model.loggedIn = false
            model.dynamics = []
            model.selectedTab = 1
            SocialUIProof.record(["prompt": true, "rows": 0, "error": ""])
            return
        }
        if let screen = LaunchMode.screen, screen.hasPrefix("guest-") {
            await LaunchClock.waitForFirstFrame()
            model.loggedIn = false
            model.history = []
            model.laterVideos = []
            model.later = []
            model.favFolders = []
            model.selectedTab = 2
            switch screen {
            case "guest-later": model.open(.feature("稍后再看"))
            case "guest-fav": model.open(.feature("我的收藏"))
            default: model.open(.feature("观看记录"))
            }
            return
        }
        if LaunchMode.perfScroll {
            await LaunchClock.waitForFirstFrame()
            await model.loadRecommend(reset: true)
            return
        }
        if LaunchMode.usesFixtures {
            await LaunchClock.waitForFirstFrame()
            model.applyFixtures()
            switch LaunchMode.screen {
            case "search": model.open(.search)
            case "settings": model.open(.settings)
            case "login": model.open(.login)
            case "video", "favsheet":
                if let first = model.feed.first { model.open(.video(first.bvid)) }
            case "history":
                model.selectedTab = 2
                model.open(.feature("观看记录"))
            case "later":
                model.selectedTab = 2
                model.open(.feature("稍后再看"))
            case "fav":
                model.selectedTab = 2
                model.open(.feature("我的收藏"))
            case "dynamics":
                SocialUIProof.record(["prompt": false, "rows": model.dynamics.count, "error": ""])
            default:
                break
            }
            return
        }
        if LaunchMode.screen == "space" || LaunchMode.screen?.hasPrefix("space-") == true {
            await LaunchClock.waitForFirstFrame()
            await openSampleSpace()
            return
        }
        if LaunchMode.searchCapture != nil {
            model.selectedTab = 3
            return
        }
        if LaunchMode.screen == "comments" {
            if model.feed.isEmpty { await model.loadRecommend(reset: true) }
            let pick = model.feed.first { $0.reply > 0 } ?? model.feed.first
            if let pick {
                model.store(pick)
                model.open(.video(pick.bvid))
            }
            return
        }
        if LaunchMode.screen == "playback" {
            if model.feed.isEmpty { await model.loadRecommend(reset: true) }
            await model.openFirstPlayable()
            return
        }
        if LaunchMode.screen == "resume" {
            await LaunchClock.waitForFirstFrame()
            await model.openResumeSample()
            return
        }
        if LaunchMode.screen == "autoplay" {
            await LaunchClock.waitForFirstFrame()
            await model.openAutoplaySample()
            return
        }
        if LaunchMode.screen == "bangumi-play" {
            await LaunchClock.waitForFirstFrame()
            await model.openBangumiPlayback()
            return
        }
        if LaunchMode.screen == "chapters" {
            await LaunchClock.waitForFirstFrame()
            await model.openChapterSample()
            return
        }
        if LaunchMode.screen == "scrub" {
            await LaunchClock.waitForFirstFrame()
            await model.openScrubSample()
            return
        }
        if LaunchMode.screen == "sleep" {
            await LaunchClock.waitForFirstFrame()
            model.loggedIn = false
            await model.openSleepSample()
            return
        }
        if LaunchMode.screen == "live" || LaunchMode.screen == "live-area" {
            await LaunchClock.waitForFirstFrame()
            model.homeTab = "直播"
            let area = LaunchMode.screen == "live-area" ? "网游" : "推荐"
            await model.loadLive(area: area, reset: true)
            let deadline = Date().addingTimeInterval(45)
            while model.loadingLive, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(200))
            }
            LiveUIProof.record([
                "area": model.liveArea,
                "count": model.lives.count,
                "title": model.lives.first?.title ?? "",
                "room": model.lives.first?.id ?? 0,
                "uname": model.lives.first?.uname ?? "",
                "error": model.lives.isEmpty ? (model.liveError.isEmpty ? "empty" : model.liveError) : ""
            ])
            return
        }
        if LaunchMode.screen == "live-room" {
            await LaunchClock.waitForFirstFrame()
            model.homeTab = "直播"
            await model.openFirstLive()
            return
        }
        if LaunchMode.screen == "sponsor" {
            await LaunchClock.waitForFirstFrame()
            await openSponsorVideo()
            return
        }
        if LaunchMode.screen == "sponsor-settings" {
            await LaunchClock.waitForFirstFrame()
            model.open(.settings)
            model.open(.setting("空降助手"))
            return
        }
        if LaunchMode.screen == "downloads" {
            await LaunchClock.waitForFirstFrame()
            model.selectedTab = 2
            model.open(.feature("离线缓存"))
            return
        }
        if LaunchMode.screen == "offline" {
            await LaunchClock.waitForFirstFrame()
            OfflineFirewall.install()
            model.selectedTab = 2
            if let item = model.downloads.latestReady {
                model.offlineTarget = item.id
                model.open(.video(item.bvid))
            }
            return
        }
        if model.feed.isEmpty { await model.refreshHome() }
        await model.refreshProfile()
        switch LaunchMode.screen {
        case "home":
            let firstCount = model.feed.count
            await model.loadRecommend(reset: false)
            let pair = await model.promoteAlignPair()
            try? await Task.sleep(for: .milliseconds(500))
            HomeProof.record([
                "source": model.feedSource,
                "page": model.feedPage,
                "count": model.feed.count,
                "firstCount": firstCount,
                "title": model.feed.first?.title ?? "",
                "bvid": model.feed.first?.bvid ?? "",
                "short": pair.short,
                "long": pair.long
            ])
        case "rank":
            model.homeTab = "分区"
            await model.loadZone("动画", reset: true)
            HomeProof.record([
                "zone": model.zoneName,
                "rid": model.zoneRid,
                "count": model.zoneFeed.count,
                "title": model.zoneFeed.first?.title ?? "",
                "bvid": model.zoneFeed.first?.bvid ?? ""
            ])
        case "bangumi":
            model.homeTab = "番剧"
            await model.loadSeasons("番剧")
            HomeProof.record([
                "count": model.bangumi.count,
                "title": model.bangumi.first?.title ?? "",
                "seasonID": model.bangumi.first?.seasonID ?? 0,
                "friday": model.bangumiSchedule["五"] ?? 0
            ])
        case "cinema":
            model.homeTab = "影视"
            await model.loadSeasons("影视")
            HomeProof.record([
                "count": model.cinema.count,
                "title": model.cinema.first?.title ?? "",
                "seasonID": model.cinema.first?.seasonID ?? 0
            ])
        default:
            break
        }
    }

    private func openSponsorVideo() async {
        for bvid in SponsorCatalog.proofCandidates {
            let page = await SponsorClient.segments(for: bvid)
            guard !page.items.isEmpty else { continue }
            guard (try? await model.client.detail(bvid: bvid)) != nil else { continue }
            print("sponsor open \(bvid) \(page.server) \(page.items.count)")
            model.open(.video(bvid))
            return
        }
        SponsorProof.record([
            "bvid": "",
            "title": "",
            "prefix": "",
            "server": "",
            "count": 0,
            "category": "",
            "start": 0,
            "end": 0,
            "skipped": false,
            "toast": "",
            "error": "没有找到带片段的视频"
        ])
    }

    private func openSampleSpace() async {
        do {
            let page = try await model.client.search(type: "bili_user", keyword: "罗翔", page: 1)
            guard let user = page.users.first(where: { $0.name.contains("罗翔") }) ?? page.users.first else {
                SpaceUIProof.record(["name": "", "mid": 0, "fans": 0, "level": 0, "sign": "", "likes": 0, "count": 0, "title": "", "tab": "", "error": "未搜索到罗翔"])
                return
            }
            model.open(.user(user.mid, user.name))
        } catch {
            SpaceUIProof.record(["name": "", "mid": 0, "fans": 0, "level": 0, "sign": "", "likes": 0, "count": 0, "title": "", "tab": "", "error": error.localizedDescription])
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .search: SearchStudio()
        case .video(let bvid): VideoStage(bvid: bvid)
        case .live(let id): LiveStage(roomID: id)
        case .settings: SettingsStudio()
        case .setting(let name): SettingDetail(name: name)
        case .messages: MessageHome()
        case .notices(let kind): NoticeListView(kind: kind)
        case .chat(let id, let name): ChatView(talkerID: id, name: name)
        case .login: LoginGate()
        case .feature(let title):
            switch title {
            case "观看记录": HistoryListView()
            case "稍后再看": WatchLaterListView()
            case "我的收藏": FavoritesView()
            case "离线缓存": DownloadsPage()
            case "私信": MessageHome()
            case "回复我的", "@我", "收到的赞", "系统通知": NoticeListView(kind: title)
            default: FeaturePageView(title: title)
            }
        case .folder(let id): FolderContentsView(mediaID: id)
        case .user(let mid, let name): SpacePage(mid: mid, name: name)
        }
    }
}

struct NowPlayingPill: View {
    @Environment(AppModel.self) private var model
    let video: VideoItem

    var body: some View {
        Button {
            model.open(.video(video.bvid))
        } label: {
            HStack(spacing: 10) {
                RemoteImage(url: video.cover, ratio: 1, maxPixel: 120)
                    .frame(width: 36, height: 36)
                    .clipShape(ConcentricRectangle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(video.title).font(.footnote.weight(.semibold)).lineLimit(1)
                    Text(model.isPlaying ? "正在播放 · \(video.ownerName)" : "已暂停 · \(video.ownerName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button {
                    model.isPlaying.toggle()
                    if model.isPlaying { model.player?.play() } else { model.player?.pause() }
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}
