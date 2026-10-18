import Foundation
import UIKit

enum BiliError: LocalizedError {
    case message(String)
    case status(Int)
    case risk(Int)

    var isRiskControl: Bool {
        switch self {
        case .status(412), .risk: return true
        default: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .status(412): return "播放被风控拦住了（412）"
        case .status(let code): return "网络 \(code)"
        case .risk(let code): return "请求被风控拦住了（\(code)）"
        }
    }
}

private struct PlaybackAttempt {
    var sawRiskControl = false
    var last: BiliError?

    mutating func note(_ error: Error) {
        let bili = (error as? BiliError) ?? BiliError.message(error.localizedDescription)
        if bili.isRiskControl { sawRiskControl = true }
        last = bili
    }
}

struct BiliClient: Sendable {
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 18
        config.httpAdditionalHeaders = [
            "User-Agent": BiliHTTP.userAgent,
            "Referer": BiliHTTP.origin,
            "Origin": BiliHTTP.origin
        ]
        return URLSession(configuration: config)
    }()

    func popular(page: Int = 1) async throws -> [VideoItem] {
        let data = try await getJSON("https://api.bilibili.com/x/web-interface/popular?ps=20&pn=\(page)")
        let list = data["data"]["list"].array ?? []
        return list.compactMap(Self.video(fromPopular:))
    }

    func weeklyIssues() async throws -> [WeeklyIssue] {
        guard let url = HotRequest.issues().endpoint else { throw BiliError.message("地址无效") }
        let data = try await getJSON(url)
        guard data["code"].int == 0 else {
            throw BiliError.message(data["message"].string ?? "每周必看不可用")
        }
        return (data["data"]["list"].array ?? []).compactMap { item in
            let number = item["number"].int ?? 0
            guard number > 0 else { return nil }
            return WeeklyIssue(
                number: number,
                name: item["name"].string ?? "",
                subject: item["subject"].string ?? ""
            )
        }
    }

    func weeklyVideos(number: Int) async throws -> [VideoItem] {
        let params = ["number": "\(number)"]
        let referer = "https://www.bilibili.com/v/popular/weekly"
        var last = "这一期没有打开"
        // A long guest session can make the signed call return -352. The same signature without that cookie still opens the issue.
        for suppressCookie in [false, true] {
            do {
                let data = try await requestQuery(
                    "/x/web-interface/popular/series/one",
                    params: params,
                    signed: true,
                    referer: referer,
                    suppressCookie: suppressCookie
                )
                let code = data["code"].int ?? -1
                if code == 0 {
                    let list = data["data"]["list"].array ?? data["data"]["archives"].array ?? []
                    let videos = list.compactMap { Self.video(fromPopular: $0) ?? Self.video(fromFavorite: $0) }
                    if !videos.isEmpty { return videos }
                    last = "这一期没有视频"
                    continue
                }
                last = code == -352 || code == 412
                    ? BiliError.risk(code).localizedDescription
                    : (data["message"].string ?? last)
            } catch {
                last = error.localizedDescription
            }
        }
        throw BiliError.message(last)
    }

    func preciousVideos() async throws -> (videos: [VideoItem], explain: String) {
        guard let url = HotRequest.precious().endpoint else { throw BiliError.message("地址无效") }
        let data = try await getJSON(url)
        guard data["code"].int == 0 else {
            throw BiliError.message(data["message"].string ?? "入站必刷不可用")
        }
        let videos = (data["data"]["list"].array ?? []).compactMap(Self.video(fromPopular:))
        return (videos, data["data"]["explain"].string ?? data["data"]["title"].string ?? "")
    }

    func ranking(rid: Int = 0) async throws -> [VideoItem] {
        let data = try await withGuest {
            let data = try await getJSON("https://api.bilibili.com/x/web-interface/ranking/v2?rid=\(rid)&type=all")
            let code = data["code"].int ?? -1
            if code == -352 || code == 412 { throw BiliError.risk(code) }
            guard code == 0 else { throw BiliError.message(data["message"].string ?? "排行不可用") }
            return data
        }
        return (data["data"]["list"].array ?? []).compactMap(Self.video(fromPopular:))
    }

    /// Web 推荐流。`idx` 从 1 开始，对应上游 `fresh_idx`。
    func recommend(idx: Int) async throws -> [VideoItem] {
        let cursor = max(1, idx)
        let params = [
            "fresh_type": "3",
            "feed_version": "V8",
            "fresh_idx": "\(cursor)",
            "fresh_idx_1h": "\(cursor)",
            "brush": "\(max(0, cursor - 1))",
            "fetch_row": "1",
            "web_location": "1430650",
            "ps": "12"
        ]
        let data = try await withGuest {
            if let signed = try? await requestQuery("/x/web-interface/wbi/index/top/feed/rcmd", params: params, signed: true) {
                let code = signed["code"].int ?? -1
                if code == 0 { return signed }
                if code == -352 || code == 412 { throw BiliError.risk(code) }
            }
            let plain = try await requestQuery("/x/web-interface/index/top/feed/rcmd", params: params, signed: false)
            let code = plain["code"].int ?? -1
            if code == -352 || code == 412 { throw BiliError.risk(code) }
            return plain
        }
        guard data["code"].int == 0 else {
            throw BiliError.message(data["message"].string ?? "推荐不可用")
        }
        let items = (data["data"]["item"].array ?? []).compactMap(Self.video(fromRecommend:))
        guard !items.isEmpty else { throw BiliError.message("推荐是空的") }
        return items
    }

    /// 分区最新投稿。`rid` 与排行分区一致。
    func region(rid: Int, page: Int) async throws -> [VideoItem] {
        let data = try await withGuest {
            try await getJSON("https://api.bilibili.com/x/web-interface/newlist?rid=\(rid)&pn=\(page)&ps=20")
        }
        guard data["code"].int == 0 else {
            throw BiliError.message(data["message"].string ?? "分区不可用")
        }
        return (data["data"]["archives"].array ?? []).compactMap(Self.video(fromPopular:))
    }

    /// 番剧 `season_type` 1，电影 2，电视剧 5。
    func seasons(type: Int) async throws -> [SeasonItem] {
        let data = try await withGuest {
            try await getJSON("https://api.bilibili.com/pgc/web/rank/list?day=3&season_type=\(type)")
        }
        guard data["code"].int == 0 else {
            throw BiliError.message(data["message"].string ?? "番剧榜不可用")
        }
        let list = data["data"]["list"].array ?? data["result"]["list"].array ?? []
        return list.compactMap { Self.season(from: $0) }
    }

    func bangumiSchedule() async throws -> [String: Int] {
        let data = try await withGuest {
            try await getJSON("https://api.bilibili.com/pgc/web/timeline?types=1&before=6&after=6")
        }
        guard data["code"].int == 0 else {
            throw BiliError.message(data["message"].string ?? "时间表不可用")
        }
        let days = data["result"].array ?? data["data"].array ?? []
        let names = ["", "一", "二", "三", "四", "五", "六", "日"]
        var counts: [String: Int] = [:]
        for day in days {
            var index = day["day_of_week"].int ?? 0
            if index == 0 { index = 7 }
            guard names.indices.contains(index), counts[names[index]] == nil else { continue }
            counts[names[index]] = day["episodes"].array?.count ?? 0
        }
        return counts
    }

    func dislike(aid: Int, csrf: String) async throws {
        guard aid > 0, !csrf.isEmpty else { throw BiliError.message("还不能提交不感兴趣") }
        guard let url = URL(string: "https://api.bilibili.com/x/feed/dislike") else { return }
        let data = try await postForm(url, fields: [
            "goto": "av",
            "id": "\(aid)",
            "reason_id": "0",
            "csrf": csrf
        ])
        guard data["code"].int == 0 else {
            throw BiliError.message(data["message"].string ?? "不感兴趣没有提交成功")
        }
    }

    func submit(_ form: SignedForm) async throws -> JSON {
        guard AccountRequest.isReady(form), let url = form.endpoint else {
            throw BiliError.message("缺少 csrf")
        }
        let data = try await postForm(url, fields: form.fields)
        try Self.requireOK(data)
        return data
    }

    func fetchAccount(_ form: SignedForm) async throws -> JSON {
        guard form.method == "GET", let url = form.endpoint else { throw BiliError.message("地址无效") }
        let data = try await getJSON(url)
        try Self.requireOK(data)
        return data
    }

    func history(max: Int, viewAt: Int, business: String) async throws -> (items: [VideoItem], max: Int, viewAt: Int, business: String) {
        let data = try await fetchAccount(AccountRequest.historyList(max: max, viewAt: viewAt, business: business))
        let cursor = data["data"]["cursor"]
        let items = (data["data"]["list"].array ?? []).compactMap(Self.video(fromHistory:))
        return (
            items,
            cursor["max"].int ?? 0,
            cursor["view_at"].int ?? 0,
            cursor["business"].string ?? business
        )
    }

    func historyPaused() async throws -> Bool {
        let data = try await fetchAccount(AccountRequest.historyShadow())
        return (data["data"].int ?? 0) == 1 || data["data"].bool == true
    }

    func watchLater() async throws -> [VideoItem] {
        let data = try await fetchAccount(AccountRequest.watchLaterList())
        return (data["data"]["list"].array ?? []).compactMap { item in
            Self.video(fromPopular: item) ?? Self.video(fromFavorite: item)
        }
    }

    func folders(mid: Int, rid: Int?) async throws -> [FavFolder] {
        let data = try await fetchAccount(AccountRequest.createdFolders(mid: mid, rid: rid))
        return (data["data"]["list"].array ?? []).compactMap(Self.folder(from:))
    }

    func folderVideos(mediaID: Int, page: Int) async throws -> (items: [VideoItem], hasMore: Bool) {
        try await folderPage(AccountRequest.folderContents(mediaID: mediaID, page: page))
    }

    func folderVideos(mediaID: Int, page: Int, keyword: String, order: String) async throws -> (items: [VideoItem], hasMore: Bool) {
        try await folderPage(LibraryRequest.folderQuery(mediaID: mediaID, page: page, keyword: keyword, order: LibraryRequest.orderCode(order)))
    }

    func followedShows(vmid: Int, type: Int, page: Int) async throws -> [SeasonItem] {
        let data = try await fetchAccount(LibraryRequest.bangumiFollow(vmid: vmid, type: type, page: page))
        try Self.requireOK(data)
        return (data["data"]["list"].array ?? []).compactMap { item in
            let id = item["season_id"].int ?? 0
            let title = item["title"].string ?? ""
            guard id > 0, !title.isEmpty else { return nil }
            return SeasonItem(
                seasonID: id,
                title: Self.unescape(title),
                cover: Self.https(item["cover"].string ?? ""),
                badge: item["badge"].string ?? "",
                subtitle: item["new_ep"]["index_show"].string ?? "",
                view: item["stat"]["follow"].int ?? 0
            )
        }
    }

    func collections(mid: Int) async throws -> [SeasonItem] {
        let data = try await fetchAccount(SpaceRequest.series(mid: mid, page: 1))
        try Self.requireOK(data)
        return (data["data"]["items_lists"]["seasons_list"].array ?? []).compactMap { item in
            let meta = item["meta"]
            let id = meta["season_id"].int ?? 0
            let title = meta["name"].string ?? meta["title"].string ?? ""
            guard id > 0, !title.isEmpty else { return nil }
            return SeasonItem(
                seasonID: id,
                title: Self.unescape(title),
                cover: Self.https(meta["cover"].string ?? ""),
                badge: "合集",
                subtitle: "\(meta["total"].int ?? 0) 个视频",
                view: 0
            )
        }
    }

    private func folderPage(_ form: SignedForm) async throws -> (items: [VideoItem], hasMore: Bool) {
        let data = try await fetchAccount(form)
        let medias = data["data"]["medias"].array ?? data["data"]["list"].array ?? []
        let items = medias.compactMap(Self.video(fromFavorite:))
        let hasMore = data["data"]["has_more"].bool ?? (items.count >= 20)
        return (items, hasMore)
    }

    private static func requireOK(_ data: JSON) throws {
        let code = data["code"].int ?? -1
        if code == -101 { throw BiliError.message("登录已失效") }
        guard code == 0 else { throw BiliError.message(data["message"].string ?? "操作没有成功") }
    }

    static func folder(from item: JSON) -> FavFolder? {
        let id = item["id"].int ?? item["media_id"].int ?? 0
        let title = item["title"].string ?? ""
        guard id > 0, !title.isEmpty else { return nil }
        return FavFolder(
            id: id,
            title: unescape(title),
            count: item["media_count"].int ?? item["count"].int ?? 0,
            favored: (item["fav_state"].int ?? 0) == 1 || item["fav_state"].bool == true
        )
    }

    static func video(fromHistory item: JSON) -> VideoItem? {
        let history = item["history"]
        let aid = history["oid"].int ?? item["aid"].int ?? 0
        let bvid = history["bvid"].string ?? item["bvid"].string ?? ""
        let title = item["title"].string ?? ""
        guard aid > 0 || !bvid.isEmpty, !title.isEmpty else { return nil }
        let business = history["business"].string ?? "archive"
        guard business == "archive" || business == "pgc" || !bvid.isEmpty else { return nil }
        return VideoItem(
            bvid: bvid.isEmpty ? "av\(aid)" : bvid,
            aid: aid,
            cid: history["cid"].int ?? 0,
            title: unescape(title),
            cover: https(item["cover"].string ?? ""),
            duration: item["duration"].int ?? 0,
            ownerName: item["author_name"].string ?? "",
            ownerMid: item["author_mid"].int ?? 0,
            ownerFace: https(item["author_face"].string ?? ""),
            desc: item["show_title"].string ?? "",
            pubdate: item["view_at"].int ?? 0,
            view: item["stat"]["view"].int ?? 0,
            danmaku: item["stat"]["danmaku"].int ?? 0,
            like: 0,
            coin: 0,
            favorite: 0,
            share: 0,
            reply: 0,
            pages: [],
            tname: item["badge"].string ?? "",
            progress: item["progress"].int ?? 0,
            viewAt: item["view_at"].int ?? 0
        )
    }

    static func video(fromFavorite item: JSON) -> VideoItem? {
        let bvid = item["bvid"].string ?? item["bv_id"].string ?? ""
        let aid = item["id"].int ?? item["aid"].int ?? 0
        let title = item["title"].string ?? ""
        guard !title.isEmpty, aid > 0 || !bvid.isEmpty else { return nil }
        let upper = item["upper"]
        return VideoItem(
            bvid: bvid.isEmpty ? "av\(aid)" : bvid,
            aid: aid,
            cid: 0,
            title: unescape(title),
            cover: https(item["cover"].string ?? item["pic"].string ?? ""),
            duration: item["duration"].int ?? 0,
            ownerName: upper["name"].string ?? item["owner"]["name"].string ?? item["author_name"].string ?? "",
            ownerMid: upper["mid"].int ?? item["owner"]["mid"].int ?? 0,
            ownerFace: https(upper["face"].string ?? ""),
            desc: unescape(item["intro"].string ?? ""),
            pubdate: item["pubtime"].int ?? item["pubdate"].int ?? 0,
            view: item["cnt_info"]["play"].int ?? item["stat"]["view"].int ?? 0,
            danmaku: item["cnt_info"]["danmaku"].int ?? item["stat"]["danmaku"].int ?? 0,
            like: 0,
            coin: 0,
            favorite: item["cnt_info"]["collect"].int ?? 0,
            share: 0,
            reply: 0,
            pages: [],
            tname: ""
        )
    }

    private func withGuest<T>(_ work: () async throws -> T) async throws -> T {
        await GuestIdentity.prepare(session: session)
        do {
            return try await work()
        } catch let error as BiliError where error.isRiskControl {
            await GuestIdentity.refresh(session: session)
            return try await work()
        }
    }

    func searchVideos(keyword: String, order: String = "totalrank", duration: Int = 0, tid: Int = 0, page: Int = 1) async throws -> [VideoItem] {
        try await search(type: "video", keyword: keyword, page: page, order: order, duration: duration, tid: tid).videos
    }

    func search(type: String, keyword: String, page: Int, order: String = "", duration: Int = 0, tid: Int = 0) async throws -> SearchPage {
        let form = SocialRequest.search(type: type, keyword: keyword, page: page, order: order, duration: duration, tid: tid)
        var found = try await fetchSearch(form, signed: false)
        let media = type == "media_bangumi" || type == "media_ft"
        if Self.searchIsEmpty(found) {
            if media { await refreshGuest() }
            if let signed = try? await fetchSearch(form, signed: true), !Self.searchIsEmpty(signed) {
                found = signed
            }
        }
        if Self.searchIsEmpty(found), media {
            let grouped = (try? await groupedMedia(keyword: keyword, page: page, type: type)) ?? []
            if !grouped.isEmpty {
                found = SearchPage(videos: [], users: [], seasons: grouped, lives: [], articles: [])
            }
        }
        // Type search answers with an empty list for bangumi on this network.
        // The public PGC rank already includes the same shows, so match it by title.
        if Self.searchIsEmpty(found), media {
            let ranked = await rankedSeasons(matching: keyword, type: type)
            if !ranked.isEmpty {
                found = SearchPage(videos: [], users: [], seasons: ranked, lives: [], articles: [])
            }
        }
        return found
    }

    private func groupedMedia(keyword: String, page: Int, type: String) async throws -> [SeasonItem] {
        let encoded = PercentEncoding.encodeURIComponent(keyword)
        guard let url = URL(string: "https://api.bilibili.com/x/web-interface/search/all/v2?keyword=\(encoded)&page=\(max(1, page))") else {
            return []
        }
        let data = try await withGuest {
            let data = try await getJSON(url, referer: "https://search.bilibili.com")
            let code = data["code"].int ?? -1
            if code == -352 || code == 412 { throw BiliError.risk(code) }
            return data
        }
        guard data["code"].int == 0 else { return [] }
        let wanted = type == "media_ft" ? "media_ft" : "media_bangumi"
        var seasons: [SeasonItem] = []
        for group in data["data"]["result"].array ?? [] {
            guard group["result_type"].string == wanted else { continue }
            seasons.append(contentsOf: (group["data"].array ?? []).compactMap(Self.bangumi(fromSearch:)))
        }
        return seasons
    }

    private func rankedSeasons(matching keyword: String, type: String) async -> [SeasonItem] {
        let word = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return [] }
        let kinds = type == "media_ft" ? [2, 5] : [1, 4]
        var items: [SeasonItem] = []
        for kind in kinds {
            if let page = try? await seasons(type: kind) {
                items.append(contentsOf: page)
            }
        }
        var seen = Set<Int>()
        return items.filter { item in
            let title = item.title
            let hit = title.localizedStandardContains(word) || word.localizedStandardContains(title)
            guard hit, seen.insert(item.seasonID).inserted else { return false }
            return true
        }
    }

    private func fetchSearch(_ form: SignedForm, signed: Bool) async throws -> SearchPage {
        let data = try await withGuest {
            let payload: JSON
            if signed {
                payload = try await requestQuery(
                    "/x/web-interface/wbi/search/type",
                    params: form.fields,
                    signed: true,
                    referer: "https://search.bilibili.com"
                )
            } else {
                guard let url = form.endpoint else { throw BiliError.message("地址无效") }
                payload = try await getJSON(url, referer: "https://search.bilibili.com")
            }
            let code = payload["code"].int ?? -1
            if code == -352 || code == 412 { throw BiliError.risk(code) }
            return payload
        }
        guard data["code"].int == 0 else {
            throw BiliError.message(data["message"].string ?? "搜索失败")
        }
        return Self.interpretSearch(data)
    }

    private static func searchIsEmpty(_ page: SearchPage) -> Bool {
        page.videos.isEmpty && page.users.isEmpty && page.seasons.isEmpty && page.lives.isEmpty && page.articles.isEmpty
    }

    private static func interpretSearch(_ data: JSON) -> SearchPage {
        let list = searchRows(data["data"]["result"])
        var page = searchPage(list)
        if searchIsEmpty(page) {
            let nested = list.flatMap { $0["data"].array ?? [] }
            if !nested.isEmpty { page = searchPage(nested) }
        }
        if searchIsEmpty(page) {
            let keys = (list.first?.raw as? [String: Any])?.keys.sorted().joined(separator: ",") ?? ""
            page.note = "rows=\(list.count) keys=\(keys)"
        }
        return page
    }

    private static func searchPage(_ list: [JSON]) -> SearchPage {
        SearchPage(
            videos: list.compactMap(video(fromSearch:)),
            users: list.compactMap(user(fromSearch:)),
            seasons: list.compactMap(bangumi(fromSearch:)),
            lives: list.compactMap(live(fromSearch:)),
            articles: list.compactMap(article(fromSearch:))
        )
    }

    func hotwords() async throws -> [HotWord] {
        let data = try await getJSON(URL(string: "https://s.search.bilibili.com/main/hotword")!)
        let list = data["list"].array ?? []
        return list.compactMap { item in
            guard let keyword = item["keyword"].string else { return nil }
            return HotWord(keyword: keyword, show: item["show_name"].string ?? keyword)
        }
    }

    func detail(bvid: String) async throws -> VideoItem {
        try await loadDetail(bvid: bvid, allowRefresh: true)
    }

    func refreshGuest() async {
        await GuestIdentity.refresh(session: session)
    }

    func related(bvid: String) async throws -> [VideoItem] {
        let data = try await getJSON("https://api.bilibili.com/x/web-interface/archive/related?bvid=\(bvid)")
        return (data["data"].array ?? []).compactMap(Self.video(fromRelated:))
    }

    func replies(aid: Int, page: Int = 1, sort: Int = 1) async throws -> [CommentItem] {
        try await replies(oid: aid, type: 1, page: page, sort: sort)
    }

    func replies(oid: Int, type: Int, page: Int = 1, sort: Int = 1) async throws -> [CommentItem] {
        try await replyPage(SocialRequest.replyList(oid: oid, sort: sort, page: page, type: type))
    }

    func replyThread(oid: Int, root: Int, page: Int, type: Int = 1) async throws -> [CommentItem] {
        try await replyPage(SocialRequest.replyThread(oid: oid, root: root, page: page, type: type))
    }

    private func replyPage(_ form: SignedForm) async throws -> [CommentItem] {
        guard let url = form.endpoint else { throw BiliError.message("地址无效") }
        let data = try await getJSON(url)
        guard data["code"].int == 0 else { throw BiliError.message(data["message"].string ?? "评论不可用") }
        return (data["data"]["replies"].array ?? []).compactMap(Self.comment)
    }

    /// DASH playurl. Upstream signs `/x/player/wbi/playurl` (`fnval` 4048, no `platform=html5`).
    /// A 412 refreshes buvid3/buvid4 and retries once, then falls back to the unsigned playurl and html5 `durl`.
    func playback(bvid: String, cid: Int, qn: Int, tryLook: Bool, codecPreference: String, audioPreference: String) async throws -> PlaybackOffer {
        try await loadPlayback(
            bvid: bvid,
            cid: cid,
            qn: qn,
            tryLook: tryLook,
            codecPreference: codecPreference,
            audioPreference: audioPreference,
            allowRefresh: true
        )
    }

    func danmaku(cid: Int) async throws -> [DanmakuCue] {
        DanmakuXML.parse(try await danmakuDocument(cid: cid))
    }

    func danmakuDocument(cid: Int) async throws -> Data {
        await GuestIdentity.prepare(session: session)
        guard let url = URL(string: "https://api.bilibili.com/x/v1/dm/list.so?oid=\(cid)") else {
            throw BiliError.message("弹幕地址无效")
        }
        let data = try await getData(url, includeSession: false)
        guard let xml = RawInflate.expand(data) else { throw BiliError.message("弹幕解压失败") }
        return xml
    }

    func subtitleLines(bvid: String, cid: Int, preference: String) async -> [SubtitleLine] {
        await GuestIdentity.prepare(session: session)
        let params = ["bvid": bvid, "cid": "\(cid)"]
        let data: JSON
        if let signed = try? await requestQuery("/x/player/wbi/v2", params: params, signed: true), signed["code"].int == 0 {
            data = signed
        } else if let plain = try? await requestQuery("/x/player/v2", params: params, signed: false), plain["code"].int == 0 {
            data = plain
        } else {
            return []
        }
        let tracks = (data["data"]["subtitle"]["subtitles"].array ?? []).compactMap { item -> (lan: String, doc: String, url: String)? in
            let lan = item["lan"].string ?? ""
            let doc = item["lan_doc"].string ?? ""
            let raw = item["subtitle_url"].string ?? ""
            guard !raw.isEmpty else { return nil }
            return (lan, doc, Self.https(raw))
        }
        guard let track = tracks.enumerated().min(by: { lhs, rhs in
            let left = SubtitlePicker.pick(lan: lhs.element.lan, doc: lhs.element.doc, preference: preference)
            let right = SubtitlePicker.pick(lan: rhs.element.lan, doc: rhs.element.doc, preference: preference)
            if left != right { return left < right }
            return lhs.offset < rhs.offset
        })?.element else { return [] }
        guard let fileURL = URL(string: track.url), let file = try? await getJSON(fileURL) else { return [] }
        return (file["body"].array ?? []).compactMap { row in
            let text = row["content"].string ?? ""
            guard !text.isEmpty, let from = row["from"].double, let to = row["to"].double else { return nil }
            return SubtitleLine(from: from, to: to, text: text)
        }
    }

    private func loadDetail(bvid: String, allowRefresh: Bool) async throws -> VideoItem {
        await GuestIdentity.prepare(session: session)
        let params = ["bvid": bvid]
        do {
            let data = try await viewPayload(params)
            guard data["code"].int == 0 else {
                throw BiliError.message(data["message"].string ?? "无法打开视频")
            }
            guard let video = Self.video(fromView: data["data"]) else { throw BiliError.message("视频数据为空") }
            return video
        } catch let error as BiliError where error.isRiskControl && allowRefresh {
            await GuestIdentity.refresh(session: session)
            return try await loadDetail(bvid: bvid, allowRefresh: false)
        }
    }

    private func viewPayload(_ params: [String: String]) async throws -> JSON {
        let referer = BiliHTTP.referer(bvid: params["bvid"] ?? "")
        if let signed = try? await requestQuery("/x/web-interface/wbi/view", params: params, signed: true, referer: referer),
           signed["code"].int == 0 {
            return signed
        }
        return try await requestQuery("/x/web-interface/view", params: params, signed: false, referer: referer)
    }

    private func loadPlayback(
        bvid: String,
        cid: Int,
        qn: Int,
        tryLook: Bool,
        codecPreference: String,
        audioPreference: String,
        allowRefresh: Bool
    ) async throws -> PlaybackOffer {
        await GuestIdentity.prepare(session: session)
        let params = dashParams(bvid: bvid, cid: cid, qn: qn, tryLook: tryLook)
        let referer = BiliHTTP.referer(bvid: bvid)
        var failure = PlaybackAttempt()
        if let offer = await oneOffer(params, signed: true, qn: qn, codecPreference: codecPreference, audioPreference: audioPreference, referer: referer, failure: &failure) {
            return offer
        }
        if let offer = await oneOffer(params, signed: false, qn: qn, codecPreference: codecPreference, audioPreference: audioPreference, referer: referer, failure: &failure) {
            return offer
        }
        var html5 = [
            "bvid": bvid,
            "cid": "\(cid)",
            "qn": "\(qn)",
            "fnval": "1",
            "fnver": "0",
            "fourk": "1",
            "platform": "html5"
        ]
        if tryLook { html5["try_look"] = "1" }
        if let offer = await oneOffer(html5, signed: false, qn: qn, codecPreference: codecPreference, audioPreference: audioPreference, referer: referer, failure: &failure) {
            return offer
        }
        if failure.sawRiskControl, allowRefresh {
            await GuestIdentity.refresh(session: session)
            return try await loadPlayback(
                bvid: bvid,
                cid: cid,
                qn: qn,
                tryLook: tryLook,
                codecPreference: codecPreference,
                audioPreference: audioPreference,
                allowRefresh: false
            )
        }
        if let last = failure.last { throw last }
        throw BiliError.message("没有可播放地址")
    }

    private func oneOffer(
        _ params: [String: String],
        signed: Bool,
        qn: Int,
        codecPreference: String,
        audioPreference: String,
        referer: String,
        failure: inout PlaybackAttempt
    ) async -> PlaybackOffer? {
        do {
            return try await playOffer(
                params,
                signed: signed,
                qn: qn,
                codecPreference: codecPreference,
                audioPreference: audioPreference,
                referer: referer
            )
        } catch {
            failure.note(error)
            return nil
        }
    }

    private func dashParams(bvid: String, cid: Int, qn: Int, tryLook: Bool) -> [String: String] {
        var params = [
            "bvid": bvid,
            "cid": "\(cid)",
            "qn": "\(qn)",
            "fnval": "4048",
            "fnver": "0",
            "fourk": "1",
            "gaia_source": "pre-load",
            "isGaiaAvoided": "true",
            "web_location": "1315873",
            "dm_img_list": "[]",
            "dm_img_str": BiliHTTP.randomToken(minCount: 16, maxCount: 64),
            "dm_cover_img_str": BiliHTTP.randomToken(minCount: 32, maxCount: 128),
            "dm_img_inter": "{\"ds\":[],\"wh\":[0,0,0],\"of\":[0,0,0]}"
        ]
        if tryLook { params["try_look"] = "1" }
        return params
    }

    private func playOffer(
        _ params: [String: String],
        signed: Bool,
        qn: Int,
        codecPreference: String,
        audioPreference: String,
        referer: String
    ) async throws -> PlaybackOffer? {
        let path = signed ? "/x/player/wbi/playurl" : "/x/player/playurl"
        let data = try await requestQuery(path, params: params, signed: signed, referer: referer)
        guard data["code"].int == 0 else { return nil }
        return PlaybackParser.offer(
            from: data,
            requestedQN: qn,
            codecPreference: codecPreference,
            audioPreference: audioPreference
        )
    }

    private func requestQuery(
        _ path: String,
        params: [String: String],
        signed: Bool,
        referer: String? = nil,
        origin: String? = nil,
        userAgent: String? = nil,
        host: String = "https://api.bilibili.com",
        suppressCookie: Bool = false
    ) async throws -> JSON {
        let fields = signed ? try await wbiSign(params) : params
        let stripped = CharacterSet(charactersIn: "!'()*")
        let query = fields.keys.sorted().map { key in
            var value = fields[key, default: ""]
            if signed {
                value = value.components(separatedBy: stripped).joined()
            }
            return "\(PercentEncoding.encodeURIComponent(key))=\(PercentEncoding.encodeURIComponent(value))"
        }.joined(separator: "&")
        guard let url = URL(string: "\(host)\(path)?\(query)") else {
            throw BiliError.message("地址无效")
        }
        return try await getJSON(url, referer: referer, origin: origin, userAgent: userAgent, suppressCookie: suppressCookie)
    }

    func liveRooms() async throws -> [LiveRoom] {
        try await liveList(area: "推荐", page: 1)
    }

    func liveList(area: String, page: Int) async throws -> [LiveRoom] {
        var web: [SignedForm] = []
        var app: [SignedForm] = []
        if area == "推荐" {
            if page <= 1 { web.append(LiveRequest.moreRecommend()) }
            web.append(LiveRequest.recommend(page: page))
            web.append(LiveRequest.area(parent: 0, page: page, sort: "online"))
            web.append(LiveRequest.area(parent: 0, page: page))
            app.append(LiveRequest.appFeed(page: page))
        } else {
            let parent = LiveRequest.parentID(for: area)
            web.append(LiveRequest.roomList(parent: parent, page: page))
            web.append(Self.guardedArea(parent: parent, page: page, sort: "online"))
            web.append(Self.guardedArea(parent: parent, page: page, sort: ""))
            app.append(LiveRequest.appArea(parent: parent, page: page))
        }
        var last = "没有直播"
        for form in web {
            do {
                let rooms = try await fetchLive(form, signed: !form.path.hasPrefix("/room/"))
                if !rooms.isEmpty {
                    print("live list ok \(form.path) \(rooms.count)")
                    return rooms
                }
                last = "\(form.path) empty"
            } catch {
                last = error.localizedDescription
                print("live list \(form.path) \(last)")
            }
        }
        for form in app {
            do {
                let rooms = try await fetchAppLive(form)
                if !rooms.isEmpty {
                    print("live list ok \(form.path) \(rooms.count)")
                    return rooms
                }
                last = "\(form.path) empty"
            } catch {
                last = error.localizedDescription
                print("live list \(form.path) \(last)")
            }
        }
        if page > 1 { return [] }
        throw BiliError.message(last)
    }

    /// Area `getList` rejects a bare WBI query. The same dm_img fields used by space dynamics go with it.
    private static func guardedArea(parent: Int, page: Int, sort: String) -> SignedForm {
        var fields = LiveRequest.area(parent: parent, page: page, sort: sort).fields
        fields["web_location"] = "444.8"
        fields["dm_img_list"] = "[]"
        fields["dm_img_str"] = BiliHTTP.randomToken(minCount: 16, maxCount: 64)
        fields["dm_cover_img_str"] = BiliHTTP.randomToken(minCount: 32, maxCount: 128)
        fields["dm_img_inter"] = "{\"ds\":[],\"wh\":[0,0,0],\"of\":[0,0,0]}"
        return SignedForm(method: "GET", path: "/xlive/web-interface/v1/second/getList", fields: fields)
    }

    func liveRoomInfo(room: Int) async throws -> LiveRoom {
        let data = try await withGuest {
            try await getJSON(
                liveURL(LiveRequest.roomInfo(room: room)),
                referer: "https://live.bilibili.com/\(room)",
                origin: "https://live.bilibili.com",
                userAgent: BiliHTTP.pcUserAgent
            )
        }
        try Self.requireOK(data)
        let info = data["data"]["room_info"]
        let anchor = data["data"]["anchor_info"]["base_info"]
        let id = info["room_id"].int ?? room
        return LiveRoom(
            id: id,
            title: Self.unescape(info["title"].string ?? "直播间"),
            cover: Self.https(info["cover"].string ?? info["keyframe"].string ?? ""),
            uname: anchor["uname"].string ?? "",
            face: Self.https(anchor["face"].string ?? ""),
            online: info["online"].int ?? 0,
            area: info["area_name"].string ?? info["parent_area_name"].string ?? "直播",
            mid: anchor["uid"].int ?? anchor["mid"].int ?? info["uid"].int ?? 0
        )
    }

    func livePlay(room: Int, qn: Int) async throws -> LiveOffer {
        let form = LiveRequest.playInfo(room: room, qn: qn)
        let data = try await withGuest {
            let data = try await requestQuery(
                form.path,
                params: form.fields,
                signed: true,
                referer: "https://live.bilibili.com/\(room)",
                origin: "https://live.bilibili.com",
                userAgent: BiliHTTP.pcUserAgent,
                host: "https://api.live.bilibili.com"
            )
            let code = data["code"].int ?? -1
            if code == -352 || code == 412 { throw BiliError.risk(code) }
            return data
        }
        try Self.requireOK(data)
        guard let offer = Self.liveOffer(from: data, requestedQN: qn) else {
            throw BiliError.message("没有可播放的直播流")
        }
        return offer
    }

    func liveDanmuInfo(room: Int) async throws -> LiveDanmuInfo {
        let form = LiveRequest.danmuInfo(room: room)
        let data = try await withGuest {
            let data = try await requestQuery(
                form.path,
                params: form.fields,
                signed: true,
                referer: "https://live.bilibili.com/\(room)",
                origin: "https://live.bilibili.com",
                userAgent: BiliHTTP.pcUserAgent,
                host: "https://api.live.bilibili.com"
            )
            let code = data["code"].int ?? -1
            if code == -352 || code == 412 { throw BiliError.risk(code) }
            return data
        }
        try Self.requireOK(data)
        let token = data["data"]["token"].string ?? ""
        guard !token.isEmpty else { throw BiliError.message("没有弹幕令牌") }
        let hosts = (data["data"]["host_list"].array ?? []).compactMap { item -> LiveDanmuHost? in
            let host = item["host"].string ?? ""
            guard !host.isEmpty else { return nil }
            return LiveDanmuHost(host: host, wssPort: item["wss_port"].int ?? 443)
        }.sorted { Self.danmuHostRank($0) < Self.danmuHostRank($1) }
        guard !hosts.isEmpty else { throw BiliError.message("没有弹幕服务器") }
        return LiveDanmuInfo(token: token, hosts: hosts)
    }

    /// `broadcastlv` is the web default. Overseas comet hosts answered but then stayed quiet.
    private static func danmuHostRank(_ host: LiveDanmuHost) -> Int {
        let name = host.host
        if name.contains("broadcastlv") { return 0 }
        if name.hasPrefix("hw-") || name.hasPrefix("ali-") || name.contains("-sg-") { return 2 }
        return 1
    }

    func sendLiveDanmaku(room: Int, message: String, csrf: String) async throws {
        let form = LiveRequest.send(room: room, message: message, csrf: csrf, rnd: Int(Date().timeIntervalSince1970))
        let signed = try await wbiSign(["web_location": "444.8"])
        let query = signed.keys.sorted().map { key in
            "\(PercentEncoding.encodeURIComponent(key))=\(PercentEncoding.encodeURIComponent(signed[key, default: ""]))"
        }.joined(separator: "&")
        guard let url = URL(string: "https://api.live.bilibili.com/msg/send?\(query)") else {
            throw BiliError.message("地址无效")
        }
        let data = try await postForm(
            url,
            fields: form.fields,
            referer: "https://live.bilibili.com/\(room)",
            origin: "https://live.bilibili.com",
            userAgent: BiliHTTP.pcUserAgent
        )
        try Self.requireOK(data)
    }

    private func fetchLive(_ form: SignedForm, signed: Bool = true) async throws -> [LiveRoom] {
        let data = try await withGuest {
            let data = try await requestQuery(
                form.path,
                params: form.fields,
                signed: signed,
                referer: "https://live.bilibili.com",
                origin: "https://live.bilibili.com",
                userAgent: BiliHTTP.pcUserAgent,
                host: "https://api.live.bilibili.com"
            )
            let code = data["code"].int ?? -1
            if code == -352 || code == 412 { throw BiliError.risk(code) }
            return data
        }
        try Self.requireOK(data)
        return Self.loggedLiveRooms(form.path, data)
    }

    private static let appLiveAgent = "Mozilla/5.0 BiliDroid/8.43.0 (bbcallen@gmail.com) os/android model/android mobi_app/android build/8430300 channel/master innerVer/8430300 osVer/15 network/2"

    /// App-signed homepage and area lists used by upstream `LiveHttp.liveFeedIndex` / `liveSecondList`.
    private func fetchAppLive(_ form: SignedForm) async throws -> [LiveRoom] {
        let data = try await withGuest {
            let signed = AppSign.sign(form.fields)
            let query = signed.keys.sorted().map { key in
                let value = signed[key, default: ""]
                if value.isEmpty { return PercentEncoding.encodeURIComponent(key) }
                return "\(PercentEncoding.encodeURIComponent(key))=\(PercentEncoding.encodeURIComponent(value))"
            }.joined(separator: "&")
            guard let url = URL(string: "https://api.live.bilibili.com\(form.path)?\(query)") else {
                throw BiliError.message("地址无效")
            }
            let data = try await getJSON(
                url,
                referer: "https://live.bilibili.com",
                origin: "https://live.bilibili.com",
                userAgent: Self.appLiveAgent
            )
            let code = data["code"].int ?? -1
            if code == -352 || code == 412 { throw BiliError.risk(code) }
            return data
        }
        try Self.requireOK(data)
        return Self.loggedLiveRooms(form.path, data)
    }

    private static func loggedLiveRooms(_ path: String, _ data: JSON) -> [LiveRoom] {
        let rooms = liveRooms(in: data)
        if rooms.isEmpty {
            let keys = (data["data"].raw as? [String: Any])?.keys.sorted().joined(separator: ",") ?? ""
            let raw = String(describing: data.raw)
            print("live list empty \(path) keys=\(keys) \(raw.prefix(360))")
        }
        return rooms
    }

    private func liveURL(_ form: SignedForm) throws -> URL {
        guard let url = URL(string: "https://api.live.bilibili.com\(form.path)?\(form.body)") else {
            throw BiliError.message("地址无效")
        }
        return url
    }

    func followDynamics(type: String, offset: String) async throws -> (items: [DynamicItem], offset: String, hasMore: Bool) {
        let data = try await fetchAccount(SocialRequest.followFeed(type: type, offset: offset))
        let items = (data["data"]["items"].array ?? []).compactMap(Self.dynamic(fromPolymer:))
        let next = data["data"]["offset"].string ?? ""
        let hasMore = data["data"]["has_more"].bool ?? !next.isEmpty
        return (items, next, hasMore && !items.isEmpty)
    }

    func dynamicDetail(id: String) async throws -> DynamicItem {
        let data = try await wbiJSON(
            "/x/polymer/web-dynamic/v1/detail",
            params: [
                "timezone_offset": "-480",
                "id": id,
                "features": DynamicRequest.features
            ],
            referer: "https://t.bilibili.com/\(id)",
            origin: "https://t.bilibili.com"
        )
        try Self.requireOK(data)
        let item = data["data"]["item"]
        guard let built = Self.dynamic(fromPolymer: item) else {
            throw BiliError.message("这条动态没有内容")
        }
        return await enrichPoll(built)
    }

    func hotTopics() async throws -> [TopicItem] {
        if let hot = try? await topicGET("/x/topic/web/hot", fields: ["page_num": "1", "page_size": "20"]) {
            let parsed = Self.topics(in: hot)
            if !parsed.isEmpty { return parsed }
        }
        return try await mergedTopics(keywords: ["日常", "游戏", "音乐", "动画"])
    }

    func searchTopics(keyword: String) async throws -> [TopicItem] {
        let data = try await topicGET("/x/topic/pub/search", fields: [
            "keywords": keyword,
            "page_num": "1",
            "page_size": "20"
        ])
        return Self.topics(in: data)
    }

    private func mergedTopics(keywords: [String]) async throws -> [TopicItem] {
        var seen = Set<Int>()
        var rows: [TopicItem] = []
        var last: Error?
        for word in keywords {
            do {
                for topic in try await searchTopics(keyword: word) where seen.insert(topic.id).inserted {
                    rows.append(topic)
                }
            } catch {
                last = error
            }
        }
        if rows.isEmpty, let last { throw last }
        return rows
    }

    func followedTopics() async throws -> [TopicItem] {
        let data = try await topicGET("/x/topic/web/fav/list", fields: ["page_num": "1", "page_size": "20"])
        return Self.topics(in: data)
    }

    func topicDynamics(id: Int) async throws -> [DynamicItem] {
        let data = try await topicGET("/x/topic/web/details/cards", fields: [
            "topic_id": "\(id)",
            "sort_by": "3",
            "page_size": "15",
            "offset": ""
        ])
        let items = data["data"]["topic_card_list"]["items"].array
            ?? data["data"]["topic_card_list"]["dynamic_list"].array
            ?? data["data"]["items"].array
            ?? []
        var rows: [DynamicItem] = []
        for item in items {
            guard var built = Self.dynamic(fromPolymer: Self.polymerCard(item)) else { continue }
            built = await enrichPoll(built)
            rows.append(built)
        }
        return rows
    }

    func repostDynamic(id: String, content: String, csrf: String) async throws {
        guard let url = URL(string: DynamicRequest.repostURL) else { throw BiliError.message("地址无效") }
        let data = try await postForm(
            url,
            fields: DynamicRequest.repostFields(dynamicID: id, content: content, csrf: csrf),
            includeCSRF: false,
            referer: "https://t.bilibili.com",
            origin: "https://t.bilibili.com"
        )
        try Self.requireOK(data)
    }

    func likeDynamic(id: String, liked: Bool, csrf: String) async throws {
        guard let url = URL(string: DynamicRequest.likeURL) else { throw BiliError.message("地址无效") }
        let data = try await postForm(
            url,
            fields: DynamicRequest.likeFields(dynamicID: id, liked: liked, csrf: csrf),
            includeCSRF: false,
            referer: "https://t.bilibili.com",
            origin: "https://t.bilibili.com"
        )
        try Self.requireOK(data)
    }

    func publishDynamic(text: String, images: [String], topicID: Int, topicName: String, repostID: String, csrf: String) async throws {
        guard let url = URL(string: "https://api.bilibili.com/x/dynamic/feed/create/dyn?csrf=\(PercentEncoding.encodeURIComponent(csrf))") else {
            throw BiliError.message("地址无效")
        }
        let raw = DynamicRequest.createBody(text: text, images: images, topicID: topicID, topicName: topicName, repostID: repostID)
        guard !raw.isEmpty else { throw BiliError.message("动态内容无效") }
        let body = Data(raw.utf8)
        let data = try await send(
            url,
            method: "POST",
            body: body,
            contentType: "application/json",
            includeSession: true,
            cookieOverride: nil,
            referer: "https://t.bilibili.com",
            origin: "https://t.bilibili.com"
        )
        try Self.requireOK(data)
    }

    func uploadDynamicImage(_ data: Data, csrf: String) async throws -> String {
        let boundary = "PiliPlus\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file_up\"; filename=\"image.jpg\"\r\n")
        append("Content-Type: image/jpeg\r\n\r\n")
        body.append(data)
        append("\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"category\"\r\n\r\ndaily\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"csrf\"\r\n\r\n\(csrf)\r\n")
        append("--\(boundary)--\r\n")
        guard let url = URL(string: "https://api.bilibili.com/x/dynamic/feed/draw/upload_bfs") else {
            throw BiliError.message("地址无效")
        }
        let json = try await send(
            url,
            method: "POST",
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)",
            includeSession: true,
            cookieOverride: nil,
            referer: "https://t.bilibili.com",
            origin: "https://t.bilibili.com"
        )
        try Self.requireOK(json)
        let remote = Self.https(json["data"]["image_url"].string ?? json["data"]["url"].string ?? "")
        guard !remote.isEmpty else { throw BiliError.message("图片没有传上去") }
        return remote
    }

    private static func polymerCard(_ item: JSON) -> JSON {
        if item["dynamic_card_item"]["id_str"].string?.isEmpty == false {
            return item["dynamic_card_item"]
        }
        return item
    }

    private func enrichPoll(_ item: DynamicItem) async -> DynamicItem {
        guard item.pollOptions.isEmpty, item.pollVoteID > 0 else { return item }
        guard let info = try? await voteInfo(id: item.pollVoteID), info.options.count >= 2 else { return item }
        var copy = item
        if copy.pollTitle.isEmpty { copy.pollTitle = info.title }
        copy.pollOptions = info.options
        copy.pollCounts = info.counts
        if info.joined > 0 { copy.pollJoined = info.joined }
        return copy
    }

    private func voteInfo(id: Int) async throws -> (title: String, options: [String], counts: [Int], joined: Int) {
        guard let url = URL(string: "https://api.vc.bilibili.com/vote_svr/v1/vote_svr/vote_info?vote_id=\(id)") else {
            throw BiliError.message("地址无效")
        }
        let data = try await getJSON(url, referer: "https://t.bilibili.com", origin: "https://t.bilibili.com")
        try Self.requireOK(data)
        let info = data["data"]["info"]
        let title = info["title"].string ?? info["desc"].string ?? ""
        var options: [String] = []
        var counts: [Int] = []
        for choice in info["options"].array ?? [] {
            let name = choice["desc"].string ?? choice["title"].string ?? ""
            guard !name.isEmpty else { continue }
            options.append(name)
            counts.append(choice["cnt"].int ?? 0)
        }
        let joined = info["cnt"].int ?? info["join_num"].int ?? counts.reduce(0, +)
        return (title.isEmpty ? "投票" : title, options, counts, joined)
    }

    private func topicGET(_ path: String, fields: [String: String]) async throws -> JSON {
        let data = try await requestQuery(
            path,
            params: fields,
            signed: false,
            referer: "https://www.bilibili.com",
            origin: "https://www.bilibili.com",
            host: "https://app.bilibili.com"
        )
        try Self.requireOK(data)
        return data
    }

    private static func topics(in data: JSON) -> [TopicItem] {
        let lists = [
            data["data"]["topic_list"].array,
            data["data"]["topic_items"].array,
            data["data"]["list"].array,
            data["data"]["items"].array
        ].compactMap { $0 }
        let raw = lists.first ?? []
        return raw.compactMap { item in
            let id = item["id"].int ?? item["topic_id"].int ?? 0
            let name = item["name"].string ?? item["topic_name"].string ?? ""
            guard id > 0, !name.isEmpty else { return nil }
            return TopicItem(
                id: id,
                name: name,
                view: item["view"].int ?? item["view_count"].int ?? 0,
                discuss: item["discuss"].int ?? item["discuss_count"].int ?? 0,
                summary: item["description"].string ?? item["desc"].string ?? ""
            )
        }
    }

    func spaceProfile(mid: Int) async throws -> SpaceProfile {
        let data = try await loadPublic(SpaceRequest.profile(mid: mid), referer: "https://space.bilibili.com/\(mid)")
        let card = data["data"]["card"]
        let name = card["name"].string ?? ""
        guard !name.isEmpty else { throw BiliError.message("空间资料是空的") }
        return SpaceProfile(
            mid: card["mid"].int ?? mid,
            name: name,
            face: Self.https(card["face"].string ?? ""),
            sign: card["sign"].string ?? "",
            level: card["level_info"]["current_level"].int ?? 0,
            following: card["attention"].int ?? 0,
            fans: card["fans"].int ?? data["data"]["follower"].int ?? 0,
            likes: data["data"]["like_num"].int ?? card["likes"].int ?? 0,
            followed: data["data"]["following"].bool ?? false
        )
    }

    func spaceVideos(mid: Int, page: Int, order: String, keyword: String = "") async throws -> (items: [VideoItem], total: Int, source: String) {
        let referer = "https://space.bilibili.com/\(mid)/video"
        let origin = "https://space.bilibili.com"
        do {
            var params = SpaceRequest.videos(mid: mid, page: page, order: order).fields
            params["tid"] = "0"
            params["keyword"] = keyword
            params["index"] = "0"
            params["platform"] = "web"
            params["web_location"] = "1550101"
            params["order_avoided"] = "true"
            params["dm_img_list"] = "[]"
            params["dm_img_str"] = BiliHTTP.randomToken(minCount: 16, maxCount: 64)
            params["dm_cover_img_str"] = BiliHTTP.randomToken(minCount: 32, maxCount: 128)
            params["dm_img_inter"] = "{\"ds\":[],\"wh\":[0,0,0],\"of\":[0,0,0]}"
            let data = try await withGuest {
                let data = try await requestQuery(
                    "/x/space/wbi/arc/search",
                    params: params,
                    signed: true,
                    referer: referer,
                    origin: origin
                )
                let code = data["code"].int ?? -1
                if code == -352 || code == 412 { throw BiliError.risk(code) }
                return data
            }
            try Self.requireOK(data)
            let page = Self.spaceVideoPage(data)
            if !page.items.isEmpty { return (page.items, page.total, "wbi") }
            throw BiliError.message("投稿是空的")
        } catch {
            var minimal = [
                "mid": "\(mid)",
                "pn": "\(max(1, page))",
                "ps": "30",
                "order": order,
                "tid": "0",
                "platform": "web",
                "web_location": "1550101",
                "order_avoided": "true"
            ]
            if !keyword.isEmpty { minimal["keyword"] = keyword }
            if let signed = try? await wbiJSON("/x/space/wbi/arc/search", params: minimal, referer: referer, origin: origin) {
                let parsed = Self.spaceVideoPage(signed)
                if (signed["code"].int ?? -1) == 0, !parsed.items.isEmpty {
                    return (parsed.items, parsed.total, "wbi")
                }
            }
            if let fallback = try? await unsignedSpaceVideos(mid: mid, page: page, order: order, referer: referer, origin: origin),
               !fallback.items.isEmpty {
                return (fallback.items, fallback.total, "arc")
            }
            if page == 1,
               let collected = try? await seasonArchiveFallback(mid: mid, referer: referer, origin: origin),
               !collected.items.isEmpty {
                return (collected.items, collected.total, "season")
            }
            throw error
        }
    }

    /// First public collection, used when both contribution searches are blocked.
    private func seasonArchiveFallback(mid: Int, referer: String, origin: String) async throws -> (items: [VideoItem], total: Int) {
        let rows = try await spaceSeries(mid: mid, page: 1)
        guard let first = rows.first(where: { $0.kind == "合集" }) else { throw BiliError.message("没有合集") }
        let raw = first.id.split(separator: "-").dropFirst().joined(separator: "-")
        guard let seasonID = Int(raw), seasonID > 0 else { throw BiliError.message("合集编号无效") }
        let data = try await withGuest {
            let data = try await requestQuery(
                "/x/polymer/web-space/seasons_archives_list",
                params: [
                    "mid": "\(mid)",
                    "season_id": "\(seasonID)",
                    "sort_reverse": "false",
                    "page_num": "1",
                    "page_size": "30"
                ],
                signed: false,
                referer: referer,
                origin: origin
            )
            let code = data["code"].int ?? -1
            if code == -352 || code == 412 { throw BiliError.risk(code) }
            return data
        }
        try Self.requireOK(data)
        let list = data["data"]["archives"].array ?? data["data"]["list"].array ?? []
        let items = list.compactMap { item -> VideoItem? in
            if let video = Self.video(fromSpace: item) { return video }
            if let video = Self.video(fromSpace: item["archive"]) { return video }
            if var video = Self.video(fromPopular: item) {
                if video.cover.isEmpty { video.cover = Self.https(item["cover"].string ?? "") }
                return video
            }
            return Self.video(fromPopular: item["archive"])
        }
        guard !items.isEmpty else { throw BiliError.message("合集里没有视频") }
        let total = data["data"]["page"]["total"].int ?? data["data"]["page"]["count"].int ?? items.count
        return (items, total)
    }

    /// Older contribution search. Used only after the WBI route is rejected.
    private func unsignedSpaceVideos(
        mid: Int,
        page: Int,
        order: String,
        referer: String,
        origin: String
    ) async throws -> (items: [VideoItem], total: Int) {
        let params = [
            "mid": "\(mid)",
            "pn": "\(max(1, page))",
            "ps": "30",
            "tid": "0",
            "order": order,
            "index": "1",
            "order_avoided": "true",
            "platform": "web"
        ]
        let data = try await withGuest {
            let data = try await requestQuery(
                "/x/space/arc/search",
                params: params,
                signed: false,
                referer: referer,
                origin: origin
            )
            let code = data["code"].int ?? -1
            if code == -352 || code == 412 { throw BiliError.risk(code) }
            return data
        }
        try Self.requireOK(data)
        return Self.spaceVideoPage(data)
    }

    private static func spaceVideoPage(_ data: JSON) -> (items: [VideoItem], total: Int) {
        let list = data["data"]["list"]["vlist"].array ?? []
        let total = data["data"]["page"]["count"].int ?? list.count
        return (list.compactMap(video(fromSpace:)), total)
    }

    /// Upstream `Constants.dynFeatures` for `/x/polymer/web-dynamic/v1/feed/space`.
    private static let dynFeatures = "itemOpusStyle,listOnlyfans,opusBigCover,onlyfansVote,decorationCard,onlyfansAssetsV2,forwardListHidden,ugcDelete,onlyfansQaCard,commentsNewVersion,avatarAutoTheme,sunflowerStyle,cardsEnhance,eva3CardOpus,eva3CardVideo,eva3CardComment,eva3CardVote,eva3CardUser"

    func spaceDynamics(mid: Int, offset: String) async throws -> (items: [DynamicItem], offset: String, hasMore: Bool, source: String, guestRefused: Bool) {
        await refreshGuest()
        let params = [
            "offset": offset,
            "host_mid": "\(mid)",
            "timezone_offset": "-480",
            "features": Self.dynFeatures,
            "platform": "web",
            "web_location": "333.1387",
            "dm_img_list": "[]",
            "dm_img_str": BiliHTTP.randomToken(minCount: 16, maxCount: 64),
            "dm_cover_img_str": BiliHTTP.randomToken(minCount: 32, maxCount: 128),
            "dm_img_inter": "{\"ds\":[],\"wh\":[0,0,0],\"of\":[0,0,0]}",
            "x-bili-device-req-json": "{\"platform\":\"web\",\"device\":\"pc\",\"spmid\":\"333.1387\"}"
        ]
        let referer = "https://space.bilibili.com/\(mid)/dynamic"
        let origin = "https://space.bilibili.com"
        do {
            let data = try await wbiJSON(
                "/x/polymer/web-dynamic/v1/feed/space",
                params: params,
                referer: referer,
                origin: origin,
                userAgent: BiliHTTP.pcUserAgent
            )
            try Self.requireOK(data)
            let page = Self.polymerDynamics(data)
            return (page.items, page.offset, page.hasMore, "wbi", false)
        } catch let error as BiliError where Self.refusesGuests(error) {
            if !Self.hasLogin {
                return ([], "", false, "wbi", true)
            }
            throw error
        }
    }

    private static var hasLogin: Bool {
        let csrf = SessionVault.shared.current()?.csrf ?? ""
        return !csrf.isEmpty
    }

    private static func refusesGuests(_ error: BiliError) -> Bool {
        switch error {
        case .status(412), .status(-101), .risk:
            return true
        case .status:
            return false
        case .message(let text):
            return text.contains("登录") || text.contains("412") || text.contains("-352")
        }
    }

    private func wbiJSON(
        _ path: String,
        params: [String: String],
        referer: String,
        origin: String,
        userAgent: String? = nil
    ) async throws -> JSON {
        try await withGuest {
            let data = try await requestQuery(
                path,
                params: params,
                signed: true,
                referer: referer,
                origin: origin,
                userAgent: userAgent
            )
            let code = data["code"].int ?? -1
            if code == -352 || code == 412 || code == -101 { throw BiliError.risk(code) }
            return data
        }
    }

    private static func polymerDynamics(_ data: JSON) -> (items: [DynamicItem], offset: String, hasMore: Bool) {
        let items = (data["data"]["items"].array ?? []).compactMap(dynamic(fromPolymer:))
        let next = data["data"]["offset"].string ?? ""
        let hasMore = data["data"]["has_more"].bool ?? !next.isEmpty
        return (items, next, hasMore && !items.isEmpty)
    }

    /// `dynamic_svr/space_history` still returns cards when the polymer route answers 412.
    private func legacySpaceDynamics(
        mid: Int,
        offset: String,
        referer: String,
        origin: String
    ) async throws -> (items: [DynamicItem], offset: String, hasMore: Bool) {
        let cursor = offset.isEmpty ? "0" : offset
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        let encoded = cursor.addingPercentEncoding(withAllowedCharacters: allowed) ?? cursor
        guard let url = URL(string: "https://api.vc.bilibili.com/dynamic_svr/v1/dynamic_svr/space_history?host_uid=\(mid)&offset_dynamic_id=\(encoded)&need_top=1&platform=web") else {
            throw BiliError.message("地址无效")
        }
        let data = try await withGuest {
            let data = try await getJSON(url, referer: referer, origin: origin)
            let code = data["code"].int ?? -1
            if code == -352 || code == 412 { throw BiliError.risk(code) }
            return data
        }
        try Self.requireOK(data)
        let cards = data["data"]["cards"].array ?? []
        let items = cards.compactMap(Self.dynamic(fromLegacy:))
        let nextValue = data["data"]["next_offset"]
        let next = nextValue.string ?? (nextValue.int.map(String.init) ?? "")
        let hasMore = (data["data"]["has_more"].int ?? 0) == 1 || data["data"]["has_more"].bool == true
        return (items, next == "0" ? "" : next, hasMore && !items.isEmpty)
    }

    func spaceFolders(mid: Int) async throws -> (folders: [FavFolder], raw: Int) {
        let data = try await loadPublic(SpaceRequest.folders(mid: mid), referer: "https://space.bilibili.com/\(mid)", origin: "https://space.bilibili.com")
        let list = data["data"]["list"].array ?? data["data"].array ?? []
        let folders = list.compactMap { item -> FavFolder? in
            let attr = item["attr"].int ?? 0
            guard attr & 1 == 0 else { return nil }
            return Self.folder(from: item)
        }
        return (folders, list.count)
    }

    func spaceBangumi(mid: Int, page: Int) async throws -> [SeasonItem] {
        let data = try await loadPublic(
            SpaceRequest.bangumi(mid: mid, page: page),
            referer: "https://space.bilibili.com/\(mid)/bangumi",
            origin: "https://space.bilibili.com"
        )
        return (data["data"]["list"].array ?? []).compactMap(Self.season(fromFollow:))
    }

    func spaceSeries(mid: Int, page: Int) async throws -> [SpaceSeries] {
        let data = try await loadPublic(
            SpaceRequest.series(mid: mid, page: page),
            referer: "https://space.bilibili.com/\(mid)",
            origin: "https://space.bilibili.com"
        )
        let lists = data["data"]["items_lists"]
        var rows: [SpaceSeries] = []
        for item in lists["seasons_list"].array ?? [] {
            if let row = Self.series(from: item, kind: "合集", idKey: "season_id") { rows.append(row) }
        }
        for item in lists["series_list"].array ?? [] {
            if let row = Self.series(from: item, kind: "系列", idKey: "series_id") { rows.append(row) }
        }
        return rows
    }

    private func loadPublic(_ form: SignedForm, referer: String, origin: String? = nil) async throws -> JSON {
        guard let url = form.endpoint else { throw BiliError.message("地址无效") }
        let data = try await withGuest {
            let data = try await getJSON(url, referer: referer, origin: origin)
            let code = data["code"].int ?? -1
            if code == -352 || code == 412 { throw BiliError.risk(code) }
            return data
        }
        try Self.requireOK(data)
        return data
    }

    static func dynamics(from videos: [VideoItem]) -> [DynamicItem] {
        videos.enumerated().map { index, video in
            DynamicItem(
                id: video.bvid,
                name: video.ownerName,
                face: video.ownerFace,
                text: video.desc.isEmpty ? video.title : video.desc,
                time: index == 0 ? "刚刚" : "\(index)小时前",
                kind: "投稿",
                video: video,
                like: video.like,
                comment: video.reply,
                repost: video.share,
                mid: video.ownerMid
            )
        }
    }

    func nav(cookieHeader: String? = nil) async throws -> NavSnapshot {
        let data = try await getJSON(
            "https://api.bilibili.com/x/web-interface/nav",
            includeSession: cookieHeader == nil,
            cookieOverride: cookieHeader
        )
        let payload = data["data"]
        if let mixin = mixinKey(from: payload) {
            WBICache.save(mixin)
        }
        let code = data["code"].int ?? -1
        let loggedIn = payload["isLogin"].bool == true && code == 0
        if !loggedIn && code != 0 && code != -101 {
            throw BiliError.message(data["message"].string ?? "无法读取账号")
        }
        let level = payload["level_info"]
        return NavSnapshot(
            isLogin: loggedIn,
            mid: payload["mid"].int ?? 0,
            name: payload["uname"].string ?? "",
            face: Self.https(payload["face"].string ?? ""),
            level: level["current_level"].int ?? 0,
            exp: level["current_exp"].int ?? 0,
            nextExp: level["next_exp"].int ?? 0,
            coins: payload["money"].int ?? 0,
            mixinKey: mixinKey(from: payload) ?? ""
        )
    }

    func navStat() async throws -> (following: Int, followers: Int, dynamicCount: Int) {
        let data = try await getJSON("https://api.bilibili.com/x/web-interface/nav/stat")
        guard data["code"].int == 0 else {
            throw BiliError.message(data["message"].string ?? "无法读取账号数据")
        }
        let payload = data["data"]
        return (
            payload["following"].int ?? 0,
            payload["follower"].int ?? 0,
            payload["dynamic_count"].int ?? 0
        )
    }

    /// TV/HD QR used by upstream `LoginHttp.getHDcode`. Does not send the current session cookie.
    func requestQRCode() async throws -> (url: String, authCode: String) {
        let signed = AppSign.sign([
            "local_id": "0",
            "platform": "android",
            "mobi_app": "android_hd"
        ])
        let data = try await postQuery(
            "https://passport.bilibili.com/x/passport-tv-login/qrcode/auth_code",
            fields: signed,
            includeSession: false
        )
        guard data["code"].int == 0 else {
            throw BiliError.message(data["message"].string ?? "无法获取二维码")
        }
        let url = data["data"]["url"].string ?? ""
        let authCode = data["data"]["auth_code"].string ?? ""
        guard !url.isEmpty, !authCode.isEmpty else { throw BiliError.message("二维码数据为空") }
        return (url, authCode)
    }

    func pollQR(authCode: String) async throws -> QRPoll {
        let signed = AppSign.sign([
            "auth_code": authCode,
            "local_id": "0"
        ])
        let data = try await postQuery(
            "https://passport.bilibili.com/x/passport-tv-login/qrcode/poll",
            fields: signed,
            includeSession: false
        )
        let code = data["code"].int ?? -1
        let message = data["message"].string ?? ""
        if code == 86038 { return .expired(message.isEmpty ? "二维码已过期" : message) }
        if code != 0 { return .pending(message.isEmpty ? "等待扫码" : message) }
        let payload = data["data"]
        let cookies = cookies(from: payload["cookie_info"]["cookies"])
        guard cookies["SESSDATA"] != nil else { throw BiliError.message("扫码结果没有 SESSDATA") }
        let session = BiliSession.make(
            cookies: cookies,
            accessToken: payload["access_token"].string ?? payload["token_info"]["access_token"].string,
            refreshToken: payload["refresh_token"].string ?? payload["token_info"]["refresh_token"].string,
            mid: payload["mid"].int ?? Int(cookies["DedeUserID"] ?? "") ?? 0
        )
        return .confirmed(session)
    }

    func logout(csrf: String, cookieHeader: String) async {
        guard !csrf.isEmpty else { return }
        guard let url = URL(string: "https://passport.bilibili.com/login/exit/v2") else { return }
        _ = try? await postForm(
            url,
            fields: ["biliCSRF": csrf],
            cookieOverride: cookieHeader,
            includeCSRF: false
        )
    }

    /// Sorted, WBI-signed query. Mixin key comes from today's `nav` response.
    func wbiSign(_ params: [String: String]) async throws -> [String: String] {
        let mixin = try await mixinKey()
        guard !mixin.isEmpty else { throw BiliError.message("缺少 WBI 签名密钥") }
        return WBISigner.sign(params, mixinKey: mixin)
    }

    func refreshMixinKey() async {
        _ = try? await mixinKey()
    }

    private func mixinKey() async throws -> String {
        if let cached = WBICache.load() { return cached }
        _ = try await nav()
        return WBICache.load() ?? ""
    }

    private func mixinKey(from payload: JSON) -> String? {
        let img = payload["wbi_img"]["img_url"].string ?? ""
        let sub = payload["wbi_img"]["sub_url"].string ?? ""
        guard !img.isEmpty, !sub.isEmpty else { return nil }
        let key = WBISigner.mixinKey(imgURL: img, subURL: sub)
        return key.isEmpty ? nil : key
    }

    private func cookies(from list: JSON) -> [String: String] {
        var cookies: [String: String] = [:]
        for item in list.array ?? [] {
            guard let name = item["name"].string, let value = item["value"].string, !name.isEmpty else { continue }
            cookies[name] = value
        }
        return cookies
    }

    private func getJSON(_ string: String, includeSession: Bool = true, cookieOverride: String? = nil) async throws -> JSON {
        guard let url = URL(string: string) else { throw BiliError.message("地址无效") }
        return try await getJSON(url, includeSession: includeSession, cookieOverride: cookieOverride)
    }

    private func getJSON(
        _ url: URL,
        includeSession: Bool = true,
        cookieOverride: String? = nil,
        referer: String? = nil,
        origin: String? = nil,
        userAgent: String? = nil,
        suppressCookie: Bool = false
    ) async throws -> JSON {
        try await send(
            url,
            method: "GET",
            body: nil,
            includeSession: includeSession,
            cookieOverride: cookieOverride,
            referer: referer,
            origin: origin,
            userAgent: userAgent,
            suppressCookie: suppressCookie
        )
    }

    private func getData(_ url: URL, includeSession: Bool) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyCommonHeaders(&request, includeSession: includeSession, cookieOverride: nil)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BiliError.status(http.statusCode)
        }
        return data
    }

    private func postQuery(_ string: String, fields: [String: String], includeSession: Bool) async throws -> JSON {
        let query = fields.keys.sorted().map { key in
            "\(PercentEncoding.encodeURIComponent(key))=\(PercentEncoding.encodeURIComponent(fields[key, default: ""]))"
        }.joined(separator: "&")
        guard let url = URL(string: string + "?" + query) else { throw BiliError.message("地址无效") }
        return try await send(url, method: "POST", body: nil, includeSession: includeSession, cookieOverride: nil)
    }

    /// Form POST. Adds `csrf` from the current session unless a cookie override is used.
    func postForm(
        _ url: URL,
        fields: [String: String],
        cookieOverride: String? = nil,
        includeCSRF: Bool = true,
        referer: String? = nil,
        origin: String? = nil,
        userAgent: String? = nil
    ) async throws -> JSON {
        var fields = fields
        if includeCSRF, fields["csrf"] == nil, let csrf = SessionVault.shared.current()?.csrf, !csrf.isEmpty {
            fields["csrf"] = csrf
        }
        let body = fields.keys.sorted().map { key in
            "\(PercentEncoding.encodeURIComponent(key))=\(PercentEncoding.encodeURIComponent(fields[key, default: ""]))"
        }.joined(separator: "&")
        return try await send(
            url,
            method: "POST",
            body: Data(body.utf8),
            contentType: "application/x-www-form-urlencoded",
            includeSession: cookieOverride == nil,
            cookieOverride: cookieOverride,
            referer: referer,
            origin: origin,
            userAgent: userAgent
        )
    }

    private func send(
        _ url: URL,
        method: String,
        body: Data?,
        contentType: String? = nil,
        includeSession: Bool,
        cookieOverride: String?,
        referer: String? = nil,
        origin: String? = nil,
        userAgent: String? = nil,
        suppressCookie: Bool = false
    ) async throws -> JSON {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if let referer {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        if let origin {
            request.setValue(origin, forHTTPHeaderField: "Origin")
        }
        if let userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        applyCommonHeaders(&request, includeSession: includeSession, cookieOverride: cookieOverride, suppressCookie: suppressCookie)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BiliError.status(http.statusCode)
        }
        let object = try JSONSerialization.jsonObject(with: data)
        return JSON(object)
    }

    private func applyCommonHeaders(_ request: inout URLRequest, includeSession: Bool, cookieOverride: String?, suppressCookie: Bool = false) {
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(BiliHTTP.userAgent, forHTTPHeaderField: "User-Agent")
        }
        if request.value(forHTTPHeaderField: "Origin") == nil {
            request.setValue(BiliHTTP.origin, forHTTPHeaderField: "Origin")
        }
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        if request.value(forHTTPHeaderField: "Referer") == nil {
            request.setValue(BiliHTTP.origin, forHTTPHeaderField: "Referer")
        }
        let cookie = suppressCookie ? "" : BiliHTTP.mergedCookie(includeSession: includeSession, override: cookieOverride)
        if !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
    }

    static func https(_ raw: String) -> String {
        var value = raw.replacingOccurrences(of: "http://", with: "https://")
        if value.hasPrefix("//") { value = "https:" + value }
        return value
    }

    static func video(fromRecommend item: JSON) -> VideoItem? {
        guard item["goto"].string == "av" || item["bvid"].string?.isEmpty == false else { return nil }
        return video(fromPopular: item)
    }

    static func season(from item: JSON) -> SeasonItem? {
        let id = item["season_id"].int ?? 0
        let title = item["title"].string ?? ""
        guard id > 0, !title.isEmpty else { return nil }
        return SeasonItem(
            seasonID: id,
            title: unescape(title),
            cover: https(item["cover"].string ?? ""),
            badge: item["badge"].string ?? "",
            subtitle: item["new_ep"]["index_show"].string ?? item["pub_index"].string ?? "",
            view: item["stat"]["view"].int ?? item["stat"]["follow"].int ?? 0
        )
    }

    static func video(fromPopular item: JSON) -> VideoItem? {
        guard let bvid = item["bvid"].string else { return nil }
        return VideoItem(
            bvid: bvid,
            aid: item["aid"].int ?? 0,
            cid: item["cid"].int ?? 0,
            title: unescape(item["title"].string ?? ""),
            cover: https(item["pic"].string ?? ""),
            duration: item["duration"].int ?? 0,
            ownerName: item["owner"]["name"].string ?? "",
            ownerMid: item["owner"]["mid"].int ?? 0,
            ownerFace: https(item["owner"]["face"].string ?? ""),
            desc: item["desc"].string ?? "",
            pubdate: item["pubdate"].int ?? 0,
            view: item["stat"]["view"].int ?? 0,
            danmaku: item["stat"]["danmaku"].int ?? 0,
            like: item["stat"]["like"].int ?? 0,
            coin: item["stat"]["coin"].int ?? 0,
            favorite: item["stat"]["favorite"].int ?? 0,
            share: item["stat"]["share"].int ?? 0,
            reply: item["stat"]["reply"].int ?? 0,
            pages: [],
            tname: item["tname"].string ?? ""
        )
    }

    static func video(fromView item: JSON) -> VideoItem? {
        guard var video = video(fromPopular: item) else { return nil }
        let pages = (item["pages"].array ?? []).map { page in
            VideoPage(
                cid: page["cid"].int ?? 0,
                index: page["page"].int ?? 1,
                title: page["part"].string ?? "P\(page["page"].int ?? 1)",
                duration: page["duration"].int ?? 0
            )
        }
        video.pages = pages
        if video.cid == 0 { video.cid = pages.first?.cid ?? 0 }
        video.desc = item["desc"].string ?? video.desc
        let history = item["history"]
        let historyCID = history["cid"].int ?? 0
        let historyProgress = history["progress"].int ?? 0
        if historyProgress != 0, historyCID == 0 || historyCID == video.cid || historyCID == video.pages.first?.cid {
            video.progress = historyProgress
        }
        let season = item["ugc_season"]
        let seasonTitle = season["title"].string ?? ""
        if !seasonTitle.isEmpty {
            var clips: [CollectionClip] = []
            for section in season["sections"].array ?? [] {
                for episode in section["episodes"].array ?? [] {
                    let bvid = episode["bvid"].string ?? ""
                    let title = episode["title"].string ?? episode["page"]["part"].string ?? ""
                    guard !bvid.isEmpty, !title.isEmpty else { continue }
                    clips.append(CollectionClip(bvid: bvid, title: title, index: clips.count + 1))
                }
            }
            video.collectionTitle = seasonTitle
            video.collectionClips = clips
            video.collectionCount = season["ep_count"].int ?? clips.count
            video.collectionIndex = clips.first { $0.bvid == video.bvid }?.index ?? 0
        }
        return video
    }

    func ownerBrief(mid: Int) async -> (fans: Int, videos: Int, followed: Bool) {
        guard mid > 0, let url = URL(string: "https://api.bilibili.com/x/web-interface/card?mid=\(mid)") else {
            return (0, 0, false)
        }
        guard let data = try? await getJSON(url, referer: "https://space.bilibili.com/\(mid)"), data["code"].int == 0 else {
            return (0, 0, false)
        }
        let fans = data["data"]["card"]["fans"].int ?? data["data"]["follower"].int ?? 0
        let videos = data["data"]["archive_count"].int ?? 0
        return (fans, videos, data["data"]["following"].bool ?? false)
    }

    static func video(fromRelated item: JSON) -> VideoItem? {
        video(fromPopular: item)
    }

    static func video(fromSpace item: JSON) -> VideoItem? {
        let bvid = item["bvid"].string ?? ""
        let title = unescape(item["title"].string ?? "")
        guard !bvid.isEmpty, !title.isEmpty else { return nil }
        return VideoItem(
            bvid: bvid,
            aid: item["aid"].int ?? 0,
            cid: 0,
            title: title,
            cover: https(item["pic"].string ?? ""),
            duration: parseClock(item["length"].string ?? ""),
            ownerName: item["author"].string ?? "",
            ownerMid: item["mid"].int ?? 0,
            ownerFace: "",
            desc: unescape(item["description"].string ?? ""),
            pubdate: item["created"].int ?? 0,
            view: flexibleCount(item["play"]),
            danmaku: flexibleCount(item["video_review"]),
            like: 0,
            coin: 0,
            favorite: 0,
            share: 0,
            reply: item["comment"].int ?? 0,
            pages: [],
            tname: ""
        )
    }

    static func season(fromFollow item: JSON) -> SeasonItem? {
        let id = item["season_id"].int ?? 0
        let title = plain(item["title"].string ?? "")
        guard id > 0, !title.isEmpty else { return nil }
        let episode = item["new_ep"]
        return SeasonItem(
            seasonID: id,
            title: title,
            cover: https(item["cover"].string ?? ""),
            badge: item["season_type_name"].string ?? "",
            subtitle: plain(episode["index_show"].string ?? episode["display"].string ?? ""),
            view: item["stat"]["follow"].int ?? 0
        )
    }

    static func series(from item: JSON, kind: String, idKey: String) -> SpaceSeries? {
        let meta = item["meta"]
        let id = meta[idKey].int ?? item[idKey].int ?? 0
        let title = meta["name"].string ?? item["name"].string ?? ""
        guard id > 0, !title.isEmpty else { return nil }
        return SpaceSeries(
            id: "\(kind)-\(id)",
            title: unescape(title),
            cover: https(meta["cover"].string ?? item["cover"].string ?? ""),
            count: meta["total"].int ?? item["total"].int ?? 0,
            kind: kind
        )
    }

    static func video(fromSearch item: JSON) -> VideoItem? {
        let bvid = item["bvid"].string ?? ""
        guard !bvid.isEmpty else { return nil }
        let durationText = item["duration"].string ?? "0:0"
        return VideoItem(
            bvid: bvid,
            aid: item["aid"].int ?? Int(item["aid"].string ?? "") ?? 0,
            cid: 0,
            title: unescape(item["title"].string ?? "").replacingOccurrences(of: "<em class=\"keyword\">", with: "").replacingOccurrences(of: "</em>", with: ""),
            cover: https(item["pic"].string ?? ""),
            duration: parseClock(durationText),
            ownerName: item["author"].string ?? "",
            ownerMid: item["mid"].int ?? 0,
            ownerFace: "",
            desc: unescape(item["description"].string ?? ""),
            pubdate: item["pubdate"].int ?? 0,
            view: item["play"].int ?? 0,
            danmaku: item["danmaku"].int ?? 0,
            like: item["like"].int ?? 0,
            coin: 0,
            favorite: item["favorites"].int ?? 0,
            share: 0,
            reply: item["review"].int ?? 0,
            pages: [],
            tname: item["typename"].string ?? ""
        )
    }

    static func comment(_ item: JSON) -> CommentItem? {
        let id = item["rpid"].int ?? 0
        guard id != 0 else { return nil }
        let replies = (item["replies"].array ?? []).compactMap(comment)
        let member = item["member"]
        let fans = member["fans_detail"]
        return CommentItem(
            id: id,
            name: member["uname"].string ?? "用户",
            face: https(member["avatar"].string ?? ""),
            message: item["content"]["message"].string ?? "",
            like: item["like"].int ?? 0,
            ctime: item["ctime"].int ?? 0,
            replies: replies,
            replyCount: item["rcount"].int ?? replies.count,
            root: item["root"].int ?? 0,
            mid: member["mid"].int ?? 0,
            medalName: fans["medal_name"].string ?? "",
            medalLevel: fans["level"].int ?? 0
        )
    }

    static func user(fromSearch item: JSON) -> SearchUser? {
        let mid = item["mid"].int ?? 0
        let name = plain(item["uname"].string ?? item["name"].string ?? "")
        guard mid > 0, !name.isEmpty else { return nil }
        return SearchUser(
            mid: mid,
            name: name,
            face: https(item["upic"].string ?? item["face"].string ?? ""),
            fans: flexibleCount(item["fans"]),
            sign: plain(item["usign"].string ?? item["sign"].string ?? "")
        )
    }

    static func bangumi(fromSearch item: JSON) -> SeasonItem? {
        let id = item["season_id"].int ?? item["media_id"].int ?? 0
        let title = plain(item["title"].string ?? item["org_title"].string ?? "")
        guard id > 0, !title.isEmpty else { return nil }
        return SeasonItem(
            seasonID: id,
            title: title,
            cover: https(item["cover"].string ?? ""),
            badge: item["season_type_name"].string ?? "",
            subtitle: plain(item["index_show"].string ?? item["styles"].string ?? ""),
            view: item["media_score"]["user_count"].int ?? 0
        )
    }

    static func liveRooms(in data: JSON) -> [LiveRoom] {
        var rows = data["data"]["list"].array ?? []
        if rows.isEmpty { rows = data["data"]["recommend_room_list"].array ?? [] }
        if rows.isEmpty { rows = data["data"]["room_list"].array ?? [] }
        if rows.isEmpty { rows = data["data"].array ?? [] }
        rows.append(contentsOf: data["data"]["card_list"].array ?? [])
        var rooms: [LiveRoom] = []
        for item in rows {
            if let room = liveRoom(from: item) { rooms.append(room) }
            if let nested = liveRoom(from: item["card_data"]["small_card_v1"]) { rooms.append(nested) }
            for child in item["list"].array ?? [] {
                if let room = liveRoom(from: child) { rooms.append(room) }
            }
            for child in item["card_data"]["my_idol_v1"]["list"].array ?? [] {
                if let room = liveRoom(from: child) { rooms.append(room) }
            }
        }
        var seen = Set<Int>()
        return rooms.filter { seen.insert($0.id).inserted }
    }

    static func liveRoom(from item: JSON) -> LiveRoom? {
        var id = item["roomid"].int ?? item["room_id"].int ?? 0
        if id == 0 {
            let uname = item["uname"].string ?? ""
            let cover = item["cover"].string ?? item["user_cover"].string ?? item["system_cover"].string ?? ""
            if !uname.isEmpty || !cover.isEmpty { id = item["id"].int ?? 0 }
        }
        guard id > 0 else { return nil }
        let title = unescape(item["title"].string ?? item["uname"].string ?? "")
        guard !title.isEmpty else { return nil }
        return LiveRoom(
            id: id,
            title: title,
            cover: https(item["cover"].string ?? item["user_cover"].string ?? item["system_cover"].string ?? item["keyframe"].string ?? ""),
            uname: item["uname"].string ?? "",
            face: https(item["face"].string ?? ""),
            online: item["online"].int ?? item["watched_show"]["num"].int ?? 0,
            area: item["area_v2_name"].string ?? item["area_name"].string ?? "直播",
            mid: item["uid"].int ?? item["mid"].int ?? 0
        )
    }

    static func liveOffer(from data: JSON, requestedQN: Int) -> LiveOffer? {
        let streams = data["data"]["playurl_info"]["playurl"]["stream"].array ?? []
        struct Candidate {
            var score: Int
            var url: String
            var proto: String
            var qn: Int
            var names: [String]
            var ids: [Int]
        }
        var found: [Candidate] = []
        for stream in streams {
            let proto = stream["protocol_name"].string ?? ""
            for format in stream["format"].array ?? [] {
                let formatName = format["format_name"].string ?? ""
                for codec in format["codec"].array ?? [] {
                    let codecName = codec["codec_name"].string ?? ""
                    let qn = codec["current_qn"].int ?? requestedQN
                    let accept = (codec["accept_qn"].array ?? []).compactMap(\.int)
                    let ids = accept.isEmpty ? [qn] : accept
                    let base = codec["base_url"].string ?? ""
                    let infos = codec["url_info"].array ?? []
                    for (index, info) in infos.enumerated() {
                        var host = info["host"].string ?? ""
                        let extra = info["extra"].string ?? ""
                        if host.hasPrefix("//") { host = "https:" + host }
                        guard !host.isEmpty, !base.isEmpty else { continue }
                        var score = 0
                        if proto == "http_hls" { score += 80 }
                        if formatName == "ts" { score += 30 }
                        if formatName == "fmp4" { score += 8 }
                        if codecName == "avc" || codecName == "avc1" { score += 24 }
                        if qn == requestedQN { score += 3 }
                        score -= index
                        var url = host + base + extra
                        if url.hasPrefix("http://") { url = "https://" + url.dropFirst("http://".count) }
                        found.append(Candidate(
                            score: score,
                            url: url,
                            proto: proto == "http_hls" ? "hls" : "flv",
                            qn: qn,
                            names: ids.map(LiveRequest.qualityName),
                            ids: ids
                        ))
                    }
                }
            }
        }
        found.sort { $0.score > $1.score }
        guard let best = found.first else { return nil }
        let selected = LiveRequest.qualityName(best.qn)
        var names: [String] = []
        var kept: [Int] = []
        for id in best.ids {
            let name = LiveRequest.qualityName(id)
            if names.contains(name) { continue }
            names.append(name)
            kept.append(id)
        }
        if !names.contains(selected) {
            names.insert(selected, at: 0)
            kept.insert(best.qn, at: 0)
        }
        var alternates: [String] = []
        for item in found.dropFirst() where item.proto == "hls" && item.url != best.url && !alternates.contains(item.url) {
            alternates.append(item.url)
            if alternates.count == 4 { break }
        }
        let host = URL(string: best.url)?.host ?? ""
        print("live offer \(best.proto) \(formatName(best.url)) qn \(best.qn) \(host)")
        return LiveOffer(
            url: best.url,
            alternates: alternates,
            protocolName: best.proto,
            qualities: names,
            qualityIDs: kept,
            selectedQN: best.qn,
            selectedName: selected
        )
    }

    private static func formatName(_ url: String) -> String {
        if url.contains(".m3u8") { return "m3u8" }
        if url.contains(".flv") { return "flv" }
        return "stream"
    }

    static func live(fromSearch item: JSON) -> LiveRoom? {
        let id = item["roomid"].int ?? item["room_id"].int ?? item["roomId"].int ?? 0
        let title = plain(item["title"].string ?? "")
        guard id > 0, !title.isEmpty else { return nil }
        return LiveRoom(
            id: id,
            title: title,
            cover: https(item["cover"].string ?? item["user_cover"].string ?? ""),
            uname: plain(item["uname"].string ?? item["author"].string ?? ""),
            face: https(item["uface"].string ?? ""),
            online: flexibleCount(item["online"]),
            area: item["cate_name"].string ?? item["area_v2_name"].string ?? "直播",
            mid: item["uid"].int ?? item["mid"].int ?? 0
        )
    }

    static func article(fromSearch item: JSON) -> SearchArticle? {
        let id = item["id"].int ?? item["cvid"].int ?? 0
        let title = plain(item["title"].string ?? "")
        guard id > 0, !title.isEmpty else { return nil }
        let images = item["image_urls"].array ?? []
        let firstImage = images.first ?? JSON(NSNull())
        let cover = firstImage["img_src"].string ?? firstImage.string ?? item["cover"].string ?? ""
        return SearchArticle(
            id: id,
            title: title,
            summary: plain(item["desc"].string ?? ""),
            cover: https(cover),
            author: plain(item["author"].string ?? item["mid"].string ?? ""),
            view: flexibleCount(item["view"])
        )
    }

    static func dynamic(fromPolymer item: JSON) -> DynamicItem? {
        let id = item["id_str"].string ?? ""
        guard !id.isEmpty else { return nil }
        let modules = item["modules"]
        let author = modules["module_author"]
        let desc = modules["module_dynamic"]["desc"]["text"].string ?? ""
        let stat = modules["module_stat"]
        let archive = archiveJSON(in: item)
        var clip = Self.video(fromArchive: archive)
        if clip == nil { clip = Self.video(fromArchive: archiveJSON(in: item["orig"])) }
        let type = item["type"].string ?? ""
        let kind: String
        switch type {
        case "DYNAMIC_TYPE_AV": kind = "投稿"
        case "DYNAMIC_TYPE_PGC", "DYNAMIC_TYPE_PGC_UNION": kind = "番剧"
        case "DYNAMIC_TYPE_ARTICLE": kind = "专栏"
        case "DYNAMIC_TYPE_FORWARD": kind = "转发"
        default: kind = "动态"
        }
        let opus = modules["module_dynamic"]["major"]["opus"]
        let rich = (modules["module_dynamic"]["desc"]["rich_text_nodes"].array ?? [])
            .compactMap { Self.filled($0["orig_text"].string ?? $0["text"].string) }
            .joined()
        let text = unescape(
            Self.filled(desc)
                ?? Self.filled(rich)
                ?? Self.filled(opus["summary"]["text"].string)
                ?? Self.filled(opus["title"].string)
                ?? Self.filled(clip?.title)
                ?? Self.filled(author["pub_action"].string)
                ?? kind
        )
        var built = DynamicItem(
            id: id,
            name: author["name"].string ?? "用户",
            face: https(author["face"].string ?? ""),
            text: text,
            time: author["pub_time"].string ?? "",
            kind: kind,
            video: clip,
            like: stat["like"]["count"].int ?? 0,
            comment: stat["comment"]["count"].int ?? 0,
            repost: stat["forward"]["count"].int ?? 0,
            mid: author["mid"].int ?? 0
        )
        let body = modules["module_dynamic"]
        built.images = dynamicImages(in: body)
        let poll = dynamicPoll(in: body)
        built.pollTitle = poll.title
        built.pollOptions = poll.options
        built.pollCounts = poll.counts
        built.pollJoined = poll.joined
        built.topicName = body["topic"]["name"].string ?? ""
        built.topicID = body["topic"]["id"].int ?? 0
        built.pollVoteID = body["additional"]["vote"]["vote_id"].int ?? 0
        built.liked = stat["like"]["status"].bool ?? false
        built.commentID = Self.longID(item["basic"]["comment_id_str"])
        built.commentType = item["basic"]["comment_type"].int ?? 0
        if item["orig"]["id_str"].string != nil, let orig = dynamic(fromPolymer: item["orig"]) {
            built.origText = orig.text
        }
        return built
    }

    private static func longID(_ json: JSON) -> Int {
        if let text = json.string, let value = Int(text) { return value }
        return json.int ?? 0
    }

    private static func filled(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    private static func dynamicImages(in dynamic: JSON) -> [String] {
        let major = dynamic["major"]
        let draw = major["draw"]["items"].array ?? []
        let opus = major["opus"]["pics"].array ?? []
        let raw = draw + opus
        var seen = Set<String>()
        var images: [String] = []
        for item in raw {
            let src = https(item["src"].string ?? item["url"].string ?? "")
            guard !src.isEmpty, seen.insert(src).inserted else { continue }
            images.append(src)
        }
        return images
    }

    private static func dynamicPoll(in dynamic: JSON) -> (title: String, options: [String], counts: [Int], joined: Int) {
        let vote = dynamic["additional"]["vote"]
        let title = vote["desc"].string ?? vote["title"].string ?? ""
        let choices = vote["options"].array ?? vote["choice"].array ?? []
        var options: [String] = []
        var counts: [Int] = []
        for choice in choices {
            let name = choice["desc"].string ?? choice["opt_desc"].string ?? choice["title"].string ?? ""
            guard !name.isEmpty else { continue }
            options.append(name)
            counts.append(choice["cnt"].int ?? choice["count"].int ?? 0)
        }
        let joined = vote["join_num"].int ?? vote["cnt"].int ?? counts.reduce(0, +)
        guard !options.isEmpty else { return ("", [], [], 0) }
        return (title.isEmpty ? "投票" : title, options, counts, joined)
    }

    static func dynamic(fromLegacy item: JSON) -> DynamicItem? {
        let desc = item["desc"]
        let id = desc["dynamic_id_str"].string ?? String(desc["dynamic_id"].int ?? 0)
        guard !id.isEmpty, id != "0" else { return nil }
        let cardText = item["card"].string ?? ""
        let card: JSON
        if let data = cardText.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) {
            card = JSON(object)
        } else {
            card = JSON(NSNull())
        }
        let profile = desc["user_profile"]["info"]
        let text = unescape(
            card["dynamic"].string
                ?? card["desc"].string
                ?? card["title"].string
                ?? card["item"]["description"].string
                ?? card["item"]["content"].string
                ?? ""
        )
        guard !text.isEmpty else { return nil }
        let stamp = desc["timestamp"].int ?? 0
        let bvid = card["bvid"].string ?? desc["bvid"].string ?? ""
        let videoTitle = unescape(card["title"].string ?? "")
        let clip: VideoItem? = bvid.isEmpty || videoTitle.isEmpty ? nil : VideoItem(
            bvid: bvid,
            aid: card["aid"].int ?? desc["rid"].int ?? 0,
            cid: 0,
            title: videoTitle,
            cover: https(card["pic"].string ?? ""),
            duration: card["duration"].int ?? 0,
            ownerName: profile["uname"].string ?? "",
            ownerMid: profile["uid"].int ?? desc["uid"].int ?? 0,
            ownerFace: https(profile["face"].string ?? ""),
            desc: "",
            pubdate: stamp,
            view: card["stat"]["view"].int ?? 0,
            danmaku: card["stat"]["danmaku"].int ?? 0,
            like: 0,
            coin: 0,
            favorite: 0,
            share: 0,
            reply: 0,
            pages: [],
            tname: ""
        )
        return DynamicItem(
            id: id,
            name: profile["uname"].string ?? "用户",
            face: https(profile["face"].string ?? ""),
            text: text,
            time: stamp > 0 ? Self.shortStamp(stamp) : "",
            kind: clip == nil ? "动态" : "投稿",
            video: clip,
            like: desc["like"].int ?? 0,
            comment: item["desc"]["comment"].int ?? 0,
            repost: desc["repost"].int ?? 0,
            mid: profile["uid"].int ?? desc["uid"].int ?? 0
        )
    }

    private static func shortStamp(_ stamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(stamp))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M-d HH:mm"
        return formatter.string(from: date)
    }

    private static func archiveJSON(in item: JSON) -> JSON {
        let major = item["modules"]["module_dynamic"]["major"]
        if major["archive"]["bvid"].string?.isEmpty == false { return major["archive"] }
        return major["archive"]
    }

    private static func video(fromArchive item: JSON) -> VideoItem? {
        let bvid = item["bvid"].string ?? ""
        let title = plain(item["title"].string ?? "")
        guard !bvid.isEmpty, !title.isEmpty else { return nil }
        return VideoItem(
            bvid: bvid,
            aid: item["aid"].int ?? 0,
            cid: 0,
            title: title,
            cover: https(item["cover"].string ?? ""),
            duration: parseClock(item["duration_text"].string ?? ""),
            ownerName: item["author"]["name"].string ?? "",
            ownerMid: item["author"]["mid"].int ?? 0,
            ownerFace: https(item["author"]["face"].string ?? ""),
            desc: "",
            pubdate: 0,
            view: flexibleCount(item["stat"]["play"]),
            danmaku: flexibleCount(item["stat"]["danmaku"]),
            like: 0,
            coin: 0,
            favorite: 0,
            share: 0,
            reply: 0,
            pages: [],
            tname: ""
        )
    }

    /// Type search returns either a row array or a dictionary of named arrays.
    static func searchRows(_ payload: JSON) -> [JSON] {
        if let list = payload.array { return list }
        let keys = ["live_room", "live_user", "media_bangumi", "media_ft", "article", "video", "user", "bili_user"]
        for key in keys {
            if let list = payload[key].array, !list.isEmpty { return list }
        }
        guard let dict = payload.raw as? [String: Any] else { return [] }
        for value in dict.values {
            if let list = value as? [Any], !list.isEmpty { return list.map(JSON.init) }
        }
        return []
    }

    static func flexibleCount(_ json: JSON) -> Int {
        if let value = json.int { return value }
        guard var text = json.string else { return 0 }
        text = text.replacingOccurrences(of: ",", with: "")
        if text.hasSuffix("亿") {
            let number = Double(text.dropLast()) ?? 0
            return Int((number * 100_000_000).rounded())
        }
        if text.hasSuffix("万") {
            let number = Double(text.dropLast()) ?? 0
            return Int((number * 10_000).rounded())
        }
        return Int(Double(text) ?? 0)
    }

    static func plain(_ text: String) -> String {
        var value = unescape(text)
        while let start = value.range(of: "<em"), let end = value.range(of: ">", range: start.upperBound..<value.endIndex) {
            value.removeSubrange(start.lowerBound..<end.upperBound)
        }
        return value.replacingOccurrences(of: "</em>", with: "")
    }

    static func unescape(_ text: String) -> String {
        var value = text
        let pairs = [("amp", "&"), ("lt", "<"), ("gt", ">"), ("quot", "\""), ("#39", "'")]
        for (name, replacement) in pairs {
            value = value.replacingOccurrences(of: "&\(name);", with: replacement)
        }
        return value
    }

    static func parseClock(_ text: String) -> Int {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        if parts.count == 3 { return parts[0] * 3600 + parts[1] * 60 + parts[2] }
        if parts.count == 2 { return parts[0] * 60 + parts[1] }
        return parts.first ?? 0
    }

    func messageUnread() async throws -> MessageUnread {
        let data = try await messageJSON(MessageRequest.unread())
        try Self.requireMessageOK(data)
        return MessageParser.unread(data)
    }

    func messageNotices(kind: String, cursor: Int, time: Int) async throws -> NoticePage {
        let call: MessageCall
        switch kind {
        case "@我": call = MessageRequest.at(cursor: cursor, time: time)
        case "收到的赞": call = MessageRequest.like(cursor: cursor, time: time)
        case "系统通知": call = MessageRequest.system(cursor: cursor)
        default: call = MessageRequest.reply(cursor: cursor, time: time)
        }
        let data = try await messageJSON(call)
        try Self.requireMessageOK(data)
        let page = MessageParser.notices(kind: kind, data: data)
        return NoticePage(items: page.items, cursor: page.cursor, cursorTime: page.cursorTime, ended: page.ended)
    }

    func chatSessions(endTs: Int) async throws -> SessionPage {
        let data = try await messageJSON(MessageRequest.sessions(endTs: endTs))
        try Self.requireMessageOK(data)
        var page = MessageParser.sessions(data)
        let ids = page.items.map(\.id)
        if !ids.isEmpty, let names = try? await messageCards(ids) {
            page.items = page.items.map { item in
                guard let card = names[item.id] else { return item }
                var copy = item
                copy.name = card.name
                copy.face = card.face
                return copy
            }
        }
        return SessionPage(items: page.items, hasMore: page.hasMore)
    }

    func chatLines(talker: Int, endSeqno: Int) async throws -> ChatPage {
        let mine = SessionVault.shared.current()?.mid ?? 0
        let data = try await messageJSON(MessageRequest.messages(talker: talker, endSeqno: endSeqno))
        try Self.requireMessageOK(data)
        let page = MessageParser.lines(data, mine: mine)
        return ChatPage(items: page.items, hasMore: page.hasMore, maxSeqno: page.items.map(\.id).max() ?? 0)
    }

    func ackChat(talker: Int, seqno: Int) async throws {
        guard let csrf = SessionVault.shared.current()?.csrf, !csrf.isEmpty, talker > 0, seqno > 0 else {
            throw BiliError.message("请先登录")
        }
        let data = try await messageJSON(MessageRequest.ack(talker: talker, seqno: seqno, csrf: csrf))
        try Self.requireMessageOK(data)
    }

    func sendChat(receiver: Int, text: String) async throws {
        guard let session = SessionVault.shared.current(), session.mid > 0, !session.csrf.isEmpty else {
            throw BiliError.message("请先登录")
        }
        let device = UUID().uuidString.lowercased()
        let stamp = Int(Date().timeIntervalSince1970)
        guard let call = MessageRequest.send(
            sender: session.mid,
            receiver: receiver,
            text: text,
            device: device,
            timestamp: stamp,
            csrf: session.csrf
        ) else {
            throw BiliError.message("消息是空的")
        }
        let signed = try await wbiSign([
            "w_sender_uid": "\(session.mid)",
            "w_receiver_id": "\(receiver)",
            "w_dev_id": device
        ])
        let query = signed.keys.sorted().map { key in
            "\(PercentEncoding.encodeURIComponent(key))=\(PercentEncoding.encodeURIComponent(signed[key, default: ""]))"
        }.joined(separator: "&")
        guard let url = URL(string: "\(call.host)\(call.path)?\(query)") else {
            throw BiliError.message("地址无效")
        }
        let data = try await postForm(
            url,
            fields: call.fields,
            includeCSRF: false,
            referer: call.referer,
            origin: call.origin
        )
        try Self.requireMessageOK(data)
    }

    private func messageCards(_ ids: [Int]) async throws -> [Int: (name: String, face: String)] {
        let data = try await messageJSON(MessageRequest.cards(ids: ids))
        try Self.requireMessageOK(data)
        return MessageParser.cards(data)
    }

    private func messageJSON(_ call: MessageCall) async throws -> JSON {
        if call.signed {
            do {
                let data = try await requestQuery(
                    call.path,
                    params: call.fields,
                    signed: true,
                    referer: call.referer,
                    origin: call.origin,
                    host: call.host
                )
                let code = data["code"].int ?? -1
                if code == 0 || code == -101 { return data }
            } catch {
                // The unsigned query is the fallback when WBI is refused.
            }
        }
        return try await requestQuery(
            call.path,
            params: call.fields,
            signed: false,
            referer: call.referer,
            origin: call.origin,
            host: call.host
        )
    }

    private static func requireMessageOK(_ data: JSON) throws {
        let code = data["code"].int ?? -1
        if code == -101 { throw BiliError.message("登录已失效") }
        guard code == 0 else {
            throw BiliError.message(data["message"].string ?? data["msg"].string ?? "操作没有成功")
        }
    }

    func playerChapters(bvid: String, cid: Int) async -> [ChapterMark] {
        let form = PlaybackRequest.playerInfo(bvid: bvid, cid: cid)
        let referer = BiliHTTP.referer(bvid: bvid)
        if let signed = try? await requestQuery(form.path, params: form.fields, signed: true, referer: referer), signed["code"].int == 0 {
            let marks = PlaybackMarkup.chapters(from: signed)
            if !marks.isEmpty { return marks }
        }
        if let plain = try? await requestQuery("/x/player/v2", params: form.fields, signed: false, referer: referer), plain["code"].int == 0 {
            return PlaybackMarkup.chapters(from: plain)
        }
        return []
    }

    func energyBars(cid: Int) async -> [Double] {
        guard cid > 0 else { return [] }
        let urls = [
            "https://bvc.bilivideo.com/pbp/data?cid=\(cid)",
            "https://api.bilibili.com/pbp/data?cid=\(cid)"
        ]
        for string in urls {
            guard let url = URL(string: string) else { continue }
            do {
                let body = try await getData(url, includeSession: false)
                let preview = String(data: body.prefix(160), encoding: .utf8) ?? "binary \(body.count)"
                let object = (try? JSONSerialization.jsonObject(with: body))
                    ?? RawInflate.expand(body).flatMap { try? JSONSerialization.jsonObject(with: $0) }
                guard let object else {
                    PlaybackLog.line("energy \(url.host ?? "") unparsed \(preview)")
                    continue
                }
                let values = PlaybackMarkup.energy(from: JSON(object))
                PlaybackLog.line("energy \(url.host ?? "") count=\(values.count) \(preview)")
                if values.count >= 4 { return values }
            } catch {
                PlaybackLog.line("energy \(url.host ?? "") \(error.localizedDescription)")
            }
        }
        return []
    }

    func videoShot(bvid: String, cid: Int) async -> VideoShotPage? {
        let form = PlaybackRequest.videoshot(bvid: bvid, cid: cid)
        guard let url = form.endpoint else { return nil }
        guard let data = try? await getJSON(url, referer: BiliHTTP.referer(bvid: bvid)), data["code"].int == 0 else { return nil }
        return PlaybackMarkup.shot(from: data)
    }

    func fetchImage(_ string: String) async -> UIImage? {
        let clean = Self.https(string)
        guard let url = URL(string: clean) else { return nil }
        guard let data = try? await getData(url, includeSession: false) else { return nil }
        return UIImage(data: data)
    }

    func seasonPlayback(ep: Int, cid: Int, qn: Int, codec: String) async -> PlaybackOffer? {
        guard ep > 0, cid > 0 else { return nil }
        let referer = "https://www.bilibili.com/bangumi/play/ep\(ep)"
        let urls = [
            "https://api.bilibili.com/pgc/player/web/playurl?ep_id=\(ep)&cid=\(cid)&qn=\(qn)&fnver=0&fnval=4048&fourk=1",
            "https://api.bilibili.com/pgc/player/web/v2/playurl?ep_id=\(ep)&cid=\(cid)&qn=\(qn)&fnver=0&fnval=4048&fourk=1&from_client=BROWSER",
            "https://api.bilibili.com/pgc/player/web/playurl?ep_id=\(ep)&cid=\(cid)&qn=\(qn)&fnver=0&fnval=1&fourk=1&platform=html5",
            "https://api.bilibili.com/pgc/player/web/playurl?ep_id=\(ep)&qn=16&fnver=0&fnval=1&platform=html5"
        ]
        for string in urls {
            guard let url = URL(string: string) else { continue }
            do {
                let data = try await getJSON(url, referer: referer)
                let code = data["code"].int ?? -1
                let message = data["message"].string ?? ""
                let info = data["result"]["video_info"]
                let dash = data["result"]["dash"]["video"].array?.count
                    ?? data["data"]["dash"]["video"].array?.count
                    ?? info["dash"]["video"].array?.count
                    ?? 0
                let durl = data["result"]["durl"][0]["url"].string
                    ?? data["data"]["durl"][0]["url"].string
                    ?? info["durl"][0]["url"].string
                    ?? ""
                PlaybackLog.line("pgc ep \(ep) code=\(code) dash=\(dash) durl=\(durl.isEmpty ? 0 : 1) \(message)")
                if code == -10403 || message.contains("地区") { return nil }
                guard code == 0, let offer = PlaybackParser.offer(from: data, requestedQN: qn, codecPreference: codec, audioPreference: "高码率") else { continue }
                return offer
            } catch {
                PlaybackLog.line("pgc ep \(ep) \(error.localizedDescription)")
            }
        }
        return nil
    }

    func seasonGuide(id: Int) async throws -> SeasonGuide {
        guard let url = URL(string: "https://api.bilibili.com/pgc/view/web/season?season_id=\(id)") else {
            throw BiliError.message("番剧地址无效")
        }
        let data = try await getJSON(url, referer: "https://www.bilibili.com/bangumi/play/ss\(id)")
        guard data["code"].int == 0, let guide = PlaybackMarkup.season(from: data, seasonID: id) else {
            throw BiliError.message(data["message"].string ?? "番剧不可用")
        }
        return guide
    }

    /// Guest-signed GET. Callers read `code` themselves so a privacy or login response stays visible.
    func accountGET(
        _ path: String,
        query: [String: String] = [:],
        host: String = "https://api.bilibili.com",
        referer: String = "https://www.bilibili.com",
        signed: Bool = false,
        suppressCookie: Bool = false
    ) async throws -> JSON {
        try await withGuest {
            let data = try await requestQuery(
                path,
                params: query,
                signed: signed,
                referer: referer,
                host: host,
                suppressCookie: suppressCookie
            )
            let code = data["code"].int ?? -1
            if code == -352 || code == 412 { throw BiliError.risk(code) }
            return data
        }
    }

    /// Android-signed GET. A -352 stays in the payload so the caller can try another path.
    func appAccountGET(
        _ path: String,
        query: [String: String],
        host: String = "https://api.bilibili.com",
        referer: String = "https://www.bilibili.com"
    ) async throws -> JSON {
        let signed = AppSign.sign(query)
        let body = signed.keys.sorted().map { key in
            let value = signed[key, default: ""]
            if value.isEmpty { return PercentEncoding.encodeURIComponent(key) }
            return "\(PercentEncoding.encodeURIComponent(key))=\(PercentEncoding.encodeURIComponent(value))"
        }.joined(separator: "&")
        guard let url = URL(string: "\(host)\(path)?\(body)") else {
            throw BiliError.message("地址无效")
        }
        return try await withGuest {
            try await getJSON(url, referer: referer, userAgent: Self.appLiveAgent)
        }
    }
}

struct NavSnapshot: Sendable {
    var isLogin: Bool
    var mid: Int
    var name: String
    var face: String
    var level: Int
    var exp: Int
    var nextExp: Int
    var coins: Int
    var mixinKey: String
}

enum QRPoll: Sendable {
    case pending(String)
    case confirmed(BiliSession)
    case expired(String)
}

struct JSON: @unchecked Sendable {
    let raw: Any
    init(_ raw: Any) { self.raw = raw }

    var string: String? { raw as? String }
    var double: Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? NSNumber { return value.doubleValue }
        if let value = raw as? String { return Double(value) }
        return nil
    }
    var bool: Bool? {
        if let value = raw as? Bool { return value }
        if let value = raw as? NSNumber { return value.boolValue }
        return nil
    }
    var int: Int? {
        if let value = raw as? Int { return value }
        if let value = raw as? Int64 { return Int(value) }
        if let value = raw as? Double { return Int(value) }
        if let value = raw as? NSNumber { return value.intValue }
        if let value = raw as? String { return Int(value) }
        return nil
    }
    var array: [JSON]? { (raw as? [Any])?.map(JSON.init) }
    subscript(_ key: String) -> JSON {
        JSON((raw as? [String: Any])?[key] ?? NSNull())
    }
    subscript(_ index: Int) -> JSON {
        guard let list = raw as? [Any], list.indices.contains(index) else { return JSON(NSNull()) }
        return JSON(list[index])
    }
}
