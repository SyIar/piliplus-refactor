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

    private var showPrompt: Bool { !model.loggedIn && !LaunchMode.accountPreview }

    var body: some View {
        Group {
            if showPrompt {
                LoginPrompt(title: "登录后查看观看记录", systemImage: "clock.arrow.circlepath")
            } else if model.history.isEmpty {
                ContentUnavailableView("没有观看记录", systemImage: "clock", description: Text("看过的视频会出现在这里"))
            } else {
                List {
                    ForEach(model.history) { video in
                        AccountVideoRow(video: video)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await model.deleteHistory(video) }
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                            .onAppear {
                                guard video.bvid == model.history.last?.bvid else { return }
                                Task { await model.loadHistory(reset: false) }
                            }
                    }
                }
                .listStyle(.plain)
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

    private var showPrompt: Bool { !model.loggedIn && !LaunchMode.accountPreview }

    var body: some View {
        Group {
            if showPrompt {
                LoginPrompt(title: "登录后查看稍后再看", systemImage: "clock")
            } else if model.laterVideos.isEmpty {
                ContentUnavailableView("稍后再看是空的", systemImage: "clock", description: Text("在视频页加入后会出现在这里"))
            } else {
                List {
                    ForEach(model.laterVideos) { video in
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

    private var folder: FavFolder? { model.favFolders.first { $0.id == mediaID } }
    private var videos: [VideoItem] { model.folderVideos[mediaID] ?? [] }
    private var showPrompt: Bool { !model.loggedIn && !LaunchMode.accountPreview }

    var body: some View {
        Group {
            if showPrompt {
                LoginPrompt(title: "登录后查看收藏", systemImage: "star")
            } else if videos.isEmpty {
                ContentUnavailableView("收藏夹是空的", systemImage: "star", description: Text(folder?.title ?? "收藏"))
            } else {
                List {
                    ForEach(videos) { video in
                        AccountVideoRow(video: video)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await model.dealFavorite(video, add: [], remove: [mediaID]) }
                                } label: {
                                    Label("移出", systemImage: "star.slash")
                                }
                            }
                            .onAppear {
                                guard video.bvid == videos.last?.bvid else { return }
                                Task { await model.loadFolder(mediaID, reset: false) }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(folder?.title ?? "收藏")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadFolder(mediaID, reset: true) }
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

    var body: some View {
        Button {
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
