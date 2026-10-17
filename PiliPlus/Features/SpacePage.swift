import SwiftUI

struct SpacePage: View {
    @Environment(AppModel.self) private var model
    let mid: Int
    let name: String

    @State private var tab = SpacePage.initialTab
    @State private var orderTitle = "最新"
    @State private var profile: SpaceProfile?
    @State private var followed = false
    @State private var failure = ""
    @State private var loading = false
    @State private var videos: [VideoItem] = []
    @State private var videoPage = 1
    @State private var videoHasMore = true
    @State private var dynamics: [DynamicItem] = []
    @State private var dynamicGuest = false
    @State private var dynamicOffset = ""
    @State private var dynamicHasMore = true
    @State private var folders: [FavFolder] = []
    @State private var seasons: [SeasonItem] = []
    @State private var seasonPage = 1
    @State private var seasonHasMore = true
    @State private var series: [SpaceSeries] = []

    private static let tabs = ["投稿", "动态", "收藏", "追番", "合集"]
    private static var initialTab: String {
        switch LaunchMode.screen {
        case "space-dynamic": return "动态"
        case "space-fav": return "收藏"
        case "space-bangumi": return "追番"
        case "space-series": return "合集"
        default: return "投稿"
        }
    }

    var body: some View {
        List {
            if let profile {
                Section { header(profile) }
                Section { controls }
                Section { tabBody }
            } else if !failure.isEmpty {
                ContentUnavailableView("空间打不开", systemImage: "person.crop.circle.badge.exclamationmark", description: Text(failure))
            } else {
                ProgressView("正在加载")
            }
        }
        .navigationTitle(profile?.name ?? name)
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
        .onChange(of: tab) { _, _ in
            Task { await reload(reset: true) }
        }
        .onChange(of: orderTitle) { _, _ in
            guard tab == "投稿" else { return }
            Task { await loadVideos(reset: true) }
        }
    }

    private func header(_ profile: SpaceProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                RemoteImage(url: profile.face, ratio: 1, maxPixel: 180)
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 6) {
                    Text("Lv.\(profile.level)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                    Text(profile.sign.isEmpty ? "这个人没有填写签名" : profile.sign)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Button(followed ? "已关注" : "关注") {
                        let next = !followed
                        Task {
                            if await model.followUser(mid: profile.mid, follow: next) {
                                followed = next
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            HStack(spacing: 0) {
                stat("关注", profile.following)
                stat("粉丝", profile.fans)
                stat("获赞", profile.likes)
            }
        }
        .padding(.vertical, 4)
    }

    private func stat(_ title: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text(CountText.format(value))
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Picker("栏目", selection: $tab) {
                ForEach(Self.tabs, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            if tab == "投稿" {
                Picker("排序", selection: $orderTitle) {
                    Text("最新").tag("最新")
                    Text("最热").tag("最热")
                }
                .pickerStyle(.segmented)
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    @ViewBuilder
    private var tabBody: some View {
        switch tab {
        case "动态":
            if dynamics.isEmpty {
                ContentUnavailableView(
                    dynamicGuest ? "登录后查看动态" : "暂无动态",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(loading ? "正在加载" : (dynamicGuest ? "接口没有向访客返回动态" : "这里是空的"))
                )
            }
            ForEach(dynamics) { item in
                dynamicRow(item)
                    .onAppear {
                        guard item.id == dynamics.last?.id else { return }
                        Task { await loadDynamics(reset: false) }
                    }
            }
        case "收藏":
            if folders.isEmpty { empty("没有公开收藏夹") }
            ForEach(folders) { folder in
                Button { model.open(.folder(folder.id)) } label: { folderRow(folder) }
                    .buttonStyle(.plain)
            }
        case "追番":
            if seasons.isEmpty { empty("没有公开追番") }
            ForEach(seasons) { season in
                seasonRow(season)
                    .onAppear {
                        guard season.id == seasons.last?.id else { return }
                        Task { await loadBangumi(reset: false) }
                    }
            }
        case "合集":
            if series.isEmpty { empty("没有合集") }
            ForEach(series) { item in
                seriesRow(item)
            }
        default:
            if videos.isEmpty { empty("没有投稿") }
            ForEach(videos) { video in
                Button {
                    model.store(video)
                    model.open(.video(video.bvid))
                } label: {
                    videoRow(video)
                }
                .buttonStyle(.plain)
                .onAppear {
                    guard video.id == videos.last?.id else { return }
                    Task { await loadVideos(reset: false) }
                }
            }
        }
    }

    private func empty(_ title: String) -> some View {
        ContentUnavailableView(title, systemImage: "tray", description: Text(loading ? "正在加载" : "这里是空的"))
    }

    private func videoRow(_ video: VideoItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteImage(url: video.cover, ratio: 16.0 / 9.0, maxPixel: 320)
                .frame(width: 128)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(video.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2, reservesSpace: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    if video.view > 0 { countIcon("play.fill", CountText.format(video.view)) }
                    if video.danmaku > 0 { countIcon("text.bubble.fill", CountText.format(video.danmaku)) }
                    Spacer(minLength: 0)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.vertical, 4)
    }

    private func countIcon(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            Text(text).lineLimit(1).fixedSize(horizontal: true, vertical: false)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func dynamicRow(_ item: DynamicItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.text).font(.subheadline).foregroundStyle(.primary).lineLimit(4)
            Text(item.time).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            if let video = item.video {
                Button {
                    model.store(video)
                    model.open(.video(video.bvid))
                } label: {
                    Text(video.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func folderRow(_ folder: FavFolder) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.title).foregroundStyle(.primary).lineLimit(1)
                Text("\(folder.count) 个内容").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func seasonRow(_ season: SeasonItem) -> some View {
        HStack(spacing: 12) {
            RemoteImage(url: season.cover, maxPixel: 240)
                .frame(width: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(season.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                if !season.subtitle.isEmpty {
                    Text(season.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    private func seriesRow(_ item: SpaceSeries) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
            Text(item.count > 0 ? "\(item.kind) · \(item.count) 个视频" : item.kind)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        loading = true
        do {
            let card = try await model.client.spaceProfile(mid: mid)
            profile = card
            followed = card.followed
            loading = false
            await reload(reset: true)
        } catch {
            loading = false
            failure = error.localizedDescription
            record(count: 0, title: "", error: failure)
        }
    }

    private func reload(reset: Bool) async {
        switch tab {
        case "动态": await loadDynamics(reset: reset)
        case "收藏": await loadFolders()
        case "追番": await loadBangumi(reset: reset)
        case "合集": await loadSeries()
        default: await loadVideos(reset: reset)
        }
    }

    private func loadVideos(reset: Bool) async {
        if reset {
            videoPage = 1
            videoHasMore = true
        }
        guard videoHasMore, !loading else { return }
        loading = true
        defer { loading = false }
        let fetching = videoPage
        do {
            let page = try await model.client.spaceVideos(mid: mid, page: fetching, order: SpaceRequest.videoOrder(for: orderTitle))
            if reset {
                videos = page.items
            } else {
                let known = Set(videos.map(\.bvid))
                videos.append(contentsOf: page.items.filter { !known.contains($0.bvid) })
            }
            videoHasMore = videos.count < page.total && !page.items.isEmpty
            if videoHasMore { videoPage = fetching + 1 }
            page.items.forEach(model.store)
            if reset { record(count: videos.count, title: videos.first?.title ?? "", error: "", source: page.source) }
        } catch {
            if reset { record(count: videos.count, title: "", error: error.localizedDescription) }
        }
    }

    private func loadDynamics(reset: Bool) async {
        if reset {
            dynamicOffset = ""
            dynamicHasMore = true
        }
        guard dynamicHasMore, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await model.client.spaceDynamics(mid: mid, offset: dynamicOffset)
            if reset {
                dynamics = page.items
            } else {
                let known = Set(dynamics.map(\.id))
                dynamics.append(contentsOf: page.items.filter { !known.contains($0.id) })
            }
            dynamicOffset = page.offset
            dynamicHasMore = page.hasMore
            dynamicGuest = page.guestRefused
            if reset {
                let title = dynamics.first?.text ?? (page.guestRefused ? "登录后查看动态" : "暂无动态")
                let empty = dynamics.isEmpty ? (page.guestRefused ? "guest" : "none") : nil
                record(count: dynamics.count, title: title, error: "", source: page.source, empty: empty)
            }
        } catch {
            if reset { record(count: dynamics.count, title: "", error: error.localizedDescription) }
        }
    }

    private func loadFolders() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await model.client.spaceFolders(mid: mid)
            folders = page.folders
            record(count: folders.count, title: folders.first?.title ?? "", error: "", raw: page.raw)
        } catch {
            record(count: 0, title: "", error: error.localizedDescription)
        }
    }

    private func loadBangumi(reset: Bool) async {
        if reset {
            seasonPage = 1
            seasonHasMore = true
        }
        guard seasonHasMore, !loading else { return }
        loading = true
        defer { loading = false }
        let fetching = seasonPage
        do {
            let page = try await model.client.spaceBangumi(mid: mid, page: fetching)
            if reset {
                seasons = page
            } else {
                let known = Set(seasons.map(\.seasonID))
                seasons.append(contentsOf: page.filter { !known.contains($0.seasonID) })
            }
            seasonHasMore = page.count >= 20
            if seasonHasMore { seasonPage = fetching + 1 }
            if reset { record(count: seasons.count, title: seasons.first?.title ?? "", error: "") }
        } catch {
            if reset { record(count: seasons.count, title: "", error: error.localizedDescription) }
        }
    }

    private func loadSeries() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            series = try await model.client.spaceSeries(mid: mid, page: 1)
            record(count: series.count, title: series.first?.title ?? "", error: "")
        } catch {
            record(count: 0, title: "", error: error.localizedDescription)
        }
    }

    private func record(count: Int, title: String, error: String, raw: Int? = nil, source: String? = nil, empty: String? = nil) {
        let card = profile
        var payload: [String: Any] = [
            "name": card?.name ?? name,
            "mid": card?.mid ?? mid,
            "fans": card?.fans ?? 0,
            "level": card?.level ?? 0,
            "sign": card?.sign ?? "",
            "likes": card?.likes ?? 0,
            "count": count,
            "title": title,
            "tab": tab,
            "error": error
        ]
        if let raw { payload["raw"] = raw }
        if let source { payload["source"] = source }
        if let empty { payload["empty"] = empty }
        SpaceUIProof.record(payload)
    }
}
