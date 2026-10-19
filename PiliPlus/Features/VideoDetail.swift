import SwiftUI

struct VideoDetailTabs: View {
    @Environment(AppModel.self) private var model
    let video: VideoItem
    @Binding var tab: String
    @Binding var showDanmaku: Bool

    var body: some View {
        HStack(spacing: 18) {
            tabTitle("简介", tag: "简介")
            if model.flag("显示视频评论") {
                tabTitle(replyTitle, tag: "评论")
            }
            Spacer(minLength: 8)
            Button("发弹幕") { showDanmaku = true }
                .font(.subheadline)
                .foregroundStyle(.primary)
                .buttonStyle(.plain)
            Button {
                model.danmakuOn.toggle()
                model.setFlag("弹幕开关", model.danmakuOn)
            } label: {
                Image(systemName: model.danmakuOn ? "text.bubble.fill" : "text.bubble")
                    .font(.body)
                    .foregroundStyle(model.danmakuOn ? Palette.bili : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.danmakuOn ? "关闭弹幕" : "打开弹幕")
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private var replyTitle: String {
        video.reply > 0 ? "评论 \(CountText.format(video.reply))" : "评论"
    }

    private func tabTitle(_ title: String, tag: String) -> some View {
        let selected = tab == tag
        return Button { tab = tag } label: {
            VStack(spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                Capsule()
                    .fill(selected ? Color.primary : Color.clear)
                    .frame(width: selected ? 18 : 0, height: 2)
            }
        }
        .buttonStyle(.plain)
    }
}

struct VideoDetailIntro: View {
    @Environment(AppModel.self) private var model
    let video: VideoItem
    let related: [VideoItem]
    @Binding var expanded: Bool
    @Binding var coinPick: Int
    @Binding var showCoin: Bool
    @Binding var showFav: Bool
    @Binding var showShare: Bool
    var pageIndex: Int
    var autoplayNote: String = ""
    var onSelectPage: (Int, VideoPage) -> Void
    var onSelectEpisode: (EpisodeItem) -> Void = { _ in }

    @State private var fans = 0
    @State private var videos = 0
    @State private var followed = false
    @State private var pagesOpen = false
    @State private var collectionOpen = false
    @State private var seasonOpen = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !autoplayNote.isEmpty {
                    Text(autoplayNote)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.bili)
                }
                ownerRow
                titleBlock
                metaLine
                VideoActionRow(video: video, coinPick: $coinPick, showCoin: $showCoin, showFav: $showFav, showShare: $showShare)
                if video.pageCount > 1 {
                    disclosureRow(title: "分P", detail: "\(min(pageIndex + 1, video.pageCount))/\(video.pageCount)") {
                        pagesOpen.toggle()
                    }
                    if pagesOpen { pageList }
                }
                if !video.collectionTitle.isEmpty {
                    disclosureRow(
                        title: "合集：\(video.collectionTitle)",
                        detail: video.collectionCount > 0 ? "\(max(video.collectionIndex, 1))/\(video.collectionCount)" : ""
                    ) {
                        collectionOpen.toggle()
                    }
                    if collectionOpen { collectionList }
                }
                if model.seasonEpisodes.count >= 2 {
                    disclosureRow(
                        title: "合集：\(model.seasonTitle.isEmpty ? "选集" : model.seasonTitle)",
                        detail: "\(seasonIndex)/\(model.seasonEpisodes.count)"
                    ) {
                        seasonOpen.toggle()
                    }
                    if seasonOpen { seasonList }
                }
                if let summary = aiSummary {
                    aiRow(summary)
                }
                if model.flag("视频页显示相关视频"), !offline, !shownRelated.isEmpty {
                    VStack(spacing: 2) {
                        ForEach(shownRelated) { item in
                            RelatedVideoRow(video: item)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .task(id: video.ownerMid) { await loadOwner() }
        .onAppear {
            if model.flag("默认展开视频简介") { expanded = true }
        }
    }

    private var offline: Bool { video.playURL?.hasPrefix("file:") == true }

    private var shownRelated: [VideoItem] { related.filter { !model.hidesRelated($0) } }

    private var aiSummary: String? { nil }

    private var ownerRow: some View {
        HStack(spacing: 8) {
            Button { model.open(.user(video.ownerMid, video.ownerName)) } label: {
                HStack(spacing: 8) {
                    RemoteImage(url: video.ownerFace, ratio: 1, maxPixel: 96)
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(video.ownerName)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if !ownerMeta.isEmpty {
                            Text(ownerMeta)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            Button {
                Task {
                    let next = !followed
                    if await model.followUser(mid: video.ownerMid, follow: next) {
                        followed = next
                    }
                }
            } label: {
                Text(followed ? "已关注" : "+ 关注")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(followed ? Color(.tertiarySystemFill) : Palette.bili, in: Capsule())
                    .foregroundStyle(followed ? Color.primary : Color.white)
            }
            .buttonStyle(.plain)
        }
    }

    private var ownerMeta: String {
        var parts: [String] = []
        if fans > 0 { parts.append("\(CountText.format(fans))粉丝") }
        if videos > 0 { parts.append("\(CountText.format(videos))视频") }
        return parts.joined(separator: " ")
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(video.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(expanded ? nil : 2)
            if expanded, !video.desc.isEmpty {
                Text(video.desc)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { expanded.toggle() }
    }

    private var metaLine: some View {
        HStack(spacing: 8) {
            if !offline || video.view > 0 {
                stat("play.fill", CountText.format(video.view))
            }
            if !offline || video.danmaku > 0 {
                stat("text.bubble", CountText.format(video.danmaku))
            }
            Text(VideoDetailText.published(video.pubdate))
                .lineLimit(1)
            if offline, !model.qualityName.isEmpty || !video.streamCodec.isEmpty {
                Text(offlineQuality)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var offlineQuality: String {
        [model.qualityName, video.streamCodec].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func stat(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            Text(text).lineLimit(1).fixedSize(horizontal: true, vertical: false)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func disclosureRow(title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if !detail.isEmpty {
                    Text(detail)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var pageList: some View {
        VStack(spacing: 0) {
            ForEach(Array(video.pages.enumerated()), id: \.element.id) { index, page in
                Button { onSelectPage(index, page) } label: {
                    HStack {
                        Text(page.title.isEmpty ? "P\(page.index)" : page.title)
                            .lineLimit(1)
                            .foregroundStyle(index == pageIndex ? Palette.bili : Color.primary)
                        Spacer()
                    }
                    .font(.subheadline)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var seasonIndex: Int {
        (model.seasonEpisodes.firstIndex { $0.bvid == video.bvid } ?? 0) + 1
    }

    private var seasonList: some View {
        VStack(spacing: 0) {
            ForEach(model.seasonEpisodes.prefix(12)) { episode in
                Button { onSelectEpisode(episode) } label: {
                    HStack {
                        Text(episode.label).lineLimit(1).foregroundStyle(.primary)
                        Spacer()
                        if episode.bvid == video.bvid {
                            Image(systemName: "play.fill").font(.caption2).foregroundStyle(Palette.bili)
                        }
                    }
                    .font(.subheadline)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var collectionList: some View {
        VStack(spacing: 0) {
            ForEach(video.collectionClips.prefix(12)) { clip in
                Button {
                    guard !clip.bvid.isEmpty else { return }
                    model.open(.video(clip.bvid))
                } label: {
                    HStack {
                        Text(clip.title).lineLimit(1).foregroundStyle(.primary)
                        Spacer()
                        if clip.index == video.collectionIndex {
                            Image(systemName: "play.fill").font(.caption2).foregroundStyle(Palette.bili)
                        }
                    }
                    .font(.subheadline)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func aiRow(_ summary: String) -> some View {
        DisclosureGroup {
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("AI 总结", systemImage: "sparkles")
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .tint(.secondary)
    }

    private func loadOwner() async {
        let brief = await model.client.ownerBrief(mid: video.ownerMid)
        fans = brief.fans
        videos = brief.videos
        followed = brief.followed
    }
}

struct RelatedVideoRow: View {
    @Environment(AppModel.self) private var model
    let video: VideoItem

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { open() } label: {
                RemoteImage(url: video.cover, ratio: 16.0 / 9.0, maxPixel: 240)
                    .frame(width: 128, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        if video.duration > 0 {
                            DurationBadge(seconds: video.duration).padding(4)
                        }
                    }
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Button { open() } label: {
                    Text(video.title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2, reservesSpace: true)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .buttonStyle(.plain)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Text(counts)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Menu {
                        Button("稍后再看", systemImage: "clock") { model.watchLater(video.bvid) }
                        Button("收藏", systemImage: "star") { model.favoriteQuick(video) }
                        Button("不感兴趣", systemImage: "hand.thumbsdown") { Task { await model.dislike(video) } }
                        if video.ownerMid > 0 {
                            Button("查看 UP", systemImage: "person") { model.open(.user(video.ownerMid, video.ownerName)) }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 22)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        let when = VideoDetailText.ago(video.pubdate)
        if when.isEmpty { return video.ownerName }
        if video.ownerName.isEmpty { return when }
        return "\(when) \(video.ownerName)"
    }

    private var counts: String {
        var parts: [String] = []
        if video.view > 0 { parts.append("\(CountText.format(video.view))播放") }
        if video.danmaku > 0 { parts.append("\(CountText.format(video.danmaku))弹幕") }
        return parts.joined(separator: " ")
    }

    private func open() {
        model.store(video)
        model.open(.video(video.bvid))
    }
}

enum DetailProof {
    static func record(title: String, owner: String, collection: String, related: Int, covers: Int) {
        guard LaunchMode.screen == "detail" || LaunchMode.screen == "detail-dark" else { return }
        let body: [String: Any] = [
            "screen": LaunchMode.screen ?? "",
            "title": title,
            "owner": owner,
            "collection": collection,
            "related": related,
            "covers": covers
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { return }
        try? data.write(to: LaunchClock.documents.appendingPathComponent("detail-proof.json"), options: .atomic)
    }
}

enum VideoDetailText {
    static func published(_ stamp: Int) -> String {
        guard stamp > 0 else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(stamp)))
    }

    static func ago(_ stamp: Int) -> String {
        guard stamp > 0 else { return "" }
        let delta = max(0, Int(Date().timeIntervalSince1970) - stamp)
        if delta < 3600 { return "\(max(1, delta / 60))分钟前" }
        if delta < 86_400 { return "\(delta / 3600)小时前" }
        if delta < 86_400 * 30 { return "\(delta / 86_400)天前" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(stamp)))
    }
}
