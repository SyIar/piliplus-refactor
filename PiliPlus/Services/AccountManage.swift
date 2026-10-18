import Foundation

struct RelationPerson: Identifiable, Hashable {
    var id: Int { mid }
    var mid: Int
    var name: String
    var face: String
    var sign: String
}

struct ArticleCard: Identifiable, Hashable {
    var id: Int
    var title: String
    var summary: String
    var cover: String
    var author: String
}

struct RankPerson: Identifiable, Hashable {
    var id: String { "\(rank)-\(name)" }
    var name: String
    var face: String
    var rank: Int
    var detail: String
}

struct SavedAccount: Identifiable, Hashable {
    var id: String { mid > 0 ? "\(mid)" : name }
    var mid: Int
    var name: String
}

enum AccountBook {
    private static let key = "piliplus.accounts.v1"

    static func accounts() -> [SavedAccount] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let rows = try? JSONDecoder().decode([Stored].self, from: data) else { return [] }
        return rows.map { SavedAccount(mid: $0.mid, name: $0.name) }
    }

    static func remember(mid: Int, name: String) {
        guard mid > 0, !name.isEmpty else { return }
        var rows = accounts().filter { $0.mid != mid }
        rows.insert(SavedAccount(mid: mid, name: name), at: 0)
        let stored = rows.map { Stored(mid: $0.mid, name: $0.name) }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private struct Stored: Codable {
        var mid: Int
        var name: String
    }
}

enum AccountManageRequest {
    static func fans(mid: Int, page: Int) -> SignedForm {
        SignedForm(method: "GET", path: "/x/relation/fans", fields: [
            "vmid": "\(mid)",
            "pn": "\(page)",
            "ps": "20"
        ])
    }

    static func followings(mid: Int, page: Int) -> SignedForm {
        SignedForm(method: "GET", path: "/x/relation/followings", fields: [
            "vmid": "\(mid)",
            "pn": "\(page)",
            "ps": "20",
            "order": "desc"
        ])
    }

    static func tags() -> SignedForm {
        SignedForm(method: "GET", path: "/x/relation/tags", fields: [:])
    }

    /// `-10` is the special-follow tag. Whisper uses `/x/relation/whispers`.
    static func tagMembers(tag: Int, page: Int) -> SignedForm {
        SignedForm(method: "GET", path: "/x/relation/tag", fields: [
            "tagid": "\(tag)",
            "pn": "\(page)",
            "ps": "20"
        ])
    }

    static func whispers(page: Int) -> SignedForm {
        SignedForm(method: "GET", path: "/x/relation/whispers", fields: [
            "pn": "\(page)",
            "ps": "20"
        ])
    }

    static func blacks(page: Int) -> SignedForm {
        SignedForm(method: "GET", path: "/x/relation/blacks", fields: [
            "pn": "\(page)",
            "ps": "20"
        ])
    }

    static func coinLog() -> SignedForm {
        SignedForm(method: "GET", path: "/x/member/web/coin/log", fields: [:])
    }

    static func expLog() -> SignedForm {
        SignedForm(method: "GET", path: "/x/member/web/exp/log", fields: [:])
    }

    static func profile() -> SignedForm {
        SignedForm(method: "GET", path: "/x/member/web/account", fields: [:])
    }

    static func updateProfile(name: String, sign: String, sex: String, birthday: String, csrf: String) -> SignedForm {
        SignedForm(method: "POST", path: "/x/member/web/update", fields: [
            "uname": name,
            "sign": sign,
            "sex": sex,
            "birthday": birthday,
            "csrf": csrf
        ])
    }

    static func loginNotices() -> SignedForm {
        SignedForm(method: "GET", path: "/x/safecenter/login_notice", fields: [
            "type": "1"
        ])
    }

    static func likes(mid: Int) -> SignedForm {
        SignedForm(method: "GET", path: "/x/space/like/video", fields: ["vmid": "\(mid)"])
    }

    static func coins(mid: Int) -> SignedForm {
        SignedForm(method: "GET", path: "/x/space/coin/video", fields: ["vmid": "\(mid)"])
    }

    static func articles(mid: Int, page: Int) -> SignedForm {
        SignedForm(method: "GET", path: "/x/space/article", fields: [
            "mid": "\(mid)",
            "pn": "\(page)",
            "ps": "12"
        ])
    }

    static func charge(mid: Int) -> SignedForm {
        SignedForm(method: "GET", path: "/x/ugcpay-rank/elec/month/up", fields: ["up_mid": "\(mid)"])
    }

    static func guards(room: Int, uid: Int) -> SignedForm {
        SignedForm(method: "GET", path: "/xlive/app-room/v2/guardTab/topList", fields: [
            "roomid": "\(room)",
            "ruid": "\(uid)",
            "page": "1",
            "page_size": "20"
        ])
    }

    static func spaceSearch(mid: Int, keyword: String) -> SignedForm {
        SignedForm(method: "GET", path: "/x/space/wbi/arc/search", fields: [
            "mid": "\(mid)",
            "keyword": keyword,
            "pn": "1",
            "ps": "20",
            "order": "pubdate"
        ])
    }

    static func shop(mid: Int) -> SignedForm {
        SignedForm(method: "GET", path: "/x/space/shop", fields: ["mid": "\(mid)"])
    }

    static func navnum(mid: Int) -> SignedForm {
        SignedForm(method: "GET", path: "/x/space/navnum", fields: ["mid": "\(mid)"])
    }
}

enum AccountManageProof {
    static func writeAndExit() -> Never {
        let csrf = "jct-token"
        let cases: [(String, SignedForm, String, Bool)] = [
            ("fans", AccountManageRequest.fans(mid: 7, page: 1), "pn=1&ps=20&vmid=7", false),
            ("followings", AccountManageRequest.followings(mid: 7, page: 1), "order=desc&pn=1&ps=20&vmid=7", false),
            ("tags", AccountManageRequest.tags(), "", false),
            ("special", AccountManageRequest.tagMembers(tag: -10, page: 1), "pn=1&ps=20&tagid=-10", false),
            ("whispers", AccountManageRequest.whispers(page: 1), "pn=1&ps=20", false),
            ("blacks", AccountManageRequest.blacks(page: 1), "pn=1&ps=20", false),
            ("coin-log", AccountManageRequest.coinLog(), "", false),
            ("exp-log", AccountManageRequest.expLog(), "", false),
            ("profile", AccountManageRequest.profile(), "", false),
            ("profile-save", AccountManageRequest.updateProfile(name: "Pili", sign: "hi", sex: "保密", birthday: "2000-01-01", csrf: csrf), "birthday=2000-01-01&csrf=jct-token&sex=%E4%BF%9D%E5%AF%86&sign=hi&uname=Pili", true),
            ("devices", AccountManageRequest.loginNotices(), "type=1", false),
            ("likes", AccountManageRequest.likes(mid: 7), "vmid=7", false),
            ("coins", AccountManageRequest.coins(mid: 7), "vmid=7", false),
            ("articles", AccountManageRequest.articles(mid: 7, page: 1), "mid=7&pn=1&ps=12", false),
            ("charge", AccountManageRequest.charge(mid: 7), "up_mid=7", false),
            ("guards", AccountManageRequest.guards(room: 1, uid: 7), "page=1&page_size=20&roomid=1&ruid=7", false),
            ("space-search", AccountManageRequest.spaceSearch(mid: 7, keyword: "AI"), "keyword=AI&mid=7&order=pubdate&pn=1&ps=20", false),
            ("shop", AccountManageRequest.shop(mid: 7), "mid=7", false)
        ]
        var failures: [String] = []
        var found: [[String: Any]] = []
        for (name, form, body, needsCSRF) in cases {
            found.append([
                "name": name,
                "method": form.method,
                "path": form.path,
                "body": form.body,
                "csrf": form.hasCSRF
            ])
            if form.body != body || form.hasCSRF != needsCSRF || (form.method == "GET" && form.endpoint == nil) {
                failures.append("\(name) \(form.body)")
            }
        }
        let payload: [String: Any] = [
            "ok": failures.isEmpty,
            "checked": found.count,
            "failures": failures,
            "cases": found
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        try? data.write(to: LaunchClock.documents.appendingPathComponent("account-manage-proof.json"), options: .atomic)
        if let text = String(data: data, encoding: .utf8) {
            print("ACCOUNT_MANAGE_PROOF_BEGIN")
            print(text)
            print("ACCOUNT_MANAGE_PROOF_END")
            fflush(stdout)
        }
        exit(failures.isEmpty ? 0 : 1)
    }
}

enum AccountManageUIProof {
    static func record(_ payload: [String: Any]) {
        guard let screen = LaunchMode.screen, screen.hasPrefix("acct-") else { return }
        var body = payload
        body["screen"] = screen
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { return }
        try? data.write(to: LaunchClock.documents.appendingPathComponent("account-manage-ui.json"), options: .atomic)
    }
}

enum AccountReads {
    static func people(_ data: JSON) -> [RelationPerson] {
        let list = data["data"]["list"].array ?? []
        return list.compactMap { item in
            let mid = item["mid"].int ?? item["fid"].int ?? 0
            let name = item["uname"].string ?? item["name"].string ?? ""
            guard mid > 0, !name.isEmpty else { return nil }
            return RelationPerson(mid: mid, name: name, face: https(item["face"].string ?? ""), sign: item["sign"].string ?? "")
        }
    }

    static func videos(_ data: JSON) -> [VideoItem] {
        let list = data["data"]["list"].array ?? data["data"].array ?? []
        return list.compactMap(video)
    }

    static func articles(_ data: JSON) -> [ArticleCard] {
        (data["data"]["articles"].array ?? []).compactMap { item in
            let id = item["id"].int ?? 0
            let title = item["title"].string ?? ""
            guard id > 0, !title.isEmpty else { return nil }
            let images = item["image_urls"].array ?? []
            let cover = item["banner_url"].string ?? images.first?.string ?? ""
            let author = item["author"]["name"].string ?? ""
            return ArticleCard(id: id, title: title, summary: item["summary"].string ?? "", cover: https(cover), author: author)
        }
    }

    static func charge(_ data: JSON) -> [RankPerson] {
        (data["data"]["list"].array ?? []).enumerated().compactMap { index, item in
            let name = item["uname"].string ?? ""
            guard !name.isEmpty else { return nil }
            let rank = item["rank"].int ?? index + 1
            return RankPerson(name: name, face: https(item["avatar"].string ?? ""), rank: rank, detail: "充电")
        }
    }

    static func guards(_ data: JSON) -> [RankPerson] {
        let list = data["data"]["list"].array ?? []
        let source = list.isEmpty ? (data["data"]["top3"].array ?? []) : list
        return source.enumerated().compactMap { index, item in
            let name = item["username"].string ?? item["uname"].string ?? ""
            guard !name.isEmpty else { return nil }
            let rank = item["rank"].int ?? index + 1
            return RankPerson(name: name, face: https(item["face"].string ?? ""), rank: rank, detail: "大航海")
        }
    }

    static func realVideo(_ video: VideoItem) -> Bool {
        !video.bvid.isEmpty && !video.title.isEmpty && !LocalLibrary.isFixture(video)
    }

    private static func video(_ item: JSON) -> VideoItem? {
        let title = item["title"].string ?? ""
        let bvid = item["bvid"].string ?? ""
        let aid = item["aid"].int ?? item["stat"]["aid"].int ?? 0
        guard !title.isEmpty, !bvid.isEmpty || aid > 0 else { return nil }
        let owner = item["owner"]
        return VideoItem(
            bvid: bvid.isEmpty ? "av\(aid)" : bvid,
            aid: aid,
            cid: item["cid"].int ?? 0,
            title: title,
            cover: https(item["pic"].string ?? item["cover"].string ?? ""),
            duration: item["duration"].int ?? 0,
            ownerName: owner["name"].string ?? item["author"].string ?? "",
            ownerMid: owner["mid"].int ?? 0,
            ownerFace: https(owner["face"].string ?? ""),
            desc: "",
            pubdate: item["pubdate"].int ?? 0,
            view: item["stat"]["view"].int ?? item["view"].int ?? 0,
            danmaku: item["stat"]["danmaku"].int ?? item["danmaku"].int ?? 0,
            like: item["stat"]["like"].int ?? 0,
            coin: item["stat"]["coin"].int ?? 0,
            favorite: item["stat"]["favorite"].int ?? 0,
            share: item["stat"]["share"].int ?? 0,
            reply: item["stat"]["reply"].int ?? 0,
            pages: [],
            tname: item["tname"].string ?? ""
        )
    }

    private static func https(_ raw: String) -> String {
        if raw.hasPrefix("http://") { return "https://" + raw.dropFirst(7) }
        return raw
    }
}

extension BiliClient {
    func relationFans(mid: Int) async throws -> [RelationPerson] {
        let form = AccountManageRequest.fans(mid: mid, page: 1)
        let referer = "https://space.bilibili.com/\(mid)/fans/fans"
        var web = form.fields
        web["order"] = "desc"
        web["order_type"] = "attention"
        web["gaia_source"] = "main_web"
        web["web_location"] = "333.999"
        var last = "粉丝列表不可用"
        for suppressCookie in [false, true] {
            do {
                let data = try await accountGET(
                    form.path,
                    query: web,
                    referer: referer,
                    signed: true,
                    suppressCookie: suppressCookie
                )
                if let rows = Self.fans(in: data) {
                    print("fans web cookie=\(!suppressCookie) rows=\(rows.count)")
                    return rows
                }
                last = data["message"].string ?? last
                print("fans web cookie=\(!suppressCookie) code=\(data["code"].int ?? -1) \(last)")
            } catch {
                last = error.localizedDescription
                print("fans web cookie=\(!suppressCookie) \(last)")
            }
        }
        let appQuery = [
            "vmid": "\(mid)",
            "pn": "1",
            "ps": "20",
            "order": "desc",
            "build": "8430300",
            "mobi_app": "android",
            "platform": "android"
        ]
        for path in ["/x/relation/fans", "/x/relation/followers"] {
            do {
                let data = try await appAccountGET(path, query: appQuery, referer: "https://www.bilibili.com")
                if let rows = Self.fans(in: data) {
                    print("fans app \(path) rows=\(rows.count)")
                    return rows
                }
                last = data["message"].string ?? last
                print("fans app \(path) code=\(data["code"].int ?? -1) \(last)")
            } catch {
                last = error.localizedDescription
                print("fans app \(path) \(last)")
            }
        }
        throw BiliError.message(last)
    }

    private static func fans(in data: JSON) -> [RelationPerson]? {
        guard data["code"].int == 0 else { return nil }
        let rows = AccountReads.people(data)
        return rows.isEmpty ? nil : rows
    }

    func recentLikes(mid: Int) async throws -> [VideoItem] {
        try await spaceVideos(AccountManageRequest.likes(mid: mid), referer: "https://space.bilibili.com/\(mid)")
    }

    func recentCoins(mid: Int) async throws -> [VideoItem] {
        try await spaceVideos(AccountManageRequest.coins(mid: mid), referer: "https://space.bilibili.com/\(mid)")
    }

    func spaceArticles(mid: Int) async throws -> [ArticleCard] {
        let form = AccountManageRequest.articles(mid: mid, page: 1)
        let data = try await accountGET(form.path, query: form.fields, referer: "https://space.bilibili.com/\(mid)")
        guard data["code"].int == 0 else {
            throw BiliError.message(data["message"].string ?? "专栏不可用")
        }
        return AccountReads.articles(data)
    }

    func chargeRank(mid: Int) async throws -> [RankPerson] {
        let form = AccountManageRequest.charge(mid: mid)
        let referer = "https://space.bilibili.com/\(mid)"
        var last = "充电榜不可用"
        for signed in [false, true] {
            do {
                let data = try await accountGET(form.path, query: form.fields, referer: referer, signed: signed)
                guard data["code"].int == 0 else {
                    last = data["message"].string ?? last
                    continue
                }
                let rows = AccountReads.charge(data)
                if !rows.isEmpty { return rows }
                last = "没有充电榜"
            } catch {
                last = error.localizedDescription
            }
        }
        throw BiliError.message(last)
    }

    func guardRank(room: Int, uid: Int) async throws -> [RankPerson] {
        let form = AccountManageRequest.guards(room: room, uid: uid)
        let data = try await accountGET(
            form.path,
            query: form.fields,
            host: "https://api.live.bilibili.com",
            referer: "https://live.bilibili.com/\(room)"
        )
        guard data["code"].int == 0 else {
            throw BiliError.message(data["message"].string ?? "大航海不可用")
        }
        return AccountReads.guards(data)
    }

    func spaceShopState(mid: Int) async -> String {
        let form = AccountManageRequest.shop(mid: mid)
        guard let data = try? await accountGET(form.path, query: form.fields, referer: "https://space.bilibili.com/\(mid)") else {
            return "小店暂时打不开"
        }
        let code = data["code"].int ?? -1
        if code == -101 { return "login" }
        if code == 0 { return "empty" }
        return data["message"].string ?? "小店暂时打不开"
    }

    /// Space `navnum` has no comic shelf for the public mids we can read.
    func spaceComicNote(mid: Int) async -> String {
        let form = AccountManageRequest.navnum(mid: mid)
        guard let data = try? await accountGET(form.path, query: form.fields, referer: "https://space.bilibili.com/\(mid)"),
              data["code"].int == 0 else {
            return "没有公开漫画"
        }
        let comic = data["data"]["comic"].int ?? 0
        return comic > 0 ? "漫画 \(comic)" : "没有公开漫画"
    }

    func roomID(mid: Int) async -> Int {
        guard let data = try? await accountGET(
            "/room/v1/Room/getRoomInfoOld",
            query: ["mid": "\(mid)"],
            host: "https://api.live.bilibili.com",
            referer: "https://live.bilibili.com"
        ) else { return 0 }
        return data["data"]["roomid"].int ?? 0
    }

    func busiestGuards() async -> (room: LiveRoom, people: [RankPerson])? {
        var pool: [LiveRoom] = []
        for area in ["推荐", "娱乐", "虚拟主播"] {
            pool += (try? await liveList(area: area, page: 1)) ?? []
        }
        var seen = Set<Int>()
        let rooms = pool.filter { seen.insert($0.id).inserted }
        var best: (room: LiveRoom, people: [RankPerson])?
        for room in rooms.prefix(8) {
            var uid = room.mid
            if uid == 0, let info = try? await liveRoomInfo(room: room.id) {
                uid = info.mid
            }
            guard uid > 0 else { continue }
            let people = (try? await guardRank(room: room.id, uid: uid)) ?? []
            guard people.count > (best?.people.count ?? 0) else { continue }
            var chosen = room
            if chosen.mid == 0 { chosen.mid = uid }
            best = (chosen, people)
        }
        return best
    }

    private func spaceVideos(_ form: SignedForm, referer: String) async throws -> [VideoItem] {
        let data = try await accountGET(form.path, query: form.fields, referer: referer)
        let code = data["code"].int ?? -1
        guard code == 0 else {
            throw BiliError.message(data["message"].string ?? "列表不可用")
        }
        return AccountReads.videos(data).filter(AccountReads.realVideo)
    }
}
