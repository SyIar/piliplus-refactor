import SwiftUI

struct HomeFeed: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        pages
            .navigationTitle("首页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { HomeToolbar() }
    }

    @ViewBuilder
    private var pages: some View {
        switch model.homeTab {
        case "直播":
            LivePlaza().homeTabBar()
        case "热门":
            HotPage().homeTabBar()
        case "分区":
            RankPage().homeTabBar()
        case "番剧":
            PGCPage(kind: "番剧").homeTabBar()
        case "影视":
            PGCPage(kind: "影视").homeTabBar()
        default:
            RecommendPage()
        }
    }
}

private struct HomeToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                model.open(.messages)
            } label: {
                Image(systemName: "bell")
            }
            .badge(model.flag("消息未读标记") ? model.unreadReply + model.unreadAt : 0)
            .accessibilityLabel("消息")
        }
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                if model.loggedIn { model.open(.feature("编辑资料")) } else { model.open(.login) }
            } label: {
                ProfileMark(name: model.userName, face: model.userFace, size: 28)
            }
            .accessibilityLabel("个人资料")
        }
    }
}

private extension View {
    /// Fixed-height category strip under the system bar. Height does not animate.
    func homeTabBar() -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            HomeTabStrip()
                .background(Color(.systemBackground))
        }
    }
}

private struct HomeTabStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
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
            .padding(.vertical, 8)
        }
        .frame(height: 56)
    }
}

/// Owns the scroll-linked collapse so the card grid is not rebuilt while the bar moves.
private struct RecommendPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            scroller
                .task { await scrollBench(proxy) }
        }
    }

    /// Category tabs stay pinned. Search lives in the system search tab, so this
    /// scroll view does not resize a glass bar while the bench is running.
    @ViewBuilder
    private var scroller: some View {
        if model.flag("首页顶栏收起") {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        RecommendGrid()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    } header: {
                        HomeTabStrip()
                            .background(Color(.systemBackground))
                    }
                }
            }
            .refreshable { await model.refreshHome() }
            .scrollEdgeSoft()
        } else {
            ScrollView {
                RecommendGrid()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
            .refreshable { await model.refreshHome() }
            .scrollEdgeSoft()
            .homeTabBar()
        }
    }

    private func scrollBench(_ proxy: ScrollViewProxy) async {
        guard LaunchMode.perfScroll else { return }
        var spins = 0
        while model.feed.count < 8 {
            spins += 1
            if spins > 500 {
                LaunchClock.write([
                    "phase": "scroll",
                    "error": model.feedSource.isEmpty ? "empty" : model.feedSource
                ])
                exit(0)
                return
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
        await ImageStore.shared.prepare(urls: model.feed.map(\.cover), maxPixel: 560)
        try? await Task.sleep(for: .milliseconds(280))
        let ids = model.feed.map(\.bvid)
        ImageStore.prepareHits = 0
        ImageStore.prepareMisses = 0
        let cold = await sweep(proxy, ids: ids)
        let warm = await sweep(proxy, ids: ids)
        LaunchClock.write([
            "phase": "scroll",
            "cold": cold.dictionary,
            "warm": warm.dictionary,
            "imageHits": ImageStore.prepareHits,
            "imageMisses": ImageStore.prepareMisses,
            "preparedCovers": ImageStore.preparedCount
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

/// Separated so collapse updates do not rebuild every card.
private struct RecommendGrid: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
            if model.loadingFeed && model.feed.isEmpty {
                ForEach(0..<6, id: \.self) { _ in ShimmerCard() }
            }
            ForEach(model.feed) { video in
                VideoCard(video: video)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .id(video.bvid)
                    .onAppear {
                        guard video.bvid == model.feed.last?.bvid else { return }
                        Task { await model.loadRecommend(reset: false) }
                    }
            }
            if model.loadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
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
        .scrollEdgeSoft()
    }

    private func entry(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .contentPlate(radius: 18)
        }
        .buttonStyle(.plain)
    }
}

struct RankPage: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Menus.rankZones, id: \.self) { item in
                        Button(item) { Task { await model.loadZone(item, reset: true) } }
                            .font(.caption.weight(model.zoneName == item ? .bold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .foregroundStyle(model.zoneName == item ? .white : .primary)
                            .selectionCapsule(selected: model.zoneName == item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(model.zoneFeed) { video in
                        VideoCard(video: video)
                            .onAppear {
                                guard video.bvid == model.zoneFeed.last?.bvid else { return }
                                Task { await model.loadZone(model.zoneName, reset: false) }
                            }
                    }
                    if model.zoneFeed.isEmpty {
                        ContentUnavailableView("这个分区还没有稿件", systemImage: "square.grid.2x2", description: Text("下拉换一个分区"))
                    }
                }
                .padding(16)
            }
            .scrollEdgeSoft()
        }
        .task {
            if model.zoneFeed.isEmpty { await model.loadZone(model.zoneName, reset: true) }
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
                                    Text("更新 \(model.bangumiSchedule[day] ?? 0)").font(.caption2).foregroundStyle(.secondary)
                                }
                                .frame(width: 72, height: 64)
                                .contentPlate(radius: 18)
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
                            .selectionCapsule(selected: false)
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(model.seasons(for: kind).prefix(18)) { season in
                        SeasonCard(season: season)
                    }
                }
                if model.seasons(for: kind).isEmpty {
                    ContentUnavailableView("暂无\(kind)", systemImage: "tv", description: Text("下拉刷新"))
                }
            }
            .padding(16)
        }
        .refreshable { await model.loadSeasons(kind) }
        .scrollEdgeSoft()
        .task {
            if model.seasons(for: kind).isEmpty { await model.loadSeasons(kind) }
        }
    }
}

private struct SeasonCard: View {
    @Environment(AppModel.self) private var model
    let season: SeasonItem

    var body: some View {
        Button {
            Task { await model.playSeason(season.seasonID) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                RemoteImage(url: season.cover, ratio: 3 / 4, maxPixel: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if !season.badge.isEmpty {
                            Text(season.badge)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.45), in: Capsule())
                                .foregroundStyle(.white)
                                .padding(6)
                        }
                    }
                Text(season.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !season.subtitle.isEmpty {
                    Text(season.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct LivePlaza: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Menus.liveAreas, id: \.self) { item in
                            Button(item) { Task { await model.loadLive(area: item, reset: true) } }
                                .font(.caption.weight(model.liveArea == item ? .bold : .regular))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .foregroundStyle(model.liveArea == item ? .white : .primary)
                                .selectionCapsule(selected: model.liveArea == item)
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
                        .contentPlate(radius: 18)
                }
                .buttonStyle(.plain)
                if model.loadingLive && model.lives.isEmpty {
                    ProgressView("正在加载")
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else if model.lives.isEmpty {
                    ContentUnavailableView("暂无直播", systemImage: "dot.radiowaves.left.and.right", description: Text("换个分区，或下拉刷新"))
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(Array(model.lives.enumerated()), id: \.element.id) { index, room in
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
                                        Text(room.uname)
                                            .lineLimit(1)
                                            .layoutPriority(-1)
                                        Spacer(minLength: 0)
                                        Label(CountText.format(room.online), systemImage: "person.2")
                                            .lineLimit(1)
                                            .fixedSize()
                                    }
                                    .lineLimit(1)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                guard index >= model.lives.count - 1 else { return }
                                Task { await model.loadLive(area: model.liveArea, reset: false) }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .refreshable { await model.loadLive(area: model.liveArea, reset: true) }
        .task {
            if model.lives.isEmpty { await model.loadLive(area: model.liveArea, reset: true) }
        }
        .scrollEdgeSoft()
    }
}
