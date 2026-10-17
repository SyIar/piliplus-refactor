import Foundation

enum BiliError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let text) = self { return text }
        return nil
    }
}

struct BiliClient: Sendable {
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 18
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 27_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
            "Referer": "https://www.bilibili.com"
        ]
        return URLSession(configuration: config)
    }()

    func popular(page: Int = 1) async throws -> [VideoItem] {
        let data = try await getJSON("https://api.bilibili.com/x/web-interface/popular?ps=20&pn=\(page)")
        let list = data["data"]["list"].array ?? []
        return list.compactMap(Self.video(fromPopular:))
    }

    func ranking(rid: Int = 0) async throws -> [VideoItem] {
        let data = try await getJSON("https://api.bilibili.com/x/web-interface/ranking/v2?rid=\(rid)&type=all")
        let list = data["data"]["list"].array ?? []
        return list.compactMap(Self.video(fromPopular:))
    }

    func searchVideos(keyword: String, order: String = "totalrank", duration: Int = 0, tid: Int = 0, page: Int = 1) async throws -> [VideoItem] {
        var comps = URLComponents(string: "https://api.bilibili.com/x/web-interface/search/type")!
        var items = [
            URLQueryItem(name: "search_type", value: "video"),
            URLQueryItem(name: "keyword", value: keyword),
            URLQueryItem(name: "order", value: order),
            URLQueryItem(name: "page", value: "\(page)")
        ]
        if duration > 0 { items.append(URLQueryItem(name: "duration", value: "\(duration)")) }
        if tid > 0 { items.append(URLQueryItem(name: "tids", value: "\(tid)")) }
        comps.queryItems = items
        let data = try await getJSON(comps.url!)
        if data["code"].int != 0 {
            throw BiliError.message(data["message"].string ?? "搜索失败")
        }
        return (data["data"]["result"].array ?? []).compactMap(Self.video(fromSearch:))
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
        let data = try await getJSON("https://api.bilibili.com/x/web-interface/view?bvid=\(bvid)")
        guard data["code"].int == 0 else { throw BiliError.message(data["message"].string ?? "无法打开视频") }
        guard let video = Self.video(fromView: data["data"]) else { throw BiliError.message("视频数据为空") }
        return video
    }

    func related(bvid: String) async throws -> [VideoItem] {
        let data = try await getJSON("https://api.bilibili.com/x/web-interface/archive/related?bvid=\(bvid)")
        return (data["data"].array ?? []).compactMap(Self.video(fromRelated:))
    }

    func replies(aid: Int, page: Int = 1) async throws -> [CommentItem] {
        let data = try await getJSON("https://api.bilibili.com/x/v2/reply?type=1&sort=1&oid=\(aid)&pn=\(page)&ps=20")
        guard data["code"].int == 0 else { throw BiliError.message(data["message"].string ?? "评论不可用") }
        return (data["data"]["replies"].array ?? []).compactMap(Self.comment)
    }

    func playURL(bvid: String, cid: Int, qn: Int) async throws -> (url: String, qualities: [String]) {
        var comps = URLComponents(string: "https://api.bilibili.com/x/player/playurl")!
        comps.queryItems = [
            URLQueryItem(name: "bvid", value: bvid),
            URLQueryItem(name: "cid", value: "\(cid)"),
            URLQueryItem(name: "qn", value: "\(qn)"),
            URLQueryItem(name: "fnval", value: "1"),
            URLQueryItem(name: "fnver", value: "0"),
            URLQueryItem(name: "fourk", value: "1"),
            URLQueryItem(name: "platform", value: "html5")
        ]
        let data = try await getJSON(comps.url!)
        guard data["code"].int == 0 else { throw BiliError.message(data["message"].string ?? "取流失败") }
        let qualities = (data["data"]["accept_description"].array ?? []).compactMap(\.string)
        let url = data["data"]["durl"][0]["url"].string ?? ""
        guard !url.isEmpty else { throw BiliError.message("没有可播放地址") }
        return (url, qualities)
    }

    func liveRooms() async throws -> [LiveRoom] {
        let data = try await getJSON("https://api.live.bilibili.com/xlive/web-interface/v1/second/getList?platform=web&parent_area_id=0&area_id=0&sort_type=&page=1")
        let list = data["data"]["list"].array ?? []
        return list.compactMap { item in
            let id = item["roomid"].int ?? 0
            guard id > 0 else { return nil }
            return LiveRoom(
                id: id,
                title: item["title"].string ?? "直播",
                cover: Self.https(item["cover"].string ?? item["user_cover"].string ?? ""),
                uname: item["uname"].string ?? "",
                face: Self.https(item["face"].string ?? ""),
                online: item["online"].int ?? item["watched_show"]["num"].int ?? 0,
                area: item["area_name"].string ?? item["area_v2_name"].string ?? "直播"
            )
        }
    }

    func dynamics() async throws -> [DynamicItem] {
        // 未登录时使用综合热门作为动态流的公开替代，登录 Cookie 接入后可切到 polymer 动态接口。
        let videos = try await popular()
        return videos.enumerated().map { index, video in
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
                repost: video.share
            )
        }
    }

    private func getJSON(_ string: String) async throws -> JSON {
        guard let url = URL(string: string) else { throw BiliError.message("地址无效") }
        return try await getJSON(url)
    }

    private func getJSON(_ url: URL) async throws -> JSON {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BiliError.message("网络 \(http.statusCode)")
        }
        let object = try JSONSerialization.jsonObject(with: data)
        return JSON(object)
    }

    static func https(_ raw: String) -> String {
        var value = raw.replacingOccurrences(of: "http://", with: "https://")
        if value.hasPrefix("//") { value = "https:" + value }
        return value
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
        return video
    }

    static func video(fromRelated item: JSON) -> VideoItem? {
        video(fromPopular: item)
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
        return CommentItem(
            id: id,
            name: item["member"]["uname"].string ?? "用户",
            face: https(item["member"]["avatar"].string ?? ""),
            message: item["content"]["message"].string ?? "",
            like: item["like"].int ?? 0,
            ctime: item["ctime"].int ?? 0,
            replies: replies
        )
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
}

struct JSON: @unchecked Sendable {
    let raw: Any
    init(_ raw: Any) { self.raw = raw }

    var string: String? { raw as? String }
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
