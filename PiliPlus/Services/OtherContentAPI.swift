import Foundation

struct ArticleDoc: Identifiable, Hashable {
    var id: Int
    var title: String
    var author: String
    var cover: String
    var body: String
}

struct AudioTrack: Identifiable, Hashable {
    var id: Int
    var title: String
    var author: String
    var uploader: String
    var cover: String
    var duration: Int
    var intro: String
}

struct CourseLesson: Identifiable, Hashable {
    var id: Int
    var title: String
    var play: Int
}

struct CourseShelf: Identifiable {
    var id: Int
    var title: String
    var teacher: String
    var subtitle: String
    var cover: String
    var lessons: [CourseLesson]
    var related: [CourseShelf]
}

struct SteinChoice: Identifiable, Hashable {
    var id: Int
    var option: String
}

struct SteinEdge: Hashable {
    var bvid: String
    var title: String
    var graph: Int
    var edge: Int
    var choices: [SteinChoice]
}

struct PublicNote: Identifiable, Hashable {
    var id: Int
    var title: String
    var summary: String
    var author: String
    var videoTitle: String
}

struct SummaryPage: Hashable {
    var bvid: String
    var title: String
    var summary: String
    var outline: [String]
    var login: Bool
    var note: String
}

struct IndexTitle: Identifiable, Hashable {
    var id: Int
    var mediaID: Int
    var title: String
    var cover: String
    var progress: String
    var order: String
}

struct ShortReview: Identifiable, Hashable {
    var id: Int
    var author: String
    var content: String
    var score: Int
}

struct MatchCard: Identifiable, Hashable {
    var id: Int
    var stage: String
    var home: String
    var away: String
    var homeScore: Int
    var awayScore: Int
    var season: String
}

struct DecorBubble: Identifiable, Hashable {
    var id: Int
    var name: String
    var image: String
    var owner: String
}

enum OtherContentProof {
    static func record(_ payload: [String: Any]) {
        guard let screen = LaunchMode.screen, screen.hasPrefix("content-") else { return }
        var body = payload
        body["screen"] = screen
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { return }
        try? data.write(to: LaunchClock.documents.appendingPathComponent("content-ui.json"), options: .atomic)
    }
}

extension BiliClient {
    func articleDocument(id requested: Int) async throws -> ArticleDoc {
        var last = "专栏打不开"
        for attempt in 0..<3 {
            if attempt > 0 {
                try await Task.sleep(for: .seconds(attempt == 1 ? 5 : 12))
            }
            do {
                return try await loadArticleDocument(id: requested)
            } catch {
                last = error.localizedDescription
                let limited = last.contains("频繁") || last.contains("稍后再试") || last.contains("412")
                if !limited { throw error }
            }
        }
        throw BiliError.message(last)
    }

    private func loadArticleDocument(id requested: Int) async throws -> ArticleDoc {
        let id: Int
        var listedAuthor = ""
        if requested > 0 {
            id = requested
        } else {
            let listed = try await openGET(
                "/x/article/recommends",
                query: ["pn": "1", "ps": "8"],
                referer: "https://www.bilibili.com/read/home"
            )
            guard let row = (listed["data"].array ?? []).first(where: { Self.realCopy($0["title"].string ?? "") }),
                  let found = row["id"].int else {
                throw BiliError.message(listed["message"].string ?? "没有专栏")
            }
            id = found
            listedAuthor = row["author"]["name"].string ?? ""
        }
        let view = try await openGET(
            "/x/article/view",
            query: ["id": "\(id)"],
            referer: "https://www.bilibili.com/read/cv\(id)",
            signed: true
        )
        guard view["code"].int == 0 else {
            throw BiliError.message(view["message"].string ?? "专栏打不开")
        }
        let data = view["data"]
        let title = data["title"].string ?? ""
        let body = Self.plainText(data["content"].string ?? data["summary"].string ?? "")
        guard Self.realCopy(title), body.count >= 40 else {
            throw BiliError.message("专栏正文是空的")
        }
        let cover = Self.https(data["image_urls"][0].string ?? data["banner_url"].string ?? "")
        let candidates: [String?] = [data["author"]["name"].string, data["author_name"].string, listedAuthor]
        let author = candidates.compactMap { $0 }.first { Self.realCopy($0) } ?? ""
        return ArticleDoc(
            id: id,
            title: title,
            author: author,
            cover: cover,
            body: body
        )
    }

    func audioShelf() async throws -> [AudioTrack] {
        let menus = try await openGET(
            "/audio/music-service-c/web/menu/hit",
            query: ["pn": "1", "ps": "6"],
            host: "https://www.bilibili.com",
            referer: "https://www.bilibili.com/audio/"
        )
        let lists = menus["data"]["data"].array ?? []
        var last = menus["message"].string ?? "没有音频"
        for menu in lists.prefix(4) {
            guard let sid = menu["menuId"].int else { continue }
            do {
                let songs = try await openGET(
                    "/audio/music-service-c/web/song/of-menu",
                    query: ["sid": "\(sid)", "pn": "1", "ps": "12"],
                    host: "https://www.bilibili.com",
                    referer: "https://www.bilibili.com/audio/am\(sid)"
                )
                let tracks = Self.tracks(in: songs["data"]["data"].array ?? [])
                if !tracks.isEmpty { return tracks }
                last = songs["message"].string ?? last
            } catch {
                last = error.localizedDescription
            }
        }
        throw BiliError.message(last)
    }

    func musicDetail() async throws -> AudioTrack {
        let tracks = try await audioShelf()
        guard let first = tracks.first else { throw BiliError.message("没有音乐") }
        let info = try? await openGET(
            "/audio/music-service-c/web/song/info",
            query: ["sid": "\(first.id)"],
            host: "https://www.bilibili.com",
            referer: "https://www.bilibili.com/audio/au\(first.id)"
        )
        guard let info, info["code"].int == 0 else { return first }
        let row = info["data"]
        let title = row["title"].string ?? first.title
        guard Self.realCopy(title) else { return first }
        return AudioTrack(
            id: row["id"].int ?? first.id,
            title: title,
            author: row["author"].string ?? first.author,
            uploader: row["uname"].string ?? first.uploader,
            cover: Self.https(row["cover"].string ?? first.cover),
            duration: row["duration"].int ?? first.duration,
            intro: row["intro"].string ?? first.intro
        )
    }

    func courseShelf() async throws -> CourseShelf {
        let data = try await openGET(
            "/pugv/view/web/season",
            query: ["season_id": "61"],
            referer: "https://www.bilibili.com/cheese/play/ss61"
        )
        guard data["code"].int == 0 else {
            throw BiliError.message(data["message"].string ?? "课堂打不开")
        }
        let season = data["data"]
        let title = season["title"].string ?? ""
        guard Self.realCopy(title) else { throw BiliError.message("课堂没有标题") }
        let lessons = (season["episodes"].array ?? []).compactMap { row -> CourseLesson? in
            let name = row["title"].string ?? ""
            guard Self.realCopy(name), let id = row["id"].int ?? row["aid"].int else { return nil }
            return CourseLesson(id: id, title: name, play: row["play"].int ?? 0)
        }
        guard !lessons.isEmpty else { throw BiliError.message("课堂没有课时") }
        let related = (season["recommend_seasons"].array ?? []).compactMap { row -> CourseShelf? in
            let name = row["title"].string ?? ""
            guard Self.realCopy(name), let id = row["id"].int else { return nil }
            return CourseShelf(id: id, title: name, teacher: "", subtitle: row["subtitle"].string ?? "", cover: Self.https(row["cover"].string ?? ""), lessons: [], related: [])
        }
        let teacher = season["up_info"]["uname"].string ?? season["up_info"]["name"].string ?? ""
        return CourseShelf(
            id: season["season_id"].int ?? 61,
            title: title,
            teacher: teacher,
            subtitle: season["subtitle"].string ?? "",
            cover: Self.https(season["cover"].string ?? ""),
            lessons: Array(lessons.prefix(20)),
            related: Array(related.prefix(12))
        )
    }

    func interactiveEdge() async throws -> SteinEdge {
        let listed = try await openGET(
            "/x/web-interface/tag/top",
            query: ["pn": "1", "ps": "8", "tid": "1221581"],
            referer: "https://www.bilibili.com/v/topic/detail?topic_id=1221581"
        )
        var last = listed["message"].string ?? "没有互动视频"
        for row in listed["data"].array ?? [] {
            guard let bvid = row["bvid"].string, bvid.hasPrefix("BV"), Self.realCopy(row["title"].string ?? "") else { continue }
            let cid = row["cid"].int ?? 0
            guard cid > 0 else { continue }
            do {
                let player = try await openGET(
                    "/x/player/v2",
                    query: ["bvid": bvid, "cid": "\(cid)"],
                    referer: "https://www.bilibili.com/video/\(bvid)"
                )
                let graph = player["data"]["interaction"]["graph_version"].int ?? 0
                guard graph > 0 else { continue }
                let edge = try await openGET(
                    "/x/stein/edgeinfo_v2",
                    query: ["bvid": bvid, "graph_version": "\(graph)", "edge_id": "0"],
                    referer: "https://www.bilibili.com/video/\(bvid)"
                )
                guard edge["code"].int == 0 else {
                    last = edge["message"].string ?? last
                    continue
                }
                let choices = (edge["data"]["edges"]["questions"][0]["choices"].array ?? []).compactMap { choice -> SteinChoice? in
                    let option = choice["option"].string ?? ""
                    guard Self.realCopy(option), let id = choice["id"].int else { return nil }
                    return SteinChoice(id: id, option: option)
                }
                if choices.isEmpty {
                    last = "这一段没有选项"
                    continue
                }
                let title = edge["data"]["title"].string ?? row["title"].string ?? ""
                return SteinEdge(bvid: bvid, title: title, graph: graph, edge: edge["data"]["edge_id"].int ?? 0, choices: choices)
            } catch {
                last = error.localizedDescription
            }
        }
        throw BiliError.message(last)
    }

    func publicNotes() async throws -> (notes: [PublicNote], note: String) {
        var last = "没有公开笔记"
        for page in 1...3 {
            let videos: [VideoItem]
            do {
                videos = try await popular(page: page)
            } catch {
                last = error.localizedDescription
                continue
            }
            if let found = await notes(on: videos, last: &last) { return found }
        }
        return ([], last)
    }

    private func notes(on videos: [VideoItem], last: inout String) async -> (notes: [PublicNote], note: String)? {
        for video in videos where video.aid > 0 && Self.realCopy(video.title) {
            let data: JSON
            do {
                data = try await openGET(
                    "/x/note/publish/list/archive",
                    query: ["oid": "\(video.aid)", "pn": "1", "ps": "10"],
                    referer: "https://www.bilibili.com/video/\(video.bvid)"
                )
            } catch {
                last = error.localizedDescription
                continue
            }
            let message = data["data"]["message"].string ?? data["message"].string ?? last
            let notes = (data["data"]["list"].array ?? []).compactMap { row -> PublicNote? in
                let title = row["title"].string ?? ""
                let author = row["author"]["name"].string ?? row["author"]["uname"].string ?? ""
                guard Self.realCopy(title), Self.realCopy(author), let id = row["cvid"].int else { return nil }
                return PublicNote(
                    id: id,
                    title: title,
                    summary: row["summary"].string ?? "",
                    author: author,
                    videoTitle: video.title
                )
            }
            if !notes.isEmpty { return (notes, "") }
            if !message.isEmpty { last = message }
        }
        return nil
    }

    func videoSummary(bvid: String, cid: Int, upMid: Int) async -> SummaryPage {
        guard bvid.hasPrefix("BV"), cid > 0 else {
            return SummaryPage(bvid: bvid, title: "", summary: "", outline: [], login: false, note: "还没有视频")
        }
        do {
            let data = try await openGET(
                "/x/web-interface/view/conclusion/get",
                query: ["bvid": bvid, "cid": "\(cid)", "up_mid": "\(upMid)"],
                referer: "https://www.bilibili.com/video/\(bvid)",
                signed: true
            )
            let code = data["code"].int ?? -1
            if code == -101 {
                return SummaryPage(bvid: bvid, title: "", summary: "", outline: [], login: true, note: "登录后查看 AI 总结")
            }
            guard code == 0 else {
                return SummaryPage(bvid: bvid, title: "", summary: "", outline: [], login: false, note: data["message"].string ?? "AI 总结不可用")
            }
            let model = data["data"]["model_result"]
            let summary = Self.plainText(model["summary"].string ?? "")
            let outline = (model["outline"].array ?? []).compactMap { $0["title"].string }.filter(Self.realCopy)
            if summary.isEmpty {
                let inner = data["data"]["code"].int ?? 1
                let note = inner == 1 ? "这条视频没有识别到可用的总结" : "这条视频没有 AI 总结"
                return SummaryPage(bvid: bvid, title: "", summary: "", outline: outline, login: false, note: note)
            }
            return SummaryPage(bvid: bvid, title: "", summary: summary, outline: outline, login: false, note: "")
        } catch {
            return SummaryPage(bvid: bvid, title: "", summary: "", outline: [], login: false, note: error.localizedDescription)
        }
    }

    func summarySample() async -> SummaryPage {
        let videos = (try? await popular(page: 1)) ?? []
        var last = SummaryPage(bvid: "", title: "", summary: "", outline: [], login: false, note: "没有可总结的视频")
        for video in videos.prefix(6) where Self.realCopy(video.title) {
            let page = await videoSummary(bvid: video.bvid, cid: video.cid, upMid: video.ownerMid)
            var titled = page
            titled.title = video.title
            if !page.summary.isEmpty || page.login { return titled }
            last = titled
        }
        return last
    }

    func seasonIndex(seasonType: Int) async throws -> [IndexTitle] {
        let data = try await openGET(
            "/pgc/season/index/result",
            query: [
                "season_type": "\(seasonType)",
                "type": "1",
                "page": "1",
                "pagesize": "12",
                "order": "3"
            ],
            referer: "https://www.bilibili.com/anime/index"
        )
        guard data["code"].int == 0 else {
            throw BiliError.message(data["message"].string ?? "索引打不开")
        }
        let rows = (data["data"]["list"].array ?? []).compactMap { row -> IndexTitle? in
            let title = row["title"].string ?? ""
            guard Self.realCopy(title), let media = row["media_id"].int else { return nil }
            return IndexTitle(
                id: row["season_id"].int ?? media,
                mediaID: media,
                title: title,
                cover: Self.https(row["cover"].string ?? ""),
                progress: row["index_show"].string ?? "",
                order: row["order"].string ?? ""
            )
        }
        if rows.isEmpty { throw BiliError.message("索引是空的") }
        return rows
    }

    func shortReviews(mediaID: Int) async throws -> [ShortReview] {
        let data = try await openGET(
            "/pgc/review/short/list",
            query: ["media_id": "\(mediaID)", "ps": "10", "cursor": "0"],
            referer: "https://www.bilibili.com/bangumi/media/md\(mediaID)"
        )
        guard data["code"].int == 0 else {
            throw BiliError.message(data["message"].string ?? "短评打不开")
        }
        let rows = (data["data"]["list"].array ?? []).compactMap { row -> ShortReview? in
            let content = Self.plainText(row["content"].string ?? "")
            let author = row["author"].string ?? row["author"]["uname"].string ?? row["author"]["name"].string ?? ""
            guard Self.realCopy(content), Self.realCopy(author), let id = row["review_id"].int else { return nil }
            return ShortReview(id: id, author: author, content: content, score: row["score"].int ?? 0)
        }
        if rows.isEmpty { throw BiliError.message("没有短评") }
        return rows
    }

    func esportsBoard() async throws -> [MatchCard] {
        let data = try await openGET(
            "/x/esports/matchs/list",
            query: ["pn": "1", "ps": "12"],
            referer: "https://www.bilibili.com/v/game/match"
        )
        guard data["code"].int == 0 else {
            throw BiliError.message(data["message"].string ?? "赛事打不开")
        }
        let rows = (data["data"]["list"].array ?? []).compactMap { row -> MatchCard? in
            let home = row["home"]["name"].string ?? row["home_team"]["title"].string ?? ""
            let away = row["away"]["name"].string ?? row["away_team"]["title"].string ?? ""
            guard Self.realCopy(home), Self.realCopy(away), let id = row["id"].int else { return nil }
            return MatchCard(
                id: id,
                stage: row["game_stage"].string ?? "",
                home: home,
                away: away,
                homeScore: row["home_score"].int ?? 0,
                awayScore: row["away_score"].int ?? 0,
                season: row["season"]["title"].string ?? ""
            )
        }
        if rows.isEmpty { throw BiliError.message("没有赛事") }
        return rows
    }

    func decorBubbles() async throws -> [DecorBubble] {
        let videos = try await popular(page: 1)
        var found: [DecorBubble] = []
        for video in videos.prefix(8) where video.aid > 0 {
            let data = try? await openGET(
                "/x/v2/reply",
                query: ["type": "1", "oid": "\(video.aid)", "sort": "1", "ps": "20", "pn": "1"],
                referer: "https://www.bilibili.com/video/\(video.bvid)"
            )
            Self.collectBubbles(data?["data"]["replies"].array ?? [], into: &found)
            if found.count >= 8 { break }
        }
        if found.isEmpty { throw BiliError.message("这批评论里没有装扮气泡") }
        return found
    }

    private func openGET(
        _ path: String,
        query: [String: String],
        host: String = "https://api.bilibili.com",
        referer: String,
        signed: Bool = false
    ) async throws -> JSON {
        var last = "请求失败"
        for suppressCookie in [false, true] {
            do {
                let data = try await accountGET(
                    path,
                    query: query,
                    host: host,
                    referer: referer,
                    signed: signed,
                    suppressCookie: suppressCookie
                )
                let code = data["code"].int ?? -1
                if code == 0 || code == -101 { return data }
                last = data["message"].string ?? last
            } catch {
                last = error.localizedDescription
            }
        }
        throw BiliError.message(last)
    }

    private static func tracks(in rows: [JSON]) -> [AudioTrack] {
        rows.compactMap { row in
            let title = row["title"].string ?? ""
            guard realCopy(title), let id = row["id"].int else { return nil }
            return AudioTrack(
                id: id,
                title: title,
                author: row["author"].string ?? "",
                uploader: row["uname"].string ?? "",
                cover: https(row["cover"].string ?? ""),
                duration: row["duration"].int ?? 0,
                intro: row["intro"].string ?? ""
            )
        }
    }

    private static func collectBubbles(_ rows: [JSON], into found: inout [DecorBubble]) {
        for row in rows {
            let card = row["member"]["user_sailing"]["cardbg"]
            let name = card["name"].string ?? ""
            let image = https(card["image"].string ?? "")
            if realCopy(name), image.hasPrefix("https"), !found.contains(where: { $0.name == name }) {
                let id = card["id"].int ?? (found.count + 1)
                found.append(DecorBubble(id: id, name: name, image: image, owner: row["member"]["uname"].string ?? ""))
            }
            if let nested = row["replies"].array {
                collectBubbles(nested, into: &found)
            }
        }
    }

    private static func plainText(_ raw: String) -> String {
        var text = raw
        if let regex = try? NSRegularExpression(pattern: "(?i)<br\\s*/?>|</p>", options: []) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "\n")
        }
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        text = text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func realCopy(_ text: String) -> Bool {
        let folded = text.lowercased()
        return !text.isEmpty && !text.contains("液态玻璃") && !text.contains("玻璃试验") && !folded.contains("fixture")
    }
}
