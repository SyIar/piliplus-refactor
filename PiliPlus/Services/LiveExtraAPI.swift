import Foundation

struct LiveAreaTag: Identifiable, Hashable {
    var id: Int
    var name: String
}

struct LiveSuperChat: Identifiable, Hashable {
    var id: Int
    var name: String
    var face: String
    var message: String
    var price: Int
}

struct LiveEmote: Identifiable, Hashable {
    var id: String
    var name: String
    var url: String
}

enum LiveBlockList {
    private static let key = "piliplus.live.block.v1"

    static func words() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func add(_ raw: String) {
        let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        var list = words()
        if !list.contains(word) { list.append(word) }
        UserDefaults.standard.set(list, forKey: key)
    }

    static func remove(_ word: String) {
        UserDefaults.standard.set(words().filter { $0 != word }, forKey: key)
    }

    static func replace(_ words: [String]) {
        UserDefaults.standard.set(words, forKey: key)
    }

    static func allows(_ text: String) -> Bool {
        let folded = text.lowercased()
        return !words().contains { !$0.isEmpty && folded.contains($0.lowercased()) }
    }
}

enum LiveExtraProof {
    static func record(_ payload: [String: Any]) {
        guard let screen = LaunchMode.screen else { return }
        switch screen {
        case "live-area-detail", "live-follow", "live-search", "live-block", "live-rank", "live-sc", "live-emote":
            break
        default:
            return
        }
        var body = payload
        body["screen"] = screen
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { return }
        try? data.write(to: LaunchClock.documents.appendingPathComponent("live-extra-ui.json"), options: .atomic)
    }
}

extension BiliClient {
    private var liveHost: String { "https://api.live.bilibili.com" }

    func liveAreaTags(parent name: String) async throws -> (id: Int, name: String, children: [LiveAreaTag]) {
        var last = "分区没有打开"
        for suppressCookie in [false, true] {
            do {
                let data = try await accountGET(
                    "/room/v1/Area/getList",
                    host: liveHost,
                    referer: "https://live.bilibili.com",
                    suppressCookie: suppressCookie
                )
                guard data["code"].int == 0 else {
                    last = data["message"].string ?? last
                    continue
                }
                let parents = data["data"].array ?? []
                let wanted = LiveRequest.parentID(for: name)
                let parent = parents.first { item in
                    item["name"].string == name || (wanted > 0 && item["id"].int == wanted)
                } ?? parents.first
                guard let parent else { throw BiliError.message("没有这个分区") }
                let id = parent["id"].int ?? wanted
                let title = parent["name"].string ?? name
                let children = (parent["list"].array ?? []).compactMap { item -> LiveAreaTag? in
                    let child = item["id"].int ?? 0
                    let label = item["name"].string ?? ""
                    guard child > 0, !label.isEmpty else { return nil }
                    return LiveAreaTag(id: child, name: label)
                }
                guard id > 0, !children.isEmpty else { throw BiliError.message("分区里没有子分区") }
                return (id, title, children)
            } catch {
                last = error.localizedDescription
            }
        }
        throw BiliError.message(last)
    }

    func liveChildRooms(parent: Int, area: Int) async throws -> [LiveRoom] {
        let query = [
            "platform": "web",
            "parent_area_id": "\(parent)",
            "area_id": "\(area)",
            "page": "1",
            "page_size": "30",
            "sort_type": "online"
        ]
        var last = "没有直播"
        do {
            let data = try await accountGET(
                "/room/v3/Area/getRoomList",
                query: query,
                host: liveHost,
                referer: "https://live.bilibili.com"
            )
            let rooms = Self.usableRooms(data)
            if !rooms.isEmpty { return rooms }
            last = data["message"].string ?? last
        } catch {
            last = error.localizedDescription
        }
        let appQuery = [
            "area_id": "\(area)",
            "parent_area_id": "\(parent)",
            "page": "1",
            "page_size": "20",
            "sort_type": "online",
            "platform": "android",
            "mobi_app": "android",
            "build": "8430300",
            "device": "android"
        ]
        let data = try await appAccountGET(
            "/xlive/app-interface/v2/second/getList",
            query: appQuery,
            host: liveHost,
            referer: "https://live.bilibili.com"
        )
        let rooms = Self.usableRooms(data)
        if !rooms.isEmpty { return rooms }
        throw BiliError.message(data["message"].string ?? last)
    }

    func popularLiveRooms() async throws -> [LiveRoom] {
        if let rooms = try? await liveChildRooms(parent: 1, area: 0), !rooms.isEmpty { return rooms }
        return try await liveChildRooms(parent: 2, area: 86)
    }

    func followedLiveRooms() async -> (rooms: [LiveRoom], login: Bool, note: String) {
        let query = ["page": "1", "page_size": "20", "ignoreRecord": "1"]
        var last = "关注的直播没有打开"
        for suppressCookie in [false, true] {
            do {
                let data = try await accountGET(
                    "/xlive/web-ucenter/user/following",
                    query: query,
                    host: liveHost,
                    referer: "https://live.bilibili.com",
                    suppressCookie: suppressCookie
                )
                let code = data["code"].int ?? -1
                if code == -101 { return ([], true, "登录后同步你关注的直播间") }
                if code == 0 {
                    let rooms = Self.usableRooms(data)
                    return (rooms, false, rooms.isEmpty ? "关注的人现在没有开播" : "")
                }
                last = data["message"].string ?? last
            } catch {
                last = error.localizedDescription
            }
        }
        return ([], false, last)
    }

    func searchLiveRooms(keyword: String) async throws -> [LiveRoom] {
        let query = [
            "actionKey": "appkey",
            "build": "8430300",
            "device": "android",
            "keyword": keyword,
            "mobi_app": "android",
            "page": "1",
            "pagesize": "20",
            "platform": "android",
            "type": "room"
        ]
        let data = try await appAccountGET(
            "/xlive/app-interface/v2/search_live",
            query: query,
            host: liveHost,
            referer: "https://live.bilibili.com"
        )
        guard data["code"].int == 0 else {
            throw BiliError.message(data["message"].string ?? "直播搜索不可用")
        }
        let list = data["data"]["room"]["list"].array ?? []
        return list.compactMap { item in
            let id = item["roomid"].int ?? item["room_id"].int ?? 0
            let title = Self.unescape(item["title"].string ?? "")
            guard id > 0, !title.isEmpty, !Self.blockedLive(title, item["name"].string ?? "") else { return nil }
            return LiveRoom(
                id: id,
                title: title,
                cover: Self.https(item["cover"].string ?? ""),
                uname: item["uname"].string ?? item["name"].string ?? "",
                face: Self.https(item["face"].string ?? ""),
                online: item["online"].int ?? item["watched_show"]["num"].int ?? 0,
                area: item["area_name"].string ?? "直播",
                mid: item["uid"].int ?? 0
            )
        }
    }

    func liveContribution(room: Int, uid: Int, kind: String) async throws -> [RankPerson] {
        let pair: (String, String) = switch kind {
        case "today": ("daily_rank", "today_rank")
        case "week": ("weekly_rank", "current_week_rank")
        case "month": ("monthly_rank", "current_month_rank")
        default: ("online_rank", "contribution_rank")
        }
        let query = [
            "ruid": "\(uid)",
            "room_id": "\(room)",
            "page": "1",
            "page_size": "20",
            "type": pair.0,
            "switch": pair.1,
            "platform": "web"
        ]
        var last = "高能榜没有打开"
        let attempts: [(Bool, Bool)] = [(false, false), (true, false), (true, true)]
        for (signed, suppressCookie) in attempts {
            do {
                let data = try await accountGET(
                    "/xlive/general-interface/v1/rank/queryContributionRank",
                    query: query,
                    host: liveHost,
                    referer: "https://live.bilibili.com/\(room)",
                    signed: signed,
                    suppressCookie: suppressCookie
                )
                guard data["code"].int == 0 else {
                    last = data["message"].string ?? last
                    continue
                }
                let list = data["data"]["item"].array ?? data["data"]["list"].array ?? []
                let people = list.enumerated().compactMap { index, item -> RankPerson? in
                    let name = item["name"].string ?? item["uname"].string ?? ""
                    guard !name.isEmpty, !Self.blockedLive(name, "") else { return nil }
                    let rank = item["rank"].int ?? index + 1
                    let score = item["score"].int ?? 0
                    return RankPerson(
                        name: name,
                        face: Self.https(item["face"].string ?? ""),
                        rank: rank,
                        detail: score > 0 ? "\(score)" : ""
                    )
                }
                if !people.isEmpty { return people }
                last = "这个直播间还没有上榜"
            } catch {
                last = error.localizedDescription
            }
        }
        throw BiliError.message(last)
    }

    func liveSuperChats(room: Int) async throws -> [LiveSuperChat] {
        let data = try await accountGET(
            "/av/v1/SuperChat/getMessageList",
            query: ["room_id": "\(room)"],
            host: liveHost,
            referer: "https://live.bilibili.com/\(room)"
        )
        guard data["code"].int == 0 else {
            throw BiliError.message(data["message"].string ?? "醒目留言没有打开")
        }
        let list = data["data"]["list"].array ?? []
        return list.enumerated().compactMap { index, item in
            let user = item["user_info"]
            let name = user["uname"].string ?? item["uname"].string ?? ""
            let message = item["message"].string ?? ""
            guard !message.isEmpty else { return nil }
            return LiveSuperChat(
                id: index + 1,
                name: name,
                face: Self.https(user["face"].string ?? item["face"].string ?? ""),
                message: message,
                price: item["price"].int ?? 0
            )
        }
    }

    func liveEmoteState(room: Int) async -> (emotes: [LiveEmote], login: Bool, note: String) {
        let query = ["platform": "pc", "room_id": "\(room)"]
        var last = "表情没有打开"
        for suppressCookie in [false, true] {
            do {
                let data = try await accountGET(
                    "/xlive/web-ucenter/v2/emoticon/GetEmoticons",
                    query: query,
                    host: liveHost,
                    referer: "https://live.bilibili.com/\(room)",
                    suppressCookie: suppressCookie
                )
                let code = data["code"].int ?? -1
                if code == -101 { return ([], true, "登录后查看这个直播间的表情") }
                if code == 0 {
                    var emotes: [LiveEmote] = []
                    let packs = data["data"]["data"].array ?? data["data"]["list"].array ?? []
                    for pack in packs {
                        let icons = pack["emoticons"].array ?? pack["emoticon_list"].array ?? []
                        for icon in icons {
                            let name = icon["emoji"].string ?? icon["name"].string ?? ""
                            let url = Self.https(icon["url"].string ?? "")
                            guard !name.isEmpty, !url.isEmpty else { continue }
                            let id = "\(icon["emoticon_unique"].string ?? name)-\(emotes.count)"
                            emotes.append(LiveEmote(id: id, name: name, url: url))
                        }
                    }
                    return (emotes, false, emotes.isEmpty ? "这个直播间没有表情包" : "")
                }
                last = data["message"].string ?? last
            } catch {
                last = error.localizedDescription
            }
        }
        return ([], false, last)
    }

    private static func usableRooms(_ data: JSON) -> [LiveRoom] {
        guard data["code"].int == 0 else { return [] }
        return liveRooms(in: data).filter { !blockedLive($0.title, $0.uname) }
    }

    private static func blockedLive(_ title: String, _ name: String) -> Bool {
        title.contains("液态玻璃") || name.contains("玻璃试验") || title.lowercased().contains("fixture")
    }
}
