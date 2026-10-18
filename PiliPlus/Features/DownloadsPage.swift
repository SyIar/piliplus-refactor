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
                            Section("正在下载") {
                                ForEach(active) { item in
                                    activeRow(item)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button("删除", role: .destructive) { model.downloads.cancel(item.id) }
                                        }
                                }
                            }
                        }
                        ForEach(groups, id: \.bvid) { group in
                            Section(group.title) {
                                ForEach(group.parts) { item in
                                    Button { model.playOffline(item) } label: {
                                        completedRow(item)
                                    }
                                    .buttonStyle(.plain)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button("删除", role: .destructive) { model.downloads.cancel(item.id) }
                                    }
                                }
                            }
                        }
                    }
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
            ToolbarItem(placement: .bottomBar) {
                Text("已用 \(model.downloads.storageLabel)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            guard LaunchMode.screen == "downloads" else { return }
            await model.downloads.prove(using: model)
        }
    }

    private func activeRow(_ item: OfflineItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text("\(item.pageTitle) · \(item.quality) · \(item.codec)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if item.state == "merging" {
                ProgressView()
            } else {
                ProgressView(value: item.fraction)
            }
            HStack {
                Text(item.state == "failed" ? item.error : "\(item.label) · \(percent(item.fraction)) · \(bytes(item.bytesWritten))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                controls(item)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func controls(_ item: OfflineItem) -> some View {
        if item.state == "running" {
            Button("暂停", systemImage: "pause.fill") { model.downloads.pause(item.id) }
                .buttonStyle(.borderless)
            Button("取消", systemImage: "xmark") { model.downloads.cancel(item.id) }
                .buttonStyle(.borderless)
        } else if item.state == "paused" || item.state == "failed" {
            Button(item.state == "paused" ? "继续" : "重试", systemImage: "play.fill") { model.downloads.resume(item.id) }
                .buttonStyle(.borderless)
            Button("取消", systemImage: "xmark") { model.downloads.cancel(item.id) }
                .buttonStyle(.borderless)
        } else if item.state == "queued" || item.state == "merging" {
            Button("取消", systemImage: "xmark") { model.downloads.cancel(item.id) }
                .buttonStyle(.borderless)
        }
    }

    private func completedRow(_ item: OfflineItem) -> some View {
        HStack(spacing: 12) {
            cover(item)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.pageTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("\(item.quality) · \(item.codec) · \(bytes(item.bytesWritten))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "play.circle")
                .foregroundStyle(Palette.bili)
        }
    }

    @ViewBuilder
    private func cover(_ item: OfflineItem) -> some View {
        let url = OfflineFiles.cover(item)
        if let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 96, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.bili.opacity(0.2))
                .frame(width: 96, height: 54)
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((min(1, max(0, value)) * 100).rounded()))%"
    }

    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
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
