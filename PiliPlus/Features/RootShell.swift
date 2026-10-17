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
        .tabViewBottomAccessory(isEnabled: model.nowPlaying != nil) {
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
        if LaunchMode.perfScroll {
            await LaunchClock.waitForFirstFrame()
            await model.loadRecommend(reset: true)
            return
        }
        if LaunchMode.usesFixtures {
            await LaunchClock.waitForFirstFrame()
            model.applyFixtures()
            if LaunchMode.screen == "search" { model.open(.search) }
            if LaunchMode.screen == "settings" { model.open(.settings) }
            if LaunchMode.screen == "login" { model.open(.login) }
            if LaunchMode.screen == "video", let first = model.feed.first { model.open(.video(first.bvid)) }
            return
        }
        if LaunchMode.screen == "playback" {
            if model.feed.isEmpty { await model.loadRecommend(reset: true) }
            await model.openFirstPlayable()
            return
        }
        if model.feed.isEmpty { await model.refreshHome() }
        await model.refreshProfile()
        switch LaunchMode.screen {
        case "home":
            let firstCount = model.feed.count
            await model.loadRecommend(reset: false)
            HomeProof.record([
                "source": model.feedSource,
                "page": model.feedPage,
                "count": model.feed.count,
                "firstCount": firstCount,
                "title": model.feed.first?.title ?? "",
                "bvid": model.feed.first?.bvid ?? ""
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

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .search: SearchStudio()
        case .video(let bvid): VideoStage(bvid: bvid)
        case .live(let id): LiveStage(roomID: id)
        case .settings: SettingsStudio()
        case .setting(let name): SettingDetail(name: name)
        case .messages: InboxView()
        case .login: LoginGate()
        case .feature(let title): FeaturePageView(title: title)
        case .user(let mid, let name): MemberPage(mid: mid, name: name)
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
