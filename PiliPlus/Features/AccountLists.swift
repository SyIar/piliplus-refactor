import SwiftUI

struct LoginPrompt: View {
    @Environment(AppModel.self) private var model
    let title: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text("登录后同步账号里的内容")
        } actions: {
            Button("登录") { model.open(.login) }
                .buttonStyle(.borderedProminent)
                .tint(Palette.bili)
        }
    }
}

struct HistoryListView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmClear = false
    @State private var searching = false

    private var showPrompt: Bool { !model.loggedIn && !LaunchMode.accountPreview }
    private var rows: [VideoItem] { model.filtered(model.history) }
    private var libraryQuery: Binding<String> {
        Binding(get: { model.libraryQuery }, set: { model.libraryQuery = $0 })
    }

    var body: some View {
        Group {
            if showPrompt {
                LoginPrompt(title: "登录后查看观看记录", systemImage: "clock.arrow.circlepath")
            } else if model.history.isEmpty {
                ContentUnavailableView("没有观看记录", systemImage: "clock", description: Text("看过的视频会出现在这里"))
            } else {
                List {
                    ForEach(rows) { video in
                        AccountVideoRow(video: video)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await model.deleteHistory(video) }
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                            .onAppear {
                                guard video.bvid == rows.last?.bvid else { return }
                                Task { await model.loadHistory(reset: false) }
                            }
                    }
                }
                .listStyle(.plain)
                .searchable(text: libraryQuery, isPresented: $searching, prompt: "搜索观看记录")
            }
        }
        .navigationTitle("观看记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !showPrompt {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(model.historyPaused ? "继续记录" : "暂停记录", systemImage: model.historyPaused ? "play.circle" : "pause.circle") {
                        Task { await model.setHistoryPaused(!model.historyPaused) }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清空", systemImage: "trash") { confirmClear = true }
                        .disabled(model.history.isEmpty)
                }
            }
        }
        .confirmationDialog("清空观看记录？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清空", role: .destructive) { Task { await model.clearHistory() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("清空后无法恢复")
        }
        .task {
            await model.loadHistoryPause()
            await model.loadHistory(reset: true)
        }
        .onAppear {
            if !model.libraryQuery.isEmpty { searching = true }
            AccountUIProof.record([
                "prompt": showPrompt,
                "rows": showPrompt ? 0 : model.history.count,
                "error": ""
            ])
        }
    }
}

struct WatchLaterListView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmClear = false
    @State private var searching = false

    private var showPrompt: Bool { !model.loggedIn && !LaunchMode.accountPreview }
    private var rows: [VideoItem] { model.filtered(model.laterVideos) }
    private var libraryQuery: Binding<String> {
        Binding(get: { model.libraryQuery }, set: { model.libraryQuery = $0 })
    }

    var body: some View {
        Group {
            if showPrompt {
                LoginPrompt(title: "登录后查看稍后再看", systemImage: "clock")
            } else if model.laterVideos.isEmpty {
                ContentUnavailableView("稍后再看是空的", systemImage: "clock", description: Text("在视频页加入后会出现在这里"))
            } else {
                List {
                    ForEach(rows) { video in
                        AccountVideoRow(video: video)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await model.removeLater(video) }
                                } label: {
                                    Label("移出", systemImage: "minus.circle")
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .searchable(text: libraryQuery, isPresented: $searching, prompt: "搜索稍后再看")
            }
        }
        .navigationTitle("稍后再看")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !showPrompt {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清空", systemImage: "trash") { confirmClear = true }
                        .disabled(model.laterVideos.isEmpty)
                }
            }
        }
        .confirmationDialog("清空稍后再看？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清空", role: .destructive) { Task { await model.clearLater() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("清空后无法恢复")
        }
        .task { await model.loadLater() }
        .onAppear {
            if !model.libraryQuery.isEmpty { searching = true }
            AccountUIProof.record([
                "prompt": showPrompt,
                "rows": showPrompt ? 0 : model.laterVideos.count,
                "error": ""
            ])
        }
    }
}

struct FavoritesView: View {
    @Environment(AppModel.self) private var model
    @State private var creating = false
    @State private var draft = ""

    private var showPrompt: Bool { !model.loggedIn && !LaunchMode.accountPreview }

    var body: some View {
        Group {
            if showPrompt {
                LoginPrompt(title: "登录后查看收藏夹", systemImage: "star")
            } else if model.favFolders.isEmpty {
                ContentUnavailableView("没有收藏夹", systemImage: "star", description: Text("可以新建一个收藏夹"))
            } else {
                List {
                    ForEach(model.favFolders) { folder in
                        Button {
                            model.open(.folder(folder.id))
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(Palette.bili)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(folder.title)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text("\(folder.count) 个内容")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("我的收藏")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !showPrompt {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("新建收藏夹", systemImage: "folder.badge.plus") { creating = true }
                }
            }
        }
        .alert("新建收藏夹", isPresented: $creating) {
            TextField("名称", text: $draft)
            Button("创建") {
                let name = draft
                draft = ""
                Task { await model.createFolder(name) }
            }
            Button("取消", role: .cancel) { draft = "" }
        }
        .task { await model.loadFolders(rid: nil) }
        .onAppear {
            AccountUIProof.record([
                "prompt": showPrompt,
                "rows": 0,
                "folders": showPrompt ? 0 : model.favFolders.count,
                "titles": model.favFolders.map(\.title),
                "error": ""
            ])
        }
    }
}

struct FolderContentsView: View {
    @Environment(AppModel.self) private var model
    let mediaID: Int
    @State private var searching = false

    private var folder: FavFolder? { model.favFolders.first { $0.id == mediaID } }
    private var videos: [VideoItem] { model.folderVideos[mediaID] ?? [] }
    private var showPrompt: Bool { !model.loggedIn && !LaunchMode.accountPreview && LaunchMode.screen != "lib-fav" }
    private var libraryQuery: Binding<String> {
        Binding(get: { model.libraryQuery }, set: { model.libraryQuery = $0 })
    }

    var body: some View {
        Group {
            if showPrompt {
                LoginPrompt(title: "登录后查看收藏", systemImage: "star")
            } else if videos.isEmpty {
                ContentUnavailableView("收藏夹是空的", systemImage: "star", description: Text(folder?.title ?? "收藏"))
            } else {
                List {
                    ForEach(videos) { video in
                        HStack(spacing: 10) {
                            if model.libraryEditing {
                                Image(systemName: model.libraryPicked.contains(video.bvid) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(model.libraryPicked.contains(video.bvid) ? Palette.bili : .secondary)
                            }
                            AccountVideoRow(video: video, interactive: !model.libraryEditing)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard model.libraryEditing else { return }
                            if model.libraryPicked.contains(video.bvid) {
                                model.libraryPicked.remove(video.bvid)
                            } else {
                                model.libraryPicked.insert(video.bvid)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { await model.dealFavorite(video, add: [], remove: [mediaID]) }
                            } label: {
                                Label("移出", systemImage: "star.slash")
                            }
                        }
                        .onAppear {
                            guard video.bvid == videos.last?.bvid else { return }
                            Task { await model.loadFolder(mediaID, reset: false, keyword: model.libraryQuery, order: model.libraryOrder) }
                        }
                    }
                }
                .listStyle(.plain)
                .searchable(text: libraryQuery, isPresented: $searching, prompt: "搜索收藏")
                .onSubmit(of: .search) {
                    Task { await reload() }
                }
            }
        }
        .navigationTitle(folder?.title ?? "收藏")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !showPrompt {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu(model.libraryOrder) {
                        ForEach(["最近收藏", "最多播放", "最近投稿"], id: \.self) { option in
                            Button(option) {
                                model.libraryOrder = option
                                Task { await reload() }
                            }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(model.libraryEditing ? "完成" : "多选") {
                        model.libraryEditing.toggle()
                        if !model.libraryEditing { model.libraryPicked = [] }
                    }
                }
                if model.libraryEditing, !model.libraryPicked.isEmpty {
                    ToolbarItem(placement: .bottomBar) {
                        Button("删除 \(model.libraryPicked.count)", role: .destructive) {
                            let chosen = videos.filter { model.libraryPicked.contains($0.bvid) }
                            Task { await model.deleteFavoriteItems(chosen, mediaID: mediaID) }
                        }
                    }
                }
            }
        }
        .task {
            if !model.libraryQuery.isEmpty { searching = true }
            let primed = LaunchMode.screen == "lib-fav" && !videos.isEmpty
            if !primed {
                await model.loadFolder(mediaID, reset: true, keyword: model.libraryQuery, order: model.libraryOrder)
            }
        }
    }

    private func reload() async {
        await model.loadFolder(mediaID, reset: true, keyword: model.libraryQuery, order: model.libraryOrder)
    }
}

struct SubscriptionsPage: View {
    @Environment(AppModel.self) private var model

    private var showPrompt: Bool { !model.loggedIn && LaunchMode.screen != "lib-sub" }

    var body: some View {
        Group {
            if showPrompt {
                LoginPrompt(title: "登录后查看我的订阅", systemImage: "rectangle.stack")
            } else if model.followedBangumi.isEmpty && model.followedDrama.isEmpty && model.followedSeries.isEmpty {
                ContentUnavailableView("还没有订阅", systemImage: "rectangle.stack", description: Text("追番、追剧和合集会出现在这里"))
            } else {
                List {
                    showSection("追番", model.followedBangumi)
                    showSection("追剧", model.followedDrama)
                    showSection("合集", model.followedSeries)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("我的订阅")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: libraryQuery, prompt: "搜索订阅")
        .task { await load() }
    }

    private var libraryQuery: Binding<String> {
        Binding(get: { model.libraryQuery }, set: { model.libraryQuery = $0 })
    }

    @ViewBuilder
    private func showSection(_ title: String, _ items: [SeasonItem]) -> some View {
        let rows = model.filteredShows(items)
        if !rows.isEmpty {
            Section(title) {
                ForEach(rows) { item in
                    HStack(spacing: 12) {
                        RemoteImage(url: item.cover, maxPixel: 240)
                            .frame(width: 72, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                            if !item.subtitle.isEmpty {
                                Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    private func load() async {
        if LaunchMode.screen == "lib-sub", !model.followedSeries.isEmpty || !model.followedBangumi.isEmpty || !model.followedDrama.isEmpty {
            return
        }
        guard model.loggedIn, let mid = model.session?.mid, mid > 0 else { return }
        do {
            model.followedBangumi = try await model.client.followedShows(vmid: mid, type: 1, page: 1)
            model.followedDrama = try await model.client.followedShows(vmid: mid, type: 2, page: 1)
            model.followedSeries = try await model.client.collections(mid: mid)
        } catch {
            model.show(error.localizedDescription)
        }
    }
}

struct FavPickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let video: VideoItem
    @State private var selected: Set<Int> = []
    @State private var baseline: Set<Int> = []
    @State private var creating = false
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.favFolders) { folder in
                    Button {
                        if selected.contains(folder.id) { selected.remove(folder.id) } else { selected.insert(folder.id) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(folder.title)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text("\(folder.count) 个内容")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if selected.contains(folder.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Palette.bili)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    creating = true
                } label: {
                    Label("新建收藏夹", systemImage: "folder.badge.plus")
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("收藏到")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        let add = selected.subtracting(baseline).sorted()
                        let remove = baseline.subtracting(selected).sorted()
                        dismiss()
                        Task { await model.dealFavorite(video, add: add, remove: remove) }
                    }
                }
            }
            .tint(.primary)
            .alert("新建收藏夹", isPresented: $creating) {
                TextField("名称", text: $draft)
                Button("创建") {
                    let name = draft
                    draft = ""
                    Task { await model.createFolder(name) }
                }
                Button("取消", role: .cancel) { draft = "" }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.regularMaterial)
        .tint(.primary)
        .task { await prepare() }
        .onAppear {
            AccountUIProof.record([
                "prompt": false,
                "sheet": true,
                "folders": model.favFolders.count,
                "titles": model.favFolders.map(\.title),
                "error": ""
            ])
        }
    }

    private func prepare() async {
        if LaunchMode.accountPreview {
            let marked = Set(model.favFolders.filter(\.favored).map(\.id))
            selected = marked
            baseline = marked
            return
        }
        await model.loadFolders(rid: video.aid)
        let marked = Set(model.favFolders.filter(\.favored).map(\.id))
        selected = marked
        baseline = marked
    }
}

struct AccountVideoRow: View {
    @Environment(AppModel.self) private var model
    let video: VideoItem
    var interactive: Bool = true

    var body: some View {
        Button {
            guard interactive else { return }
            model.store(video)
            model.open(.video(video.bvid))
        } label: {
            HStack(alignment: .top, spacing: 12) {
                RemoteImage(url: video.cover, maxPixel: 320)
                    .frame(width: 128)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text(video.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(video.ownerName)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(-1)
                        Spacer(minLength: 8)
                        HStack(spacing: 8) {
                            if video.view > 0 {
                                countIcon("play.fill", CountText.format(video.view))
                            }
                            if video.danmaku > 0 {
                                countIcon("text.bubble.fill", CountText.format(video.danmaku))
                            }
                            if let mark = progressText {
                                Text(mark)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func countIcon(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            Text(text)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var progressText: String? {
        if video.progress < 0 { return "已看完" }
        if video.progress > 0 { return "看到 \(clock(video.progress))" }
        return nil
    }

    private func clock(_ seconds: Int) -> String {
        let value = max(0, seconds)
        let hours = value / 3600
        let minutes = (value % 3600) / 60
        let secs = value % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }
}
