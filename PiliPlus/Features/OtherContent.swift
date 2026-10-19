import SwiftUI

struct ArticleReaderPage: View {
    @Environment(AppModel.self) private var model
    @State private var article: ArticleDoc?
    @State private var failure = ""
    @State private var loading = true

    var body: some View {
        Group {
            if let article {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(article.title)
                            .font(.title2.bold())
                        if !article.author.isEmpty {
                            Text(article.author)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if !article.cover.isEmpty {
                            RemoteImage(url: article.cover, maxPixel: 640)
                                .frame(maxWidth: .infinity)
                                .frame(height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(Array(paragraphs(article.body).enumerated()), id: \.offset) { _, paragraph in
                                Text(paragraph)
                                    .font(.body)
                                    .lineSpacing(8)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(16)
                }
            } else if loading {
                ProgressView("正在打开专栏")
            } else {
                ContentUnavailableView("专栏打不开", systemImage: "doc.text", description: Text(failure))
            }
        }
        .navigationTitle("专栏")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    /// `<p>` and `<br>` already become newlines. Each block gets its own gap.
    private func paragraphs(_ body: String) -> [String] {
        let parts = body
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty && !body.isEmpty ? [body] : parts
    }

    private func load() async {
        do {
            let doc = try await model.client.articleDocument(id: model.articleFocusID)
            if !doc.cover.isEmpty {
                await ImageStore.shared.prepare(urls: [doc.cover], maxPixel: 640)
            }
            article = doc
            loading = false
            OtherContentProof.record([
                "state": "rows",
                "rows": 1,
                "title": doc.title,
                "names": [doc.author],
                "body": doc.body.count,
                "id": doc.id,
                "error": ""
            ])
        } catch {
            loading = false
            failure = error.localizedDescription
            OtherContentProof.record([
                "state": "error",
                "rows": 0,
                "title": "",
                "names": [String](),
                "body": 0,
                "id": 0,
                "error": failure
            ])
        }
    }
}

struct AudioShelfPage: View {
    @Environment(AppModel.self) private var model
    @State private var tracks: [AudioTrack] = []
    @State private var failure = ""
    @State private var loading = true

    var body: some View {
        Group {
            if loading && tracks.isEmpty {
                ProgressView("正在加载音频")
            } else if tracks.isEmpty {
                ContentUnavailableView("没有音频", systemImage: "music.note", description: Text(failure))
            } else {
                List(tracks) { track in
                    Button { model.open(.feature("音乐详情")) } label: { trackRow(track) }
                        .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("音频")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func trackRow(_ track: AudioTrack) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteImage(url: track.cover, maxPixel: 240)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(track.author.isEmpty ? track.uploader : track.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(Self.clock(track.duration))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func load() async {
        do {
            let rows = try await model.client.audioShelf()
            await ImageStore.shared.prepare(urls: rows.prefix(6).map(\.cover), maxPixel: 240)
            tracks = rows
            loading = false
            OtherContentProof.record([
                "state": "rows",
                "rows": rows.count,
                "titles": rows.map(\.title),
                "id": rows.first?.id ?? 0,
                "error": ""
            ])
        } catch {
            loading = false
            failure = error.localizedDescription
            OtherContentProof.record(["state": "error", "rows": 0, "titles": [String](), "id": 0, "error": failure])
        }
    }

    static func clock(_ seconds: Int) -> String {
        let value = max(0, seconds)
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

struct MusicDetailPage: View {
    @Environment(AppModel.self) private var model
    @State private var track: AudioTrack?
    @State private var failure = ""
    @State private var loading = true

    var body: some View {
        Group {
            if let track {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        RemoteImage(url: track.cover, maxPixel: 640)
                            .frame(maxWidth: .infinity)
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        Text(track.title).font(.title2.bold())
                        Text(track.author.isEmpty ? track.uploader : track.author)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(track.uploader) · \(AudioShelfPage.clock(track.duration))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !track.intro.isEmpty {
                            Text(track.intro).font(.body)
                        }
                    }
                    .padding(16)
                }
            } else if loading {
                ProgressView("正在打开音乐")
            } else {
                ContentUnavailableView("音乐打不开", systemImage: "music.note.list", description: Text(failure))
            }
        }
        .navigationTitle("音乐详情")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            let row = try await model.client.musicDetail()
            if !row.cover.isEmpty { await ImageStore.shared.prepare(urls: [row.cover], maxPixel: 640) }
            track = row
            loading = false
            OtherContentProof.record([
                "state": "rows",
                "rows": 1,
                "title": row.title,
                "names": [row.author.isEmpty ? row.uploader : row.author],
                "id": row.id,
                "note": row.intro,
                "error": ""
            ])
        } catch {
            loading = false
            failure = error.localizedDescription
            OtherContentProof.record(["state": "error", "rows": 0, "title": "", "names": [String](), "id": 0, "note": "", "error": failure])
        }
    }
}

struct CoursePage: View {
    @Environment(AppModel.self) private var model
    @State private var shelf: CourseShelf?
    @State private var failure = ""
    @State private var loading = true

    var body: some View {
        Group {
            if let shelf {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(shelf.title).font(.headline)
                            if !shelf.teacher.isEmpty {
                                Text(shelf.teacher).font(.subheadline).foregroundStyle(.secondary)
                            }
                            if !shelf.subtitle.isEmpty {
                                Text(shelf.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    Section("课时") {
                        ForEach(shelf.lessons) { lesson in
                            HStack {
                                Text(lesson.title).lineLimit(2)
                                Spacer(minLength: 8)
                                if lesson.play > 0 {
                                    Text(CountText.format(lesson.play))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if !shelf.related.isEmpty {
                        Section("相关课程") {
                            ForEach(shelf.related) { item in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).lineLimit(2)
                                    if !item.subtitle.isEmpty {
                                        Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            } else if loading {
                ProgressView("正在加载课堂")
            } else {
                ContentUnavailableView("课堂打不开", systemImage: "graduationcap", description: Text(failure))
            }
        }
        .navigationTitle("课堂")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            let page = try await model.client.courseShelf()
            shelf = page
            loading = false
            OtherContentProof.record([
                "state": "rows",
                "rows": page.lessons.count,
                "title": page.title,
                "titles": page.lessons.map(\.title),
                "extra": page.related.count,
                "names": [page.teacher],
                "error": ""
            ])
        } catch {
            loading = false
            failure = error.localizedDescription
            OtherContentProof.record(["state": "error", "rows": 0, "title": "", "titles": [String](), "extra": 0, "names": [String](), "error": failure])
        }
    }
}

struct InteractiveVideoPage: View {
    @Environment(AppModel.self) private var model
    @State private var edge: SteinEdge?
    @State private var failure = ""
    @State private var loading = true

    var body: some View {
        Group {
            if let edge {
                List {
                    Section {
                        Text(edge.title).font(.headline)
                        Text(edge.bvid).font(.caption).foregroundStyle(.secondary)
                    }
                    Section("选项") {
                        ForEach(edge.choices) { choice in
                            Text(choice.option)
                        }
                    }
                }
                .listStyle(.plain)
            } else if loading {
                ProgressView("正在打开互动视频")
            } else {
                ContentUnavailableView("没有互动视频", systemImage: "point.topleft.down.to.point.bottomright.curvepath", description: Text(failure))
            }
        }
        .navigationTitle("互动视频")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            let page = try await model.client.interactiveEdge()
            edge = page
            loading = false
            OtherContentProof.record([
                "state": "rows",
                "rows": page.choices.count,
                "title": page.title,
                "bvid": page.bvid,
                "titles": page.choices.map(\.option),
                "id": page.graph,
                "error": ""
            ])
        } catch {
            loading = false
            failure = error.localizedDescription
            OtherContentProof.record(["state": "error", "rows": 0, "title": "", "bvid": "", "titles": [String](), "id": 0, "error": failure])
        }
    }
}

struct NotesPage: View {
    @Environment(AppModel.self) private var model
    @State private var notes: [PublicNote] = []
    @State private var failure = ""
    @State private var loading = true

    var body: some View {
        Group {
            if loading && notes.isEmpty {
                ProgressView("正在查找公开笔记")
            } else if notes.isEmpty {
                ContentUnavailableView("没有公开笔记", systemImage: "note.text", description: Text(failure))
            } else {
                List(notes) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                        if !note.summary.isEmpty {
                            Text(note.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Text(note.author.isEmpty ? note.videoTitle : note.author)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("笔记")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            let page = try await model.client.publicNotes()
            notes = page.notes
            failure = page.note
            loading = false
            if page.notes.isEmpty {
                OtherContentProof.record([
                    "state": "empty",
                    "rows": 0,
                    "titles": [String](),
                    "names": [String](),
                    "note": page.note,
                    "error": ""
                ])
            } else {
                OtherContentProof.record([
                    "state": "rows",
                    "rows": page.notes.count,
                    "titles": page.notes.map(\.title),
                    "names": page.notes.map(\.author),
                    "note": page.notes.first?.videoTitle ?? "",
                    "error": ""
                ])
            }
        } catch {
            loading = false
            failure = error.localizedDescription
            OtherContentProof.record(["state": "error", "rows": 0, "titles": [String](), "names": [String](), "note": "", "error": failure])
        }
    }
}

struct AISummaryPage: View {
    @Environment(AppModel.self) private var model
    @State private var page = SummaryPage(bvid: "", title: "", summary: "", outline: [], login: false, note: "")
    @State private var loading = true

    var body: some View {
        Group {
            if loading {
                ProgressView("正在读取 AI 总结")
            } else if page.login {
                ContentUnavailableView("登录后查看 AI 总结", systemImage: "sparkles", description: Text(page.title.isEmpty ? page.note : page.title))
            } else if page.summary.isEmpty {
                ContentUnavailableView("没有 AI 总结", systemImage: "sparkles", description: Text(page.note.isEmpty ? page.title : page.note))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(page.title).font(.headline)
                        Text(page.summary).font(.body)
                        if !page.outline.isEmpty {
                            Text("提纲").font(.subheadline.weight(.semibold))
                            ForEach(Array(page.outline.enumerated()), id: \.offset) { _, line in
                                Text(line).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle("AI 总结")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        let sample = await model.client.summarySample()
        page = sample
        loading = false
        if !sample.summary.isEmpty {
            OtherContentProof.record([
                "state": "rows",
                "rows": 1,
                "title": sample.title,
                "bvid": sample.bvid,
                "note": sample.summary,
                "titles": sample.outline,
                "error": ""
            ])
        } else if sample.login {
            OtherContentProof.record([
                "state": "login",
                "rows": 0,
                "title": sample.title,
                "bvid": sample.bvid,
                "note": sample.note,
                "titles": [String](),
                "error": ""
            ])
        } else {
            OtherContentProof.record([
                "state": "empty",
                "rows": 0,
                "title": sample.title,
                "bvid": sample.bvid,
                "note": sample.note,
                "titles": [String](),
                "error": sample.note
            ])
        }
    }
}

struct SeasonIndexPage: View {
    @Environment(AppModel.self) private var model
    var seasonType: Int
    @State private var rows: [IndexTitle] = []
    @State private var failure = ""
    @State private var loading = true

    var body: some View {
        Group {
            if loading && rows.isEmpty {
                ProgressView("正在加载索引")
            } else if rows.isEmpty {
                ContentUnavailableView("索引是空的", systemImage: "square.grid.2x2", description: Text(failure))
            } else {
                List(rows) { item in
                    Button {
                        model.reviewMediaID = item.mediaID
                        model.open(.feature("番剧短评"))
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            RemoteImage(url: item.cover, maxPixel: 240)
                                .frame(width: 72, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                Text(item.progress).font(.caption).foregroundStyle(.secondary)
                                Text(item.order).font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(seasonType == 2 ? "影视索引" : "番剧索引")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            let page = try await model.client.seasonIndex(seasonType: seasonType)
            await ImageStore.shared.prepare(urls: page.prefix(8).map(\.cover), maxPixel: 240)
            rows = page
            loading = false
            if model.reviewMediaID == 0 { model.reviewMediaID = page.first?.mediaID ?? 0 }
            OtherContentProof.record([
                "state": "rows",
                "rows": page.count,
                "titles": page.map(\.title),
                "id": page.first?.mediaID ?? 0,
                "title": page.first?.title ?? "",
                "error": ""
            ])
        } catch {
            loading = false
            failure = error.localizedDescription
            OtherContentProof.record(["state": "error", "rows": 0, "titles": [String](), "id": 0, "title": "", "error": failure])
        }
    }
}

struct ShortReviewPage: View {
    @Environment(AppModel.self) private var model
    @State private var reviews: [ShortReview] = []
    @State private var failure = ""
    @State private var loading = true
    @State private var mediaTitle = ""

    var body: some View {
        Group {
            if loading && reviews.isEmpty {
                ProgressView("正在加载短评")
            } else if reviews.isEmpty {
                ContentUnavailableView("没有短评", systemImage: "text.bubble", description: Text(failure))
            } else {
                List(reviews) { review in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(review.author).font(.subheadline.weight(.semibold))
                            Spacer()
                            if review.score > 0 {
                                Text("\(review.score)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Palette.bili)
                            }
                        }
                        Text(review.content).font(.subheadline).foregroundStyle(.primary)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("短评")
        .navigationSubtitle(mediaTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            var media = model.reviewMediaID
            if media == 0 {
                let index = try await model.client.seasonIndex(seasonType: 1)
                media = index.first?.mediaID ?? 0
                mediaTitle = index.first?.title ?? ""
            }
            guard media > 0 else { throw BiliError.message("没有剧集") }
            let rows = try await model.client.shortReviews(mediaID: media)
            reviews = rows
            loading = false
            OtherContentProof.record([
                "state": "rows",
                "rows": rows.count,
                "titles": rows.map(\.content),
                "names": rows.map(\.author),
                "id": media,
                "title": mediaTitle,
                "error": ""
            ])
        } catch {
            loading = false
            failure = error.localizedDescription
            OtherContentProof.record(["state": "error", "rows": 0, "titles": [String](), "names": [String](), "id": 0, "title": "", "error": failure])
        }
    }
}

struct EsportsPage: View {
    @Environment(AppModel.self) private var model
    @State private var matches: [MatchCard] = []
    @State private var failure = ""
    @State private var loading = true

    var body: some View {
        Group {
            if loading && matches.isEmpty {
                ProgressView("正在加载赛事")
            } else if matches.isEmpty {
                ContentUnavailableView("没有赛事", systemImage: "flag.checkered", description: Text(failure))
            } else {
                List(matches) { match in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(match.home) \(match.homeScore) : \(match.awayScore) \(match.away)")
                            .font(.subheadline.weight(.semibold))
                        Text([match.season, match.stage].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("赛事")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            let rows = try await model.client.esportsBoard()
            matches = rows
            loading = false
            OtherContentProof.record([
                "state": "rows",
                "rows": rows.count,
                "titles": rows.map { "\($0.home) \($0.homeScore):\($0.awayScore) \($0.away)" },
                "names": rows.flatMap { [$0.home, $0.away] },
                "error": ""
            ])
        } catch {
            loading = false
            failure = error.localizedDescription
            OtherContentProof.record(["state": "error", "rows": 0, "titles": [String](), "names": [String](), "error": failure])
        }
    }
}

struct BubblePage: View {
    @Environment(AppModel.self) private var model
    @State private var bubbles: [DecorBubble] = []
    @State private var failure = ""
    @State private var loading = true

    var body: some View {
        Group {
            if loading && bubbles.isEmpty {
                ProgressView("正在查找装扮气泡")
            } else if bubbles.isEmpty {
                ContentUnavailableView("没有装扮气泡", systemImage: "bubble.left", description: Text(failure))
            } else {
                List(bubbles) { bubble in
                    HStack(spacing: 12) {
                        RemoteImage(url: bubble.image, ratio: 1, maxPixel: 240)
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(bubble.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                            if !bubble.owner.isEmpty {
                                Text(bubble.owner).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("装扮气泡")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            let rows = try await model.client.decorBubbles()
            await ImageStore.shared.prepare(urls: rows.map(\.image), maxPixel: 240)
            bubbles = rows
            loading = false
            OtherContentProof.record([
                "state": "rows",
                "rows": rows.count,
                "names": rows.map(\.name),
                "titles": rows.map(\.image),
                "error": ""
            ])
        } catch {
            loading = false
            failure = error.localizedDescription
            OtherContentProof.record(["state": "error", "rows": 0, "names": [String](), "titles": [String](), "error": failure])
        }
    }
}

struct CacheSearchPage: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    private var hits: [OfflineItem] {
        let word = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let pool = model.downloads.items.filter { Self.real($0.title) }
        guard !word.isEmpty else { return pool }
        return pool.filter {
            $0.title.localizedCaseInsensitiveContains(word)
                || $0.owner.localizedCaseInsensitiveContains(word)
                || $0.bvid.localizedCaseInsensitiveContains(word)
        }
    }

    var body: some View {
        Group {
            if model.downloads.items.isEmpty {
                ContentUnavailableView("没有可搜索的缓存", systemImage: "magnifyingglass", description: Text("下载完成后再搜索标题"))
            } else if hits.isEmpty {
                ContentUnavailableView("没有匹配的缓存", systemImage: "magnifyingglass", description: Text(query))
            } else {
                List(hits) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                        Text("\(item.owner) · \(item.bvid)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("缓存搜索")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "搜索已缓存的标题")
        .task { reveal() }
    }

    private func reveal() {
        guard LaunchMode.screen == "content-cache" else { return }
        let pool = model.downloads.items.filter { Self.real($0.title) }
        let token = Self.token(in: pool.first?.title ?? "")
        query = token
        if pool.isEmpty {
            OtherContentProof.record([
                "state": "empty",
                "rows": 0,
                "query": "",
                "titles": [String](),
                "bvid": "",
                "note": "没有可搜索的缓存",
                "error": ""
            ])
            return
        }
        let matched = token.isEmpty ? [] : pool.filter { $0.title.localizedCaseInsensitiveContains(token) }
        OtherContentProof.record([
            "state": matched.isEmpty ? "empty" : "rows",
            "rows": matched.count,
            "query": token,
            "titles": matched.map(\.title),
            "bvid": matched.first?.bvid ?? "",
            "note": matched.isEmpty ? "没有匹配的缓存" : "",
            "error": ""
        ])
    }

    private static func token(in title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return trimmed }
        return String(trimmed.prefix(4))
    }

    private static func real(_ text: String) -> Bool {
        let folded = text.lowercased()
        return !text.contains("液态玻璃") && !text.contains("玻璃试验") && !folded.contains("fixture")
    }
}
