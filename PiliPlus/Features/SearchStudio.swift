import SwiftUI

struct SearchStudio: View {
    @Environment(AppModel.self) private var model
    @State private var keyword = ""
    @State private var tab = "综合"
    @State private var results: [VideoItem] = []
    @State private var users: [SearchUser] = []
    @State private var seasons: [SeasonItem] = []
    @State private var rooms: [LiveRoom] = []
    @State private var articles: [SearchArticle] = []
    @State private var page = 1
    @State private var searching = false
    @State private var order = "默认排序"
    @State private var duration = "全部时长"
    @State private var zone = "全部"
    @State private var pub = "不限"
    @State private var showFilter = false

    private var prompt: String {
        model.flag("搜索默认词") ? (model.hotwords.first?.show ?? "搜索视频、番剧、UP 主") : "搜索"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                tabStrip
                if keyword.isEmpty { discover } else { resultList }
            }
        }
        .scrollEdgeSoft()
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $keyword, prompt: prompt) {
            if model.flag("搜索建议"), !keyword.isEmpty {
                ForEach(model.hotwords.filter { $0.show.localizedCaseInsensitiveContains(keyword) || $0.keyword.localizedCaseInsensitiveContains(keyword) }) { word in
                    Text(word.show).searchCompletion(word.keyword)
                }
            }
        }
        .onSubmit(of: .search) { Task { await run(reset: true) } }
        .task { await captureIfNeeded() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("筛选", systemImage: "line.3.horizontal.decrease") { showFilter = true }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("搜索") { Task { await run(reset: true) } }
                    .fontWeight(.bold)
            }
        }
        .sheet(isPresented: $showFilter) { filterSheet }
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Menus.searchTabs, id: \.self) { item in
                    Button(item) { tab = item; Task { await run(reset: true) } }
                        .font(.caption.weight(tab == item ? .bold : .regular))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(tab == item ? Color.white : Color.primary)
                        .selectionCapsule(selected: tab == item)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private var discover: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.flag("记录搜索历史") && !model.searchHistory.isEmpty {
                section("搜索历史") {
                    FlowTags(items: model.searchHistory) { word in
                        keyword = word
                        Task { await run(reset: true) }
                    }
                    Button("清空历史", role: .destructive) {
                        model.searchHistory = []
                        model.save()
                    }
                    .font(.caption)
                }
            }
            if model.flag("大家都在搜") {
                section("大家都在搜") {
                    FlowTags(items: model.hotwords.map(\.keyword)) { word in
                        keyword = word
                        Task { await run(reset: true) }
                    }
                }
            }
            if model.flag("搜索发现") {
                section("搜索发现") {
                    ForEach(model.hotwords) { word in
                        Button {
                            keyword = word.keyword
                            Task { await run(reset: true) }
                        } label: {
                            HStack {
                                Text(word.show).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var resultList: some View {
        LazyVStack(spacing: 14) {
            if searching { ProgressView().padding() }
            switch tab {
            case "用户":
                if users.isEmpty && !searching { emptyResult }
                ForEach(users) { user in
                    Button { model.open(.user(user.mid, user.name)) } label: {
                        HStack(spacing: 12) {
                            RemoteImage(url: user.face, ratio: 1, maxPixel: 120)
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.name).font(.headline).foregroundStyle(.primary).lineLimit(1)
                                Text(user.sign.isEmpty ? "UID \(user.mid)" : user.sign)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Text(CountText.format(user.fans))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                    .contentPlate(radius: 18)
                }
            case "番剧", "影视":
                if seasons.isEmpty && !searching { emptyResult }
                ForEach(seasons) { season in
                    Button { model.open(.feature(season.title)) } label: {
                        HStack(spacing: 12) {
                            RemoteImage(url: season.cover, maxPixel: 240)
                                .frame(width: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(season.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                                Text(season.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            case "直播间":
                if rooms.isEmpty && !searching { emptyResult }
                ForEach(rooms) { room in
                    Button { model.open(.live(room.id)) } label: {
                        HStack(spacing: 12) {
                            RemoteImage(url: room.cover, maxPixel: 240)
                                .frame(width: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(room.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                                HStack {
                                    Text(room.uname).lineLimit(1).layoutPriority(-1)
                                    Spacer(minLength: 8)
                                    if room.online > 0 {
                                        HStack(spacing: 3) {
                                            Image(systemName: "person.fill")
                                            Text(CountText.format(room.online))
                                                .lineLimit(1)
                                                .fixedSize(horizontal: true, vertical: false)
                                        }
                                        .fixedSize(horizontal: true, vertical: false)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            case "专栏":
                if articles.isEmpty && !searching { emptyResult }
                ForEach(articles) { article in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(article.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                        if !article.summary.isEmpty {
                            Text(article.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        HStack {
                            Text(article.author).lineLimit(1).layoutPriority(-1)
                            Spacer(minLength: 8)
                            if article.view > 0 {
                                HStack(spacing: 3) {
                                    Image(systemName: "eye.fill")
                                    Text(CountText.format(article.view))
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .contentPlate(radius: 18)
                }
            default:
                if results.isEmpty && !searching { emptyResult }
                ForEach(results) { video in
                    VideoCard(video: video)
                }
            }
            if !searching && hasResults {
                Button("更多结果") { Task { await run(reset: false) } }
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(16)
    }

    private var emptyResult: some View {
        ContentUnavailableView("没有结果", systemImage: "magnifyingglass", description: Text("换个关键词试试"))
    }

    private var hasResults: Bool {
        switch tab {
        case "用户": return !users.isEmpty
        case "番剧", "影视": return !seasons.isEmpty
        case "直播间": return !rooms.isEmpty
        case "专栏": return !articles.isEmpty
        default: return !results.isEmpty
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private var filterSheet: some View {
        NavigationStack {
            List {
                picker("排序", Menus.videoOrders.map(\.0), $order)
                picker("时长", Menus.durations.map(\.0), $duration)
                picker("分区", Menus.zones.map(\.0), $zone)
                picker("发布时间", Menus.pubTimes, $pub)
            }
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showFilter = false; Task { await run(reset: true) } }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    private func picker(_ title: String, _ options: [String], _ binding: Binding<String>) -> some View {
        Picker(title, selection: binding) {
            ForEach(options, id: \.self) { Text($0).tag($0) }
        }
    }

    private func captureIfNeeded() async {
        guard let spec = LaunchMode.searchCapture else { return }
        tab = spec.tab
        keyword = spec.keyword
        let failure = await run(reset: true)
        let title: String
        let count: Int
        switch spec.tab {
        case "用户":
            count = users.count
            title = users.first?.name ?? ""
        case "番剧":
            count = seasons.count
            title = seasons.first?.title ?? ""
        case "直播间":
            count = rooms.count
            title = rooms.first?.title ?? ""
        case "专栏":
            count = articles.count
            title = articles.first?.title ?? ""
        default:
            count = results.count
            title = results.first?.title ?? ""
        }
        SocialUIProof.record([
            "prompt": false,
            "type": spec.type,
            "count": count,
            "title": title,
            "error": failure
        ])
    }

    @discardableResult
    private func run(reset: Bool) async -> String {
        let word = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return "" }
        if reset {
            page = 1
            if model.flag("记录搜索历史") {
                model.searchHistory.removeAll { $0 == word }
                model.searchHistory.insert(word, at: 0)
                model.searchHistory = Array(model.searchHistory.prefix(20))
                model.save()
            }
        } else {
            page += 1
        }
        searching = true
        defer { searching = false }
        let orderValue = tab == "视频" || tab == "综合" ? (Menus.videoOrders.first { $0.0 == order }?.1 ?? "totalrank") : ""
        let durationValue = tab == "视频" || tab == "综合" ? (Menus.durations.first { $0.0 == duration }?.1 ?? 0) : 0
        let tid = tab == "视频" || tab == "综合" ? (Menus.zones.first { $0.0 == zone }?.1 ?? 0) : 0
        let type = SocialRequest.searchType(for: tab)
        do {
            let found = try await model.client.search(type: type, keyword: word, page: page, order: orderValue, duration: durationValue, tid: tid)
            if reset {
                results = []
                users = []
                seasons = []
                rooms = []
                articles = []
            }
            switch tab {
            case "用户":
                let known = Set(users.map(\.mid))
                users.append(contentsOf: found.users.filter { !known.contains($0.mid) })
            case "番剧", "影视":
                let known = Set(seasons.map(\.seasonID))
                seasons.append(contentsOf: found.seasons.filter { !known.contains($0.seasonID) })
            case "直播间":
                let known = Set(rooms.map(\.id))
                rooms.append(contentsOf: found.lives.filter { !known.contains($0.id) })
            case "专栏":
                let known = Set(articles.map(\.id))
                articles.append(contentsOf: found.articles.filter { !known.contains($0.id) })
            default:
                let known = Set(results.map(\.bvid))
                let pageItems = found.videos.filter { !known.contains($0.bvid) }
                results.append(contentsOf: pageItems)
                pageItems.forEach(model.store)
            }
            if reset && !hasResults {
                let text = found.note.isEmpty ? "未搜索到「\(word)」" : "未搜索到「\(word)」 \(found.note)"
                if LaunchMode.searchCapture == nil { model.show(text) }
                return text
            }
            return ""
        } catch {
            let text = error.localizedDescription
            if LaunchMode.searchCapture == nil { model.show(text) }
            return text
        }
    }
}

struct FlowTags: View {
    let items: [String]
    var tap: (String) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(items, id: \.self) { item in
                    Button(item) { tap(item) }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .selectionCapsule(selected: false)
                }
            }
        }
    }
}
