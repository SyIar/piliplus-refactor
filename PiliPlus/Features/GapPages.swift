import SwiftUI

struct SharePosterPage: View {
    @Environment(AppModel.self) private var model
    @State private var video: VideoItem?
    @State private var failure = ""
    @State private var loading = true

    var body: some View {
        Group {
            if let video {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        poster(video)
                        if let url = URL(string: "https://www.bilibili.com/video/\(video.bvid)") {
                            ShareLink(item: url) {
                                Label("系统分享", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Palette.bili)
                        }
                    }
                    .padding(16)
                }
            } else if loading {
                ProgressView("正在生成海报")
            } else {
                ContentUnavailableView("海报生成不了", systemImage: "photo", description: Text(failure))
            }
        }
        .navigationTitle("分享海报")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func poster(_ video: VideoItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            RemoteImage(url: video.cover, maxPixel: 640)
                .frame(maxWidth: .infinity)
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(video.title)
                .font(.title3.bold())
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ProfileMark(name: video.ownerName, face: video.ownerFace, size: 28)
                Text(video.ownerName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if video.view > 0 {
                    Text("\(CountText.format(video.view)) 播放")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(video.bvid)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Text("https://www.bilibili.com/video/\(video.bvid)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("哔哩哔哩")
                .font(.caption.weight(.bold))
                .foregroundStyle(Palette.bili)
        }
        .padding(16)
        .contentPlate(radius: 22)
    }

    private func load() async {
        guard let item = await model.publicVideo(preferred: model.shareBVID) else {
            loading = false
            failure = "没有可用的视频"
            GapProof.record(["state": "error", "rows": 0, "title": "", "bvid": "", "names": [String](), "covers": 0, "error": failure])
            return
        }
        await ImageStore.shared.prepare(urls: [item.cover, item.ownerFace], maxPixel: 640)
        video = item
        loading = false
        GapProof.record([
            "state": "rows",
            "rows": 1,
            "title": item.title,
            "bvid": item.bvid,
            "names": [item.ownerName],
            "covers": ImageStore.preparedCount,
            "error": ""
        ])
    }
}

struct CastPage: View {
    @Environment(AppModel.self) private var model
    @State private var video: VideoItem?
    @State private var devices: [CastDevice] = []
    @State private var failure = ""
    @State private var searching = true

    var body: some View {
        Group {
            if let video {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(video.title)
                                .font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(video.bvid)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            if !video.ownerName.isEmpty {
                                Text(video.ownerName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section("设备") {
                        if searching {
                            ProgressView("正在搜索投屏设备")
                        } else if devices.isEmpty {
                            ContentUnavailableView("没有发现投屏设备", systemImage: "tv.slash", description: Text("已搜索局域网中的 MediaRenderer"))
                        } else {
                            ForEach(devices) { device in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name).lineLimit(2)
                                    Text(device.location)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        Button(searching ? "搜索中" : "搜索设备") {
                            Task { await search(video) }
                        }
                        .disabled(searching)
                    }
                }
            } else if searching {
                ProgressView("正在准备投屏")
            } else {
                ContentUnavailableView("没有可投屏的视频", systemImage: "tv", description: Text(failure))
            }
        }
        .navigationTitle("投屏")
        .navigationBarTitleDisplayMode(.inline)
        .task { await prepare() }
    }

    private func prepare() async {
        guard let item = await model.publicVideo(preferred: model.shareBVID) else {
            searching = false
            failure = "没有可用的视频"
            GapProof.record(["state": "error", "rows": 0, "title": "", "bvid": "", "names": [String](), "note": "", "error": failure])
            return
        }
        video = item
        await search(item)
    }

    private func search(_ item: VideoItem) async {
        searching = true
        let found = await CastFinder.search()
        devices = found
        searching = false
        if found.isEmpty {
            GapProof.record([
                "state": "empty",
                "rows": 0,
                "title": item.title,
                "bvid": item.bvid,
                "names": [String](),
                "note": "没有发现投屏设备",
                "error": ""
            ])
        } else {
            GapProof.record([
                "state": "rows",
                "rows": found.count,
                "title": item.title,
                "bvid": item.bvid,
                "names": found.map(\.name),
                "note": "",
                "error": ""
            ])
        }
    }
}

struct WebDAVPage: View {
    @Environment(AppModel.self) private var model
    @State private var status = ""
    @State private var busy = false

    var body: some View {
        List {
            Section("服务器") {
                TextField("WebDAV 地址", text: binding("WebDAV 地址"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("用户名", text: binding("用户名"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("密码", text: binding("密码"))
            }
            Section {
                Button("备份设置") { Task { await backup() } }
                    .disabled(busy)
                Button("恢复设置") { Task { await restore() } }
                    .disabled(busy)
            }
            if !status.isEmpty || !(model.values["应用主题"] ?? "").isEmpty {
                Section("结果") {
                    if !status.isEmpty {
                        Text(status)
                    }
                    LabeledContent("应用主题", value: model.values["应用主题"] ?? "哔哩粉")
                }
            }
        }
        .navigationTitle("WebDAV")
        .navigationBarTitleDisplayMode(.inline)
        .task { await proveIfNeeded() }
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(
            get: { model.values[key] ?? "" },
            set: {
                model.values[key] = $0
                model.save()
            }
        )
    }

    private func backup() async {
        busy = true
        status = await model.backupSettingsToWebDAV()
        busy = false
        model.show(status)
    }

    private func restore() async {
        busy = true
        status = await model.restoreSettingsFromWebDAV()
        busy = false
        model.show(status)
    }

    private func proveIfNeeded() async {
        guard LaunchMode.screen == "gap-webdav" else { return }
        let address = model.values["WebDAV 地址"] ?? ""
        model.values["应用主题"] = "蓝色"
        model.save()
        let backed = await model.backupSettingsToWebDAV()
        guard backed == "已备份" else {
            status = backed
            GapProof.record([
                "state": "error",
                "rows": 0,
                "title": "应用主题",
                "query": address,
                "note": "",
                "error": backed
            ])
            return
        }
        model.values["应用主题"] = "绿色"
        model.save()
        let restored = await model.restoreSettingsFromWebDAV()
        let theme = model.values["应用主题"] ?? ""
        let ok = restored == "已恢复" && theme == "蓝色"
        status = ok ? "已从 WebDAV 恢复" : restored
        GapProof.record([
            "state": ok ? "rows" : "error",
            "rows": ok ? 1 : 0,
            "title": "应用主题",
            "query": address,
            "note": theme,
            "error": ok ? "" : "\(restored) \(theme)"
        ])
    }
}

struct UpdatePage: View {
    @Environment(AppModel.self) private var model
    @State private var release: ReleaseNote?
    @State private var failure = ""
    @State private var loading = true

    var body: some View {
        Group {
            if let release {
                List {
                    Section {
                        LabeledContent("当前版本", value: ReleaseCheck.current)
                        LabeledContent("最新版本", value: release.tag)
                        LabeledContent("名称", value: release.name)
                        LabeledContent("状态", value: ReleaseCheck.headline(current: ReleaseCheck.current, tag: release.tag))
                    }
                    Section("更新说明") {
                        let blocks = ReleaseNotes.blocks(from: release.notes)
                        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                            ReleaseNotesRow(block: block)
                        }
                    }
                }
            } else if loading {
                ProgressView("正在检查更新")
            } else {
                ContentUnavailableView("更新检查失败", systemImage: "arrow.down.circle", description: Text(failure))
            }
        }
        .navigationTitle("检查更新")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            let note = try await ReleaseCheck.latest()
            release = note
            loading = false
            let excerpt = note.notes
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            GapProof.record([
                "state": "rows",
                "rows": 1,
                "title": note.name,
                "note": note.tag,
                "body": String(excerpt.prefix(180)),
                "names": [ReleaseCheck.headline(current: ReleaseCheck.current, tag: note.tag)],
                "error": ""
            ])
        } catch {
            loading = false
            failure = error.localizedDescription
            GapProof.record([
                "state": "error",
                "rows": 0,
                "title": "",
                "note": "",
                "body": "",
                "names": [String](),
                "error": failure
            ])
        }
    }
}

private struct ReleaseNotes {
    struct Block {
        var text: AttributedString
        var headerLevel: Int?
        var listMarker: String?
        var code: Bool
    }

    static func blocks(from source: String) -> [Block] {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let parsed = try? AttributedString(markdown: source, options: options) else {
            let plain = AttributedString(source.trimmingCharacters(in: .whitespacesAndNewlines))
            return plain.characters.isEmpty ? [] : [Block(text: plain, headerLevel: nil, listMarker: nil, code: false)]
        }
        var grouped: [(PresentationIntent, AttributedString)] = []
        for run in parsed.runs {
            let intent = run.presentationIntent ?? PresentationIntent()
            let piece = AttributedString(parsed[run.range])
            if let index = grouped.indices.last, grouped[index].0 == intent {
                var text = grouped[index].1
                text.append(piece)
                grouped[index].1 = text
            } else {
                grouped.append((intent, piece))
            }
        }
        return grouped.compactMap { intent, text in
            let trimmed = text.trimmingWhitespace()
            guard !trimmed.characters.isEmpty else { return nil }
            return Block(
                text: trimmed,
                headerLevel: headerLevel(intent),
                listMarker: listMarker(intent),
                code: isCodeBlock(intent)
            )
        }
    }

    private static func headerLevel(_ intent: PresentationIntent) -> Int? {
        for component in intent.components {
            if case .header(let level) = component.kind { return level }
        }
        return nil
    }

    private static func listMarker(_ intent: PresentationIntent) -> String? {
        var ordered = false
        var ordinal = 0
        var item = false
        for component in intent.components {
            switch component.kind {
            case .orderedList:
                ordered = true
            case .unorderedList:
                ordered = false
            case .listItem(let value):
                item = true
                ordinal = value
            default:
                break
            }
        }
        guard item else { return nil }
        if ordered, ordinal > 0 { return "\(ordinal)." }
        return "•"
    }

    private static func isCodeBlock(_ intent: PresentationIntent) -> Bool {
        intent.components.contains { component in
            if case .codeBlock = component.kind { return true }
            return false
        }
    }
}

private struct ReleaseNotesRow: View {
    let block: ReleaseNotes.Block

    var body: some View {
        if let level = block.headerLevel {
            Text(block.text)
                .font(level <= 2 ? .title3.bold() : .headline)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let marker = block.listMarker {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: marker == "•" ? 12 : nil, alignment: .trailing)
                Text(block.text)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if block.code {
            Text(block.text)
                .font(.callout.monospaced())
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(block.text)
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private extension AttributedString {
    func trimmingWhitespace() -> AttributedString {
        var copy = self
        while let first = copy.characters.first, first.isWhitespace {
            copy.characters.removeFirst()
        }
        while let last = copy.characters.last, last.isWhitespace {
            copy.characters.removeLast()
        }
        return copy
    }
}
