import SwiftUI

struct HomeFeed: View {
    @Environment(AppModel.self) private var model
    @State private var hideChrome = false

    var body: some View {
        @Bindable var model = model
        ZStack {
            AuroraBackground()
            VStack(spacing: 0) {
                if !hideChrome || !model.flag("首页顶栏收起") {
                    topBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                tabStrip
                content
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .animation(.spring(duration: 0.38), value: hideChrome)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { model.open(.search) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text(model.flag("搜索默认词") ? (model.hotwords.first?.show ?? "搜索视频、番剧、UP 主") : "搜索")
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .font(.subheadline)
                .padding(.horizontal, 14)
                .frame(height: 42)
            }
            .buttonStyle(.plain)
            .glassCapsule()
            GlassIconButton(system: "bell", badge: model.flag("消息未读标记") ? model.unreadReply + model.unreadAt : 0) {
                model.open(.messages)
            }
            Button {
                if model.loggedIn { model.open(.feature("编辑资料")) } else { model.open(.login) }
            } label: {
                avatar
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(Palette.bili.gradient)
            Text(String(model.userName.prefix(1)))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
        }
        .frame(width: 40, height: 40)
        .glassCapsule(interactive: false)
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.homeTabs, id: \.self) { tab in
                    Button {
                        withAnimation(.spring(duration: 0.32)) { model.homeTab = tab }
                    } label: {
                        Text(tab)
                            .font(.subheadline.weight(model.homeTab == tab ? .bold : .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .foregroundStyle(model.homeTab == tab ? .white : .primary)
                            .background {
                                if model.homeTab == tab {
                                    Capsule().fill(Palette.bili.gradient)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.homeTab {
        case "直播":
            LivePlaza()
        case "热门":
            HotPage()
        case "分区":
            RankPage()
        case "番剧":
            PGCPage(kind: "番剧")
        case "影视":
            PGCPage(kind: "影视")
        default:
            recommend
        }
    }

    private var recommend: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
                    if model.loadingFeed && model.feed.isEmpty {
                        ForEach(0..<6, id: \.self) { _ in ShimmerCard() }
                    }
                    ForEach(model.feed) { video in
                        VideoCard(video: video).id(video.bvid)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .refreshable { await model.refreshHome() }
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y
            } action: { old, new in
                guard model.flag("首页顶栏收起") else { return }
                if new > old + 12 { hideChrome = true }
                if new < 8 || new < old - 18 { hideChrome = false }
            }
            .task { await scrollBench(proxy) }
        }
    }

    private func scrollBench(_ proxy: ScrollViewProxy) async {
        guard LaunchMode.perfScroll else { return }
        while model.feed.count < 8 {
            try? await Task.sleep(for: .milliseconds(40))
        }
        try? await Task.sleep(for: .milliseconds(450))
        let ids = model.feed.map(\.bvid)
        let cold = await sweep(proxy, ids: ids)
        let warm = await sweep(proxy, ids: ids)
        LaunchClock.write([
            "phase": "scroll",
            "cold": cold.dictionary,
            "warm": warm.dictionary
        ])
        try? await Task.sleep(for: .milliseconds(300))
        exit(0)
    }

    private func sweep(_ proxy: ScrollViewProxy, ids: [String]) async -> FrameStats {
        FrameMonitor.shared.start()
        let step = max(2, ids.count / 8)
        var index = 0
        while index < ids.count {
            let id = ids[index]
            withAnimation(.linear(duration: 0.32)) {
                proxy.scrollTo(id, anchor: .top)
            }
            try? await Task.sleep(for: .milliseconds(340))
            index += step
        }
        withAnimation(.linear(duration: 0.32)) {
            proxy.scrollTo(ids[0], anchor: .top)
        }
        try? await Task.sleep(for: .milliseconds(360))
        return FrameMonitor.shared.stop()
    }
}

struct HotPage: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if model.flag("显示热门推荐") {
                    HStack(spacing: 8) {
                        entry("每周必看", "flame") { model.open(.feature("每周必看")) }
                        entry("入站必刷", "star.circle") { model.open(.feature("入站必刷")) }
                        entry("排行榜", "chart.bar") { model.homeTab = "分区" }
                    }
                }
                ForEach(Array(model.hot.enumerated()), id: \.element.id) { index, video in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.title3.weight(.black).monospacedDigit())
                            .foregroundStyle(index < 3 ? Palette.bili : .secondary)
                            .frame(width: 28)
                        VideoCard(video: video, compact: true)
                    }
                }
            }
            .padding(16)
        }
        .refreshable { await model.refreshHome() }
    }

    private func entry(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .glassCard(radius: 18, interactive: true)
        }
        .buttonStyle(.plain)
    }
}

struct RankPage: View {
    @Environment(AppModel.self) private var model
    @State private var zone = "全站"
    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Menus.rankZones, id: \.self) { item in
                        Button(item) { zone = item }
                            .font(.caption.weight(zone == item ? .bold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .glassCapsule(interactive: zone == item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(model.rank.isEmpty ? model.feed : model.rank) { video in
                        VideoCard(video: video)
                    }
                }
                .padding(16)
            }
        }
    }
}

struct PGCPage: View {
    @Environment(AppModel.self) private var model
    let kind: String
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if kind == "番剧" && model.flag("展示追番时间表") {
                    Text("追番时间表")
                        .font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { day in
                                VStack {
                                    Text("周\(day)").font(.caption.weight(.bold))
                                    Text(day == "五" ? "更新 6" : "更新 2").font(.caption2).foregroundStyle(.secondary)
                                }
                                .frame(width: 72, height: 64)
                                .glassCard(radius: 18, interactive: true)
                            }
                        }
                    }
                }
                HStack {
                    ForEach(kind == "番剧" ? ["追番", "索引", "点评"] : ["追剧", "索引", "电影"], id: \.self) { item in
                        Button(item) { model.open(.feature(item == "索引" ? "索引" : kind)) }
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .glassCapsule()
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(model.feed.prefix(9)) { video in
                        VideoCard(video: video, compact: true)
                    }
                }
            }
            .padding(16)
        }
    }
}

struct LivePlaza: View {
    @Environment(AppModel.self) private var model
    @State private var area = "推荐"
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Menus.liveAreas, id: \.self) { item in
                            Button(item) { area = item }
                                .font(.caption.weight(area == item ? .bold : .regular))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .glassCapsule(interactive: area == item)
                        }
                    }
                }
                Button {
                    model.open(.feature("关注的直播"))
                } label: {
                    Label("关注的直播", systemImage: "heart")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .glassCard(radius: 18, interactive: true)
                }
                .buttonStyle(.plain)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(model.lives) { room in
                        Button { model.open(.live(room.id)) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                RemoteImage(url: room.cover)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay(alignment: .topLeading) {
                                        Text(room.area)
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.black.opacity(0.45), in: Capsule())
                                            .foregroundStyle(.white)
                                            .padding(8)
                                    }
                                Text(room.title).font(.caption.weight(.semibold)).lineLimit(2).foregroundStyle(.primary)
                                HStack {
                                    Text(room.uname).lineLimit(1)
                                    Spacer()
                                    Label(CountText.format(room.online), systemImage: "person.2")
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if model.lives.isEmpty {
                    ContentUnavailableView("暂无直播", systemImage: "dot.radiowaves.left.and.right", description: Text("下拉刷新，或检查网络"))
                }
            }
            .padding(16)
        }
        .refreshable { await model.refreshHome() }
    }
}
