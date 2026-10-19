import PhotosUI
import SwiftUI

struct DynamicPollBlock: View {
    let title: String
    let options: [String]
    let counts: [Int]
    let joined: Int

    /// A row of zeros is what we invent when `vote_info` has no counts. Real tallies include at least one positive number.
    private var showsCounts: Bool { counts.contains { $0 > 0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.isEmpty ? "投票" : title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                HStack(spacing: 8) {
                    Text(option).lineLimit(1)
                    Spacer(minLength: 8)
                    if showsCounts {
                        Text(CountText.format(index < counts.count ? counts[index] : 0))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            if joined > 0 {
                Text("\(CountText.format(joined))人参与")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct DynamicImageStrip: View {
    let images: [String]

    var body: some View {
        let shown = Array(images.prefix(3))
        HStack(spacing: 6) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, url in
                RemoteImage(url: url, ratio: 1, maxPixel: 360)
                    .frame(width: shown.count == 1 ? 180 : 96, height: shown.count == 1 ? 180 : 96)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

struct DynamicComposer: View {
    @Environment(AppModel.self) private var model
    var repost: DynamicItem?
    @State private var text = ""
    @State private var topic = ""
    @State private var picks: [PhotosPickerItem] = []
    @State private var localImages: [Data] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let repost {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(repost.name).font(.caption.weight(.semibold)).lineLimit(1)
                        Text(repost.text).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                TextField(repost == nil ? "说点什么" : "说说转发理由", text: $text, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
                if repost == nil {
                    TextField("话题", text: $topic)
                        .textFieldStyle(.roundedBorder)
                    PhotosPicker(selection: $picks, maxSelectionCount: 9, matching: .images) {
                        Label("添加图片", systemImage: "photo")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    if !localImages.isEmpty {
                        Text("已选 \(localImages.count) 张")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button(repost == nil ? "发布" : "转发") {
                    Task { await publish() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.bili)
                if !model.loggedIn {
                    Button("登录后发布") { model.open(.login) }
                        .buttonStyle(.bordered)
                }
            }
            .padding(16)
        }
        .navigationTitle(repost == nil ? "发布动态" : "转发动态")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: picks) { _, items in
            Task { await loadPicks(items) }
        }
        .onAppear { record() }
    }

    private func loadPicks(_ items: [PhotosPickerItem]) async {
        var loaded: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty {
                loaded.append(data)
            }
        }
        localImages = loaded
        record()
    }

    private func publish() async {
        if let repost {
            let ok = await model.repostDynamic(repost, text: text)
            if ok { model.pop() }
            return
        }
        let ok = await model.publishDynamic(text: text, images: localImages, topicName: topic)
        if ok { model.pop() }
    }

    private func record() {
        DynamicUIProof.record([
            "composer": true,
            "image": true,
            "loginGuide": !model.loggedIn,
            "repost": repost != nil,
            "source": repost?.text ?? "",
            "photos": localImages.count,
            "error": ""
        ])
    }
}

struct DynamicDetailPage: View {
    @Environment(AppModel.self) private var model
    let id: String
    @State private var item: DynamicItem?
    @State private var comments: [CommentItem] = []
    @State private var error = ""

    var body: some View {
        Group {
            if let item {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            author(item)
                            Text(item.text)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if !item.images.isEmpty {
                                DynamicImageStrip(images: item.images)
                            }
                            if item.hasPoll {
                                DynamicPollBlock(title: item.pollTitle, options: item.pollOptions, counts: item.pollCounts, joined: item.pollJoined)
                            }
                            if !item.origText.isEmpty {
                                Text(item.origText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            if !item.topicName.isEmpty {
                                Text("#\(item.topicName)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Palette.bili)
                            }
                            if let video = item.video {
                                VideoCard(video: video)
                            }
                            HStack {
                                ActionChip(system: "arrow.2.squarepath", title: CountText.format(item.repost)) {
                                    model.dynamicFocus = item
                                    model.open(.feature("转发动态"))
                                }
                                ActionChip(system: "text.bubble", title: CountText.format(item.comment)) {
                                    withAnimation { proxy.scrollTo("dyn-comments", anchor: .top) }
                                }
                                ActionChip(system: item.liked ? "hand.thumbsup.fill" : "hand.thumbsup", title: CountText.format(item.like), selected: item.liked) {
                                    Task { await model.likeDynamic(item) }
                                }
                            }
                            CommentThreadList(
                                oid: item.commentID,
                                type: item.commentType,
                                initial: comments,
                                embedded: true
                            )
                            .id("dyn-comments")
                        }
                        .padding(16)
                    }
                }
            } else if !error.isEmpty {
                ContentUnavailableView("无法打开动态", systemImage: "text.bubble", description: Text(error))
            } else {
                ProgressView("正在加载")
            }
        }
        .navigationTitle("动态")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func author(_ item: DynamicItem) -> some View {
        HStack(spacing: 8) {
            RemoteImage(url: item.face, ratio: 1, maxPixel: 120)
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(item.time).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func load() async {
        let seed = model.dynamicFocus?.id == id ? model.dynamicFocus : nil
        do {
            var loaded: DynamicItem
            if id.isEmpty {
                throw BiliError.message(model.dynamicError.isEmpty ? "没有找到动态" : model.dynamicError)
            } else if var full = try? await model.client.dynamicDetail(id: id) {
                if let seed, !seed.text.isEmpty {
                    let trimmed = full.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty || trimmed == full.kind || trimmed == "动态" {
                        full.text = seed.text
                    }
                }
                if full.images.isEmpty, let seed { full.images = seed.images }
                if !full.hasPoll, let seed, seed.hasPoll {
                    full.pollTitle = seed.pollTitle
                    full.pollOptions = seed.pollOptions
                    full.pollCounts = seed.pollCounts
                    full.pollJoined = seed.pollJoined
                }
                if full.commentID == 0, let seed { full.commentID = seed.commentID }
                if full.commentType == 0, let seed { full.commentType = seed.commentType }
                loaded = full
            } else if let seed {
                loaded = seed
            } else {
                throw BiliError.message("这条动态没有打开")
            }
            let sort = model.values["评论展示"] == "按时间" ? 0 : 1
            let rows = loaded.commentID > 0 && loaded.commentType > 0
                ? ((try? await model.client.replies(oid: loaded.commentID, type: loaded.commentType, page: 1, sort: sort)) ?? [])
                : []
            await ImageStore.shared.prepare(urls: loaded.images, maxPixel: 360)
            let covers = ImageStore.preparedCount
            await ImageStore.shared.prepare(urls: loaded.face.isEmpty ? [] : [loaded.face], maxPixel: 120)
            comments = rows
            item = loaded
            DynamicUIProof.record([
                "text": loaded.text,
                "author": loaded.name,
                "images": loaded.images.count,
                "covers": covers,
                "poll": loaded.hasPoll,
                "options": loaded.pollOptions.count,
                "pollTitle": loaded.pollTitle,
                "maxCount": loaded.pollCounts.max() ?? 0,
                "topic": loaded.topicName,
                "comments": rows.count,
                "commentType": loaded.commentType,
                "error": ""
            ])
        } catch {
            self.error = error.localizedDescription
            DynamicUIProof.record([
                "text": "",
                "author": "",
                "images": 0,
                "poll": false,
                "options": 0,
                "pollTitle": "",
                "topic": "",
                "error": self.error
            ])
        }
    }
}

struct TopicHome: View {
    @Environment(AppModel.self) private var model
    @State private var hot: [TopicItem] = []
    @State private var followed: [TopicItem] = []
    @State private var error = ""

    private var followingPrompt: Bool { !model.loggedIn }

    var body: some View {
        List {
            Section("关注话题") {
                if followingPrompt {
                    Button("登录后查看关注话题") { model.open(.login) }
                } else if followed.isEmpty {
                    Text("还没有关注话题").foregroundStyle(.secondary)
                } else {
                    ForEach(followed) { topic in
                        topicRow(topic)
                    }
                }
            }
            Section("话题") {
                if hot.isEmpty, !error.isEmpty {
                    Text(error).foregroundStyle(.secondary)
                }
                ForEach(hot) { topic in
                    topicRow(topic)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("话题")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func topicRow(_ topic: TopicItem) -> some View {
        Button {
            model.open(.topic(topic.id, topic.name))
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.name).foregroundStyle(.primary).lineLimit(1)
                Text(meta(topic))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func meta(_ topic: TopicItem) -> String {
        var parts: [String] = []
        if topic.view > 0 { parts.append("\(CountText.format(topic.view))浏览") }
        if topic.discuss > 0 { parts.append("\(CountText.format(topic.discuss))讨论") }
        if parts.isEmpty { return topic.summary }
        return parts.joined(separator: " ")
    }

    private func load() async {
        do {
            hot = try await model.client.hotTopics()
            if model.loggedIn {
                followed = (try? await model.client.followedTopics()) ?? []
            }
            await ImageStore.shared.prepare(urls: [], maxPixel: 120)
            DynamicUIProof.record([
                "hot": hot.count,
                "followed": followed.count,
                "followingPrompt": followingPrompt,
                "error": hot.isEmpty ? "话题是空的" : ""
            ])
            if hot.isEmpty { error = "话题是空的" }
        } catch {
            self.error = error.localizedDescription
            DynamicUIProof.record([
                "hot": 0,
                "followed": 0,
                "followingPrompt": followingPrompt,
                "error": self.error
            ])
        }
    }
}

struct TopicDetailPage: View {
    @Environment(AppModel.self) private var model
    let id: Int
    let name: String
    @State private var rows: [DynamicItem] = []
    @State private var error = ""

    var body: some View {
        List {
            if !error.isEmpty, rows.isEmpty {
                Text(error).foregroundStyle(.secondary)
            }
            ForEach(rows) { item in
                Button {
                    model.dynamicFocus = item
                    model.open(.dynamic(item.id))
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.name).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                        Text(item.text).font(.subheadline).foregroundStyle(.primary).lineLimit(2)
                        if !item.images.isEmpty {
                            DynamicImageStrip(images: item.images)
                        }
                        if item.hasPoll {
                            DynamicPollBlock(title: item.pollTitle, options: item.pollOptions, counts: item.pollCounts, joined: item.pollJoined)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .navigationTitle(name.isEmpty ? "话题" : name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            rows = try await model.client.topicDynamics(id: id)
            let shown = Array(rows.flatMap { $0.images.prefix(1) }.prefix(3))
            await ImageStore.shared.prepare(urls: shown, maxPixel: 360)
            DynamicUIProof.record([
                "topic": name,
                "rows": rows.count,
                "images": shown.count,
                "covers": ImageStore.preparedCount,
                "error": rows.isEmpty ? "这个话题还没有动态" : ""
            ])
            if rows.isEmpty { error = "这个话题还没有动态" }
        } catch {
            self.error = error.localizedDescription
            DynamicUIProof.record(["topic": name, "rows": 0, "error": self.error])
        }
    }
}
