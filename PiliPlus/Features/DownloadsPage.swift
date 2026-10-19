import SwiftUI

struct DownloadsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let active = model.downloads.active
        let groups = model.downloads.completedGroups
        Group {
            if active.isEmpty && groups.isEmpty {
                ContentUnavailableView {
                    Label("没有离线视频", systemImage: "arrow.down.circle")
                } description: {
                    Text("在视频页选择画质、编码和分P后开始缓存")
                }
            } else {
                ScrollViewReader { proxy in
                    List {
                        if !active.isEmpty {
                            Section {
                                ForEach(active) { item in
                                    activeRow(item)
                                        .id(item.id)
                                        .listRowInsets(rowInsets)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button("删除", role: .destructive) { model.downloads.cancel(item.id) }
                                        }
                                }
                            } header: {
                                Text("正在下载 \(active.count)")
                                    .font(.subheadline)
                                    .textCase(nil)
                            }
                        }
                        if !groups.isEmpty {
                            Section {
                                ForEach(groups, id: \.bvid) { group in
                                    completedRow(group)
                                        .listRowInsets(rowInsets)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button("删除", role: .destructive) {
                                                for part in group.parts { model.downloads.cancel(part.id) }
                                            }
                                        }
                                }
                            } header: {
                                Text("已缓存 \(groups.count)")
                                    .font(.subheadline)
                                    .textCase(nil)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .environment(\.defaultMinListRowHeight, 44)
                    .onChange(of: model.downloads.mergeOffset) { _, value in
                        let anchor: UnitPoint = value % 2 == 0 ? .top : .bottom
                        if let id = active.first?.id ?? groups.first?.parts.first?.id {
                            proxy.scrollTo(id, anchor: anchor)
                        }
                    }
                }
            }
        }
        .navigationTitle("离线缓存")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("搜索") { model.open(.feature("离线缓存搜索")) }
            }
            ToolbarItem(placement: .bottomBar) {
                Text("已用 \(model.downloads.storageLabel)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .task {
            guard LaunchMode.screen == "downloads" else { return }
            await model.downloads.prove(using: model)
        }
    }

    private var rowInsets: EdgeInsets {
        EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 12)
    }

    private func activeRow(_ item: OfflineItem) -> some View {
        HStack(alignment: .center, spacing: 10) {
            cover(item)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(activeMeta(item))
                    .font(.caption)
                    .foregroundStyle(item.state == "failed" ? .red : .secondary)
                    .lineLimit(1)
                ProgressView(value: item.state == "queued" ? 0 : min(1, item.fraction))
                    .progressViewStyle(.linear)
                    .tint(Palette.bili)
            }
            controls(item)
        }
    }

    private func activeMeta(_ item: OfflineItem) -> String {
        if item.state == "failed" { return item.error.isEmpty ? item.label : item.error }
        let page = item.pageTitle.isEmpty ? "P\(item.page)" : item.pageTitle
        return "\(item.label) · \(page) · \(item.quality) · \(percent(item.fraction)) · \(bytes(item.bytesWritten))"
    }

    @ViewBuilder
    private func controls(_ item: OfflineItem) -> some View {
        if item.state == "running" {
            iconButton("pause.fill", "暂停") { model.downloads.pause(item.id) }
            iconButton("xmark", "取消") { model.downloads.cancel(item.id) }
        } else if item.state == "paused" || item.state == "failed" {
            iconButton("play.fill", item.state == "paused" ? "继续" : "重试") { model.downloads.resume(item.id) }
            iconButton("xmark", "取消") { model.downloads.cancel(item.id) }
        } else if item.state == "queued" || item.state == "merging" {
            iconButton("xmark", "取消") { model.downloads.cancel(item.id) }
        }
    }

    private func iconButton(_ system: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.caption.weight(.semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func completedRow(_ group: (bvid: String, title: String, parts: [OfflineItem])) -> some View {
        if group.parts.count > 1 {
            NavigationLink {
                DownloadPartsPage(bvid: group.bvid)
            } label: {
                mediaRow(item: group.parts[0], title: group.title, meta: groupMeta(group.parts))
            }
        } else if let item = group.parts.first {
            Button { model.playOffline(item) } label: {
                mediaRow(item: item, title: item.title, meta: groupMeta(group.parts))
            }
            .buttonStyle(.plain)
        }
    }

    private func mediaRow(item: OfflineItem, title: String, meta: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            cover(item)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(meta)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func groupMeta(_ parts: [OfflineItem]) -> String {
        let quality = parts.first?.quality ?? ""
        let size = parts.reduce(Int64(0)) { $0 + $1.bytesWritten }
        return "\(parts.count) P · \(quality) · \(bytes(size))"
    }

    @ViewBuilder
    private func cover(_ item: OfflineItem) -> some View {
        let url = OfflineFiles.cover(item)
        if let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 112, height: 63)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Palette.bili.opacity(0.16))
                .frame(width: 112, height: 63)
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.caption2)
                        .foregroundStyle(Palette.bili)
                }
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((min(1, max(0, value)) * 100).rounded()))%"
    }

    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

struct DownloadPartsPage: View {
    @Environment(AppModel.self) private var model
    let bvid: String

    var body: some View {
        let parts = model.downloads.completedGroups.first { $0.bvid == bvid }?.parts ?? []
        List {
            ForEach(parts) { item in
                Button { model.playOffline(item) } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.pageTitle.isEmpty ? "P\(item.page)" : item.pageTitle)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Text("\(item.quality) · \(ByteCountFormatter.string(fromByteCount: item.bytesWritten, countStyle: .file))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "play.fill")
                            .font(.caption)
                            .foregroundStyle(Palette.bili)
                    }
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("删除", role: .destructive) { model.downloads.cancel(item.id) }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(parts.first?.title ?? "分P")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DownloadSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let video: VideoItem
    @State private var quality: String
    @State private var codec: String
    @State private var allPages: Bool
    @State private var picked: Set<Int>

    init(video: VideoItem) {
        self.video = video
        let options = Self.qualities(for: video)
        _quality = State(initialValue: options.first ?? "高清 720P")
        _codec = State(initialValue: "avc1")
        _allPages = State(initialValue: true)
        _picked = State(initialValue: Set(Self.pages(for: video).map(\.cid)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("画质", selection: $quality) {
                    ForEach(Self.qualities(for: video), id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                Picker("编码", selection: $codec) {
                    Text("AVC").tag("avc1")
                    Text("HEVC").tag("hev1")
                    Text("AV1").tag("av1")
                }
                if Self.pages(for: video).count > 1 {
                    Toggle("全部分P", isOn: $allPages)
                    if !allPages {
                        Section("选择分P") {
                            ForEach(Self.pages(for: video)) { page in
                                Button {
                                    if picked.contains(page.cid) { picked.remove(page.cid) } else { picked.insert(page.cid) }
                                } label: {
                                    HStack {
                                        Text(page.title.isEmpty ? "P\(page.index)" : page.title)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if picked.contains(page.cid) {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(Palette.bili)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("离线缓存")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("开始缓存") { start() }
                        .disabled(chosen.isEmpty)
                }
            }
            .onAppear {
                let options = Self.qualities(for: video)
                let preferred = model.values["默认画质"] ?? ""
                if options.contains(preferred) { quality = preferred }
                let saved = model.values["首选解码格式"] ?? ""
                if ["avc1", "hev1", "av1"].contains(saved) { codec = saved }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var chosen: [VideoPage] {
        let pages = Self.pages(for: video)
        if allPages || pages.count <= 1 { return pages }
        return pages.filter { picked.contains($0.cid) }
    }

    private func start() {
        model.downloads.enqueue(video: video, pages: chosen, quality: quality, codec: codec, limit: model.cacheLimitBytes())
        dismiss()
        model.show("已加入离线缓存")
        model.open(.feature("离线缓存"))
    }

    private static func qualities(for video: VideoItem) -> [String] {
        if !video.qualities.isEmpty { return video.qualities }
        return ["流畅 360P", "清晰 480P", "高清 720P", "高清 1080P"]
    }

    private static func pages(for video: VideoItem) -> [VideoPage] {
        if video.pages.isEmpty {
            return [VideoPage(cid: video.cid, index: 1, title: "P1", duration: video.duration)]
        }
        return video.pages.filter { $0.cid > 0 }
    }
}
