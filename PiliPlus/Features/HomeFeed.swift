import SwiftUI

struct HomeFeed: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        pages
            .background { AuroraBackdrop() }
            .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private var pages: some View {
        switch model.homeTab {
        case "直播":
            LivePlaza().feedChrome { HomeChrome(collapse: 0) }
        case "热门":
            HotPage().feedChrome { HomeChrome(collapse: 0) }
        case "分区":
            RankPage().feedChrome { HomeChrome(collapse: 0) }
        case "番剧":
            PGCPage(kind: "番剧").feedChrome { HomeChrome(collapse: 0) }
        case "影视":
            PGCPage(kind: "影视").feedChrome { HomeChrome(collapse: 0) }
        default:
            RecommendPage()
        }
    }
}

/// Search row plus the home tabs. Only the search row tracks scroll.
private struct HomeChrome: View {
    var collapse: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            CollapsingSearchRow(progress: collapse)
            HomeTabStrip()
        }
    }
}

/// Height follows scroll progress. The value is already eased, and animations
/// are disabled so the row cannot finish the move after the finger has stopped.
private struct CollapsingSearchRow: View {
    var progress: CGFloat
    static let full: CGFloat = 48

    var body: some View {
        SearchRow()
            .frame(height: Self.full, alignment: .top)
            .offset(y: -Self.full * progress)
            .frame(height: max(0, Self.full * (1 - progress)), alignment: .top)
            .clipped()
            .opacity(1 - Double(progress))
            .accessibilityHidden(progress > 0.98)
    }
}

private struct SearchRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GlassEffectContainer(spacing: 4) {
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
                .glassCapsule(interactive: false)
                .accessibilityLabel("搜索")
                GlassIconButton(system: "bell", badge: model.flag("消息未读标记") ? model.unreadReply + model.unreadAt : 0) {
                    model.open(.messages)
                }
                .accessibilityLabel("消息")
                Button {
                    if model.loggedIn { model.open(.feature("编辑资料")) } else { model.open(.login) }
                } label: {
                    avatar
                }
                .buttonStyle(.plain)
                .accessibilityLabel("个人资料")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 2)
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(Palette.bili.gradient)
            Text(String(model.userName.prefix(1)))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
        }
        .frame(width: 40, height: 40)
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
    @State private var tracked: CGFloat = 0
    @State private var collapse: CGFloat = 0
    @State private var easing = false

    private static let travel: CGFloat = 72

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                RecommendGrid()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
            .refreshable { await model.refreshHome() }
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y
            } action: { old, new in
                trackCollapse(from: old, to: new)
            }
            .feedChrome {
                HomeChrome(collapse: model.flag("首页顶栏收起") ? collapse : 0)
            }
            .task { await scrollBench(proxy) }
        }
    }

    /// Small deltas track the scroll directly. A scripted `scrollTo` often
    /// reports the whole distance at once; that case eases the bar instead of
    /// cutting its height to zero on a single frame.
    private func trackCollapse(from old: CGFloat, to new: CGFloat) {
        guard model.flag("首页顶栏收起") else {
            if tracked != 0 || collapse != 0 {
                applyCollapse(tracked: 0, collapse: 0)
            }
            return
        }
        if easing { return }
        let dy = new - old
        var next = tracked + dy
        if new <= 1 { next = 0 }
        next = min(Self.travel, max(0, next))
        if abs(next - tracked) < 0.05 { return }
        let t = next / Self.travel
        let eased = t * t * (3 - 2 * t)
        if abs(dy) > 28 {
            easing = true
            let duration = min(0.42, 0.22 + abs(dy) / 700)
            withAnimation(.easeInOut(duration: duration)) {
                tracked = next
                collapse = eased
            }
            Task {
                try? await Task.sleep(for: .milliseconds(Int(duration * 1000) + 40))
                easing = false
            }
        } else {
            applyCollapse(tracked: next, collapse: eased)
        }
    }

    private func applyCollapse(tracked: CGFloat, collapse: CGFloat) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            self.tracked = tracked
            self.collapse = collapse
        }
    }

    private func scrollBench(_ proxy: ScrollViewProxy) async {
        guard LaunchMode.perfScroll else { return }
        while model.feed.count < 8 {
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
            "imageMisses": ImageStore.prepareMisses
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
                VideoCard(video: video).id(video.bvid)
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
                            .foregroundStyle(zone == item ? .white : .primary)
                            .selectionCapsule(selected: zone == item)
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
                                .foregroundStyle(area == item ? .white : .primary)
                                .selectionCapsule(selected: area == item)
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
