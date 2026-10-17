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

    /// DASH playurl. `platform=html5` is omitted on purpose: it drops the dash block and only returns 720P/360P.
    /// Unsigned `/x/player/playurl` is used because the WBI playurl answered HTTP 412 from this client.
    func playback(bvid: String, cid: Int, qn: Int, tryLook: Bool, codecPreference: String, audioPreference: String) async throws -> PlaybackOffer {
        var comps = URLComponents(string: "https://api.bilibili.com/x/player/playurl")!
        var items = [
            URLQueryItem(name: "bvid", value: bvid),
            URLQueryItem(name: "cid", value: "\(cid)"),
            URLQueryItem(name: "qn", value: "\(qn)"),
            URLQueryItem(name: "fnval", value: "4048"),
            URLQueryItem(name: "fnver", value: "0"),
            URLQueryItem(name: "fourk", value: "1")
        ]
        if tryLook { items.append(URLQueryItem(name: "try_look", value: "1")) }
        comps.queryItems = items
        guard let url = comps.url else { throw BiliError.message("地址无效") }
        let data = try await getJSON(url)
        guard data["code"].int == 0 else { throw BiliError.message(data["message"].string ?? "取流失败") }
        guard let offer = PlaybackParser.offer(from: data, requestedQN: qn, codecPreference: codecPreference, audioPreference: audioPreference) else {
            throw BiliError.message("没有可播放地址")
        }
        return offer
    }

    func danmaku(cid: Int) async throws -> [DanmakuCue] {
        guard let url = URL(string: "https://api.bilibili.com/x/v1/dm/list.so?oid=\(cid)") else {
            throw BiliError.message("弹幕地址无效")
        }
        let data = try await getData(url, includeSession: false)
        guard let xml = RawInflate.expand(data) else { throw BiliError.message("弹幕解压失败") }
        return DanmakuXML.parse(xml)
    }

    func subtitleLines(bvid: String, cid: Int, preference: String) async -> [SubtitleLine] {
        guard let url = URL(string: "https://api.bilibili.com/x/player/v2?bvid=\(bvid)&cid=\(cid)") else { return [] }
        guard let data = try? await getJSON(url), data["code"].int == 0 else { return [] }
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
        Self.dynamics(from: try await popular())
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
                repost: video.share
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

    private func getJSON(_ url: URL, includeSession: Bool = true, cookieOverride: String? = nil) async throws -> JSON {
        try await send(url, method: "GET", body: nil, includeSession: includeSession, cookieOverride: cookieOverride)
    }

    private func getData(_ url: URL, includeSession: Bool) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if includeSession, let header = SessionVault.shared.cookieHeader(), !header.isEmpty {
            request.setValue(header, forHTTPHeaderField: "Cookie")
        }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BiliError.message("网络 \(http.statusCode)")
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
        includeCSRF: Bool = true
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
            cookieOverride: cookieOverride
        )
    }

    private func send(
        _ url: URL,
        method: String,
        body: Data?,
        contentType: String? = nil,
        includeSession: Bool,
        cookieOverride: String?
    ) async throws -> JSON {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        let header = cookieOverride ?? (includeSession ? SessionVault.shared.cookieHeader() : nil)
        if let header, !header.isEmpty {
            request.setValue(header, forHTTPHeaderField: "Cookie")
        }
        let (data, response) = try await session.data(for: request)
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
