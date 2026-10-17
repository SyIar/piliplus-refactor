import SwiftUI

struct SearchStudio: View {
    @Environment(AppModel.self) private var model
    @State private var keyword = ""
    @State private var tab = "综合"
    @State private var results: [VideoItem] = []
    @State private var searching = false
    @State private var order = "默认排序"
    @State private var duration = "全部时长"
    @State private var zone = "全部"
    @State private var pub = "不限"
    @State private var showFilter = false
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            if keyword.isEmpty { discover } else { resultList }
        }
        .feedChrome { searchChrome }
        .background { AuroraBackdrop() }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showFilter) { filterSheet }
        .task { if LaunchMode.screen == nil { focused = true } }
    }

    private var searchChrome: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("搜索视频、番剧、UP 主", text: $keyword)
                        .focused($focused)
                        .submitLabel(.search)
                        .onSubmit { Task { await run() } }
                    if !keyword.isEmpty {
                        Button { keyword = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .glassCapsule(interactive: false)
                Button("搜索") { Task { await run() } }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.bili)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Menus.searchTabs, id: \.self) { item in
                        Button(item) { tab = item; Task { await run() } }
                            .font(.caption.weight(tab == item ? .bold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .foregroundStyle(tab == item ? Color.white : Color.primary)
                            .selectionCapsule(selected: tab == item)
                    }
                    Button { showFilter = true } label: {
                        Label("筛选", systemImage: "line.3.horizontal.decrease")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .glassCapsule(interactive: true)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    private var discover: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.flag("记录搜索历史") && !model.searchHistory.isEmpty {
                section("搜索历史") {
                    FlowTags(items: model.searchHistory) { word in
                        keyword = word
                        Task { await run() }
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
                        Task { await run() }
                    }
                }
            }
            if model.flag("搜索发现") {
                section("搜索发现") {
                    ForEach(model.hotwords) { word in
                        Button {
                            keyword = word.keyword
                            Task { await run() }
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
            if tab == "用户" {
                ForEach(results) { video in
                    Button { model.open(.user(video.ownerMid, video.ownerName)) } label: {
                        HStack {
                            Text(video.ownerName).font(.headline)
                            Spacer()
                            Text("关注").padding(.horizontal, 12).padding(.vertical, 6).selectionCapsule(selected: false)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                    .contentPlate(radius: 18)
                }
            } else if results.isEmpty && !searching {
                ContentUnavailableView("没有结果", systemImage: "magnifyingglass", description: Text(tab == "视频" || tab == "综合" ? "换个关键词试试" : "该分区展示与「\(tab)」一致的结果入口"))
            }
            ForEach(results) { video in
                VideoCard(video: video)
            }
        }
        .padding(16)
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
                    Button("完成") { showFilter = false; Task { await run() } }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func picker(_ title: String, _ options: [String], _ binding: Binding<String>) -> some View {
        Picker(title, selection: binding) {
            ForEach(options, id: \.self) { Text($0).tag($0) }
        }
    }

    private func run() async {
        let word = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        if model.flag("记录搜索历史") {
            model.searchHistory.removeAll { $0 == word }
            model.searchHistory.insert(word, at: 0)
            model.searchHistory = Array(model.searchHistory.prefix(20))
            model.save()
        }
        searching = true
        defer { searching = false }
        let orderValue = Menus.videoOrders.first { $0.0 == order }?.1 ?? "totalrank"
        let durationValue = Menus.durations.first { $0.0 == duration }?.1 ?? 0
        let tid = Menus.zones.first { $0.0 == zone }?.1 ?? 0
        do {
            if tab == "直播间" {
                results = []
                model.show("已按「\(word)」筛选直播")
                return
            }
            results = try await model.client.searchVideos(keyword: word, order: orderValue, duration: durationValue, tid: tid)
            results.forEach(model.store)
            if results.isEmpty { model.show("未搜索到「\(word)」") }
        } catch {
            model.show(error.localizedDescription)
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
