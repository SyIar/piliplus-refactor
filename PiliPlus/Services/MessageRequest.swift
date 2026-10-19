import Darwin
import Foundation

/// Reply, @, like, system notices, private sessions, and a text send, before they touch the network.
struct MessageCall: Equatable, Sendable {
    var host: String
    var signed: Bool
    var form: SignedForm

    var method: String { form.method }
    var path: String { form.path }
    var body: String { form.body }
    var fields: [String: String] { form.fields }

    var referer: String {
        if host.contains("api.vc.bilibili.com") || host.contains("message.bilibili.com") {
            return "https://message.bilibili.com/"
        }
        return "https://www.bilibili.com/"
    }

    var origin: String {
        String(referer.dropLast())
    }
}

struct NoticeItem: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var face: String
    var title: String
    var subtitle: String
    var time: Int
    var timeText: String
}

struct ChatSession: Identifiable, Hashable, Sendable {
    var id: Int
    var name: String
    var face: String
    var preview: String
    var time: Int
    var unread: Int
    var seqno: Int
}

struct ChatLine: Identifiable, Hashable, Sendable {
    var id: Int
    var text: String
    var mine: Bool
    var time: Int
    var system: Bool
}

struct MessageUnread: Sendable {
    var reply: Int
    var at: Int
    var like: Int
    var system: Int
}

struct NoticePage: Sendable {
    var items: [NoticeItem]
    var cursor: Int
    var cursorTime: Int
    var ended: Bool
}

struct SessionPage: Sendable {
    var items: [ChatSession]
    var hasMore: Bool
}

struct ChatPage: Sendable {
    var items: [ChatLine]
    var hasMore: Bool
    var maxSeqno: Int
}

enum MessageRequest {
    static let api = "https://api.bilibili.com"
    static let message = "https://message.bilibili.com"
    static let vc = "https://api.vc.bilibili.com"

    static func reply(cursor: Int = 0, time: Int = 0) -> MessageCall {
        feed("/x/msgfeed/reply", cursor: cursor, time: time, timeKey: "reply_time")
    }

    static func at(cursor: Int = 0, time: Int = 0) -> MessageCall {
        feed("/x/msgfeed/at", cursor: cursor, time: time, timeKey: "at_time")
    }

    static func like(cursor: Int = 0, time: Int = 0) -> MessageCall {
        feed("/x/msgfeed/like", cursor: cursor, time: time, timeKey: "like_time")
    }

    static func system(cursor: Int = 0) -> MessageCall {
        var fields = [
            "page_size": "20",
            "mobi_app": "web",
            "build": "0",
            "web_location": "333.40164"
        ]
        if cursor > 0 { fields["cursor"] = "\(cursor)" }
        return call(host: message, signed: false, method: "GET", path: "/x/sys-msg/query_notify_list", fields: fields)
    }

    static func unread() -> MessageCall {
        call(host: api, signed: false, method: "GET", path: "/x/msgfeed/unread", fields: [
            "build": "0",
            "mobi_app": "web",
            "web_location": "333.1365"
        ])
    }

    static func sessions(endTs: Int = 0) -> MessageCall {
        var fields = [
            "session_type": "1",
            "group_fold": "1",
            "unfollow_fold": "0",
            "sort_rule": "2",
            "build": "0",
            "mobi_app": "web"
        ]
        if endTs > 0 { fields["end_ts"] = "\(endTs)" }
        return call(host: vc, signed: true, method: "GET", path: "/session_svr/v1/session_svr/get_sessions", fields: fields)
    }

    static func cards(ids: [Int]) -> MessageCall {
        let uids = ids.filter { $0 > 0 }.map(String.init).joined(separator: ",")
        return call(host: vc, signed: true, method: "GET", path: "/account/v1/user/cards", fields: [
            "uids": uids,
            "build": "0",
            "mobi_app": "web"
        ])
    }

    static func messages(talker: Int, endSeqno: Int = 0) -> MessageCall {
        var fields = [
            "talker_id": "\(talker)",
            "session_type": "1",
            "size": "20",
            "sender_device_id": "1",
            "build": "0",
            "mobi_app": "web"
        ]
        if endSeqno > 0 { fields["end_seqno"] = "\(endSeqno)" }
        return call(host: vc, signed: true, method: "GET", path: "/svr_sync/v1/svr_sync/fetch_session_msgs", fields: fields)
    }

    static func ack(talker: Int, seqno: Int, csrf: String) -> MessageCall {
        call(host: vc, signed: true, method: "GET", path: "/session_svr/v1/session_svr/update_ack", fields: [
            "talker_id": "\(talker)",
            "session_type": "1",
            "ack_seqno": "\(seqno)",
            "build": "0",
            "mobi_app": "web",
            "csrf_token": csrf,
            "csrf": csrf
        ])
    }

    /// Text messages are form fields shaped like `msg[content]`. Blank text or a missing csrf returns nil.
    static func send(sender: Int, receiver: Int, text: String, device: String, timestamp: Int, csrf: String) -> MessageCall? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sender > 0, receiver > 0, !trimmed.isEmpty, !device.isEmpty, timestamp > 0, !csrf.isEmpty else { return nil }
        let content = contentJSON(trimmed)
        guard !content.isEmpty else { return nil }
        return call(host: vc, signed: true, method: "POST", path: "/web_im/v1/web_im/send_msg", fields: [
            "msg[sender_uid]": "\(sender)",
            "msg[receiver_id]": "\(receiver)",
            "msg[receiver_type]": "1",
            "msg[msg_type]": "1",
            "msg[msg_status]": "0",
            "msg[dev_id]": device,
            "msg[timestamp]": "\(timestamp)",
            "msg[new_face_version]": "1",
            "msg[content]": content,
            "from_firework": "0",
            "build": "0",
            "mobi_app": "web",
            "csrf_token": csrf,
            "csrf": csrf
        ])
    }

    static func contentJSON(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "{\"content\":\"\(escaped)\"}"
    }

    private static func feed(_ path: String, cursor: Int, time: Int, timeKey: String) -> MessageCall {
        var fields = [
            "platform": "web",
            "mobi_app": "web",
            "build": "0",
            "web_location": "333.40164"
        ]
        if cursor > 0 { fields["id"] = "\(cursor)" }
        if time > 0 { fields[timeKey] = "\(time)" }
        return call(host: api, signed: false, method: "GET", path: path, fields: fields)
    }

    private static func call(host: String, signed: Bool, method: String, path: String, fields: [String: String]) -> MessageCall {
        MessageCall(host: host, signed: signed, form: SignedForm(method: method, path: path, fields: fields))
    }
}

enum MessageParser {
    static func unread(_ data: JSON) -> MessageUnread {
        let bag = data["data"]
        return MessageUnread(
            reply: bag["reply"].int ?? 0,
            at: bag["at"].int ?? 0,
            like: bag["like"].int ?? 0,
            system: bag["sys_msg"].int ?? bag["sys"].int ?? 0
        )
    }

    static func notices(kind: String, data: JSON) -> (items: [NoticeItem], cursor: Int, cursorTime: Int, ended: Bool) {
        if kind == "系统通知" {
            let list = data["data"].array ?? []
            let items = list.enumerated().compactMap { index, item in system(item, index: index) }
            let cursor = (list.last ?? JSON(NSNull()))["cursor"].int ?? 0
            return (items, cursor, 0, list.count < 20 || cursor <= 0)
        }
        let list = data["data"]["items"].array ?? []
        let cursor = data["data"]["cursor"]
        let ended = cursor["is_end"].bool == true || list.isEmpty
        let items: [NoticeItem]
        switch kind {
        case "@我": items = list.compactMap { at($0) }
        case "收到的赞": items = list.compactMap { like($0) }
        default: items = list.compactMap { reply($0) }
        }
        return (items, cursor["id"].int ?? 0, cursor["time"].int ?? 0, ended)
    }

    static func sessions(_ data: JSON) -> (items: [ChatSession], hasMore: Bool) {
        let list = data["data"]["session_list"].array ?? []
        return (list.compactMap { session($0) }, flag(data["data"]["has_more"], fallback: list.count >= 20))
    }

    static func cards(_ data: JSON) -> [Int: (name: String, face: String)] {
        var found: [Int: (name: String, face: String)] = [:]
        let list = data["data"].array ?? data["data"]["cards"].array ?? []
        for item in list {
            let id = item["mid"].int ?? item["uid"].int ?? 0
            guard id > 0 else { continue }
            let name = item["name"].string ?? item["uname"].string ?? ""
            found[id] = (name.isEmpty ? "用户 \(id)" : name, BiliClient.https(item["face"].string ?? ""))
        }
        return found
    }

    static func lines(_ data: JSON, mine: Int) -> (items: [ChatLine], hasMore: Bool) {
        let list = data["data"]["messages"].array ?? []
        let items = list.compactMap { line(from: $0, mine: mine) }.sorted { $0.id < $1.id }
        return (items, flag(data["data"]["has_more"], fallback: list.count >= 20))
    }

    static func clock(_ stamp: Int) -> String {
        guard stamp > 0 else { return "" }
        let seconds = stamp > 10_000_000_000 ? TimeInterval(stamp) / 1000 : TimeInterval(stamp)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: seconds))
    }

    private static func reply(_ item: JSON) -> NoticeItem? {
        let id = item["id"].int ?? 0
        guard id > 0 else { return nil }
        let user = item["user"]
        let body = item["item"]
        let source = body["source_content"].string ?? ""
        let quoted = body["target_reply_content"].string ?? body["root_reply_content"].string ?? ""
        let time = item["reply_time"].int ?? 0
        return NoticeItem(
            id: "reply-\(id)",
            name: user["nickname"].string ?? "用户",
            face: BiliClient.https(user["avatar"].string ?? ""),
            title: source.isEmpty ? "回复了你" : source,
            subtitle: quoted,
            time: time,
            timeText: clock(time)
        )
    }

    private static func at(_ item: JSON) -> NoticeItem? {
        let id = item["id"].int ?? 0
        guard id > 0 else { return nil }
        let user = item["user"]
        let body = item["item"]
        let source = body["source_content"].string ?? ""
        let time = item["at_time"].int ?? 0
        return NoticeItem(
            id: "at-\(id)",
            name: user["nickname"].string ?? "用户",
            face: BiliClient.https(user["avatar"].string ?? ""),
            title: source.isEmpty ? "提到了你" : source,
            subtitle: body["business"].string ?? "",
            time: time,
            timeText: clock(time)
        )
    }

    private static func like(_ item: JSON) -> NoticeItem? {
        let id = item["id"].int ?? 0
        guard id > 0 else { return nil }
        let users = item["users"].array ?? []
        let firstUser = users.first ?? JSON(NSNull())
        let first = firstUser["nickname"].string ?? "有人"
        let count = item["counts"].int ?? users.count
        let name = count > 1 ? "\(first) 等 \(count) 人" : first
        let subject = item["item"]["title"].string ?? item["item"]["business"].string ?? ""
        let time = item["like_time"].int ?? 0
        return NoticeItem(
            id: "like-\(id)",
            name: name,
            face: BiliClient.https(firstUser["avatar"].string ?? ""),
            title: "赞了你",
            subtitle: subject,
            time: time,
            timeText: clock(time)
        )
    }

    private static func system(_ item: JSON, index: Int) -> NoticeItem? {
        let title = item["title"].string ?? ""
        let content = systemText(item["content"].string ?? "")
        guard !title.isEmpty || !content.isEmpty else { return nil }
        let id = item["id"].int ?? index
        let timeText = item["time_at"].string ?? ""
        return NoticeItem(
            id: "sys-\(id)",
            name: "系统通知",
            face: "",
            title: title.isEmpty ? "系统通知" : title,
            subtitle: content,
            time: item["cursor"].int ?? 0,
            timeText: timeText
        )
    }

    private static func session(_ item: JSON) -> ChatSession? {
        let id = item["talker_id"].int ?? item["talker_uid"].int ?? 0
        guard id > 0 else { return nil }
        let last = item["last_msg"]
        let type = last["msg_type"].int ?? 1
        let preview = text(content: last["content"], msgType: type).text
        return ChatSession(
            id: id,
            name: "用户 \(id)",
            face: "",
            preview: preview,
            time: item["session_ts"].int ?? last["timestamp"].int ?? 0,
            unread: item["unread_count"].int ?? 0,
            seqno: item["max_seqno"].int ?? last["msg_seqno"].int ?? 0
        )
    }

    private static func line(from item: JSON, mine: Int) -> ChatLine? {
        let seq = item["msg_seqno"].int ?? item["msg_key"].int ?? 0
        guard seq > 0 else { return nil }
        let type = item["msg_type"].int ?? 1
        let parsed = text(content: item["content"], msgType: type)
        let sender = item["sender_uid"].int ?? 0
        return ChatLine(
            id: seq,
            text: parsed.text,
            mine: mine > 0 && sender == mine,
            time: item["timestamp"].int ?? 0,
            system: parsed.system || type >= 10
        )
    }

    private static func text(content: JSON, msgType: Int) -> (text: String, system: Bool) {
        if msgType == 5 { return ("撤回了一条消息", true) }
        if msgType == 2 { return ("[图片]", false) }
        if let direct = content["content"].string, !direct.isEmpty {
            return (direct, msgType >= 10)
        }
        let raw = content.string ?? ""
        if let data = raw.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let value = object["content"] as? String, !value.isEmpty { return (value, msgType >= 10) }
            if let value = object["title"] as? String, !value.isEmpty { return (value, msgType >= 10) }
        }
        if raw.isEmpty { return (msgType == 1 ? "" : "[消息]", msgType >= 10) }
        return (raw, msgType >= 10)
    }

    private static func systemText(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let web = object["web"] as? String, !web.isEmpty else { return raw }
        return web
    }

    private static func flag(_ value: JSON, fallback: Bool) -> Bool {
        if let flag = value.int { return flag != 0 }
        if let flag = value.bool { return flag }
        return fallback
    }
}

enum MessageRequestProof {
    struct Case: Sendable {
        var name: String
        var method: String
        var host: String
        var path: String
        var body: String
        var expect: String
        var csrf: Bool
    }

    static func cases() -> [Case] {
        let csrf = "jct-token"
        let send = MessageRequest.send(sender: 42, receiver: 7, text: "你好", device: "device-1", timestamp: 1_700_000_000, csrf: csrf)!
        let quoted = MessageRequest.send(sender: 42, receiver: 7, text: "a\"b", device: "device-1", timestamp: 1_700_000_000, csrf: csrf)!
        return [
            check("reply", MessageRequest.reply(), "build=0&mobi_app=web&platform=web&web_location=333.40164", csrf: false),
            check("reply-page", MessageRequest.reply(cursor: 9, time: 1_700_000_000), "build=0&id=9&mobi_app=web&platform=web&reply_time=1700000000&web_location=333.40164", csrf: false),
            check("at", MessageRequest.at(), "build=0&mobi_app=web&platform=web&web_location=333.40164", csrf: false),
            check("at-page", MessageRequest.at(cursor: 9, time: 1_700_000_000), "at_time=1700000000&build=0&id=9&mobi_app=web&platform=web&web_location=333.40164", csrf: false),
            check("like", MessageRequest.like(), "build=0&mobi_app=web&platform=web&web_location=333.40164", csrf: false),
            check("like-page", MessageRequest.like(cursor: 9, time: 1_700_000_000), "build=0&id=9&like_time=1700000000&mobi_app=web&platform=web&web_location=333.40164", csrf: false),
            check("system", MessageRequest.system(), "build=0&mobi_app=web&page_size=20&web_location=333.40164", csrf: false),
            check("system-page", MessageRequest.system(cursor: 99), "build=0&cursor=99&mobi_app=web&page_size=20&web_location=333.40164", csrf: false),
            check("unread", MessageRequest.unread(), "build=0&mobi_app=web&web_location=333.1365", csrf: false),
            check("sessions", MessageRequest.sessions(), "build=0&group_fold=1&mobi_app=web&session_type=1&sort_rule=2&unfollow_fold=0", csrf: false),
            check("sessions-page", MessageRequest.sessions(endTs: 1_700_000_000), "build=0&end_ts=1700000000&group_fold=1&mobi_app=web&session_type=1&sort_rule=2&unfollow_fold=0", csrf: false),
            check("cards", MessageRequest.cards(ids: [7, 8]), "build=0&mobi_app=web&uids=7%2C8", csrf: false),
            check("messages", MessageRequest.messages(talker: 7), "build=0&mobi_app=web&sender_device_id=1&session_type=1&size=20&talker_id=7", csrf: false),
            check("messages-older", MessageRequest.messages(talker: 7, endSeqno: 100), "build=0&end_seqno=100&mobi_app=web&sender_device_id=1&session_type=1&size=20&talker_id=7", csrf: false),
            check("ack", MessageRequest.ack(talker: 7, seqno: 99, csrf: csrf), "ack_seqno=99&build=0&csrf=jct-token&csrf_token=jct-token&mobi_app=web&session_type=1&talker_id=7", csrf: true),
            check("send", send, "build=0&csrf=jct-token&csrf_token=jct-token&from_firework=0&mobi_app=web&msg%5Bcontent%5D=%7B%22content%22%3A%22%E4%BD%A0%E5%A5%BD%22%7D&msg%5Bdev_id%5D=device-1&msg%5Bmsg_status%5D=0&msg%5Bmsg_type%5D=1&msg%5Bnew_face_version%5D=1&msg%5Breceiver_id%5D=7&msg%5Breceiver_type%5D=1&msg%5Bsender_uid%5D=42&msg%5Btimestamp%5D=1700000000", csrf: true),
            check("send-quote", quoted, "build=0&csrf=jct-token&csrf_token=jct-token&from_firework=0&mobi_app=web&msg%5Bcontent%5D=%7B%22content%22%3A%22a%5C%22b%22%7D&msg%5Bdev_id%5D=device-1&msg%5Bmsg_status%5D=0&msg%5Bmsg_type%5D=1&msg%5Bnew_face_version%5D=1&msg%5Breceiver_id%5D=7&msg%5Breceiver_type%5D=1&msg%5Bsender_uid%5D=42&msg%5Btimestamp%5D=1700000000", csrf: true)
        ]
    }

    static func failures() -> [String] {
        var issues: [String] = []
        for item in cases() {
            if item.body != item.expect || item.method.isEmpty || item.path.isEmpty || item.host.isEmpty {
                issues.append("\(item.name) body \(item.body)")
            }
            if item.csrf {
                if !item.body.contains("csrf=jct-token") { issues.append("\(item.name) csrf") }
            } else if item.body.contains("csrf=") {
                issues.append("\(item.name) unexpected csrf")
            }
        }
        if MessageRequest.send(sender: 42, receiver: 7, text: "  ", device: "device-1", timestamp: 1, csrf: "jct-token") != nil {
            issues.append("blank text was signed")
        }
        if MessageRequest.send(sender: 42, receiver: 7, text: "你好", device: "device-1", timestamp: 1, csrf: "") != nil {
            issues.append("empty csrf was signed")
        }
        if MessageRequest.reply().host != MessageRequest.api || MessageRequest.system().host != MessageRequest.message || MessageRequest.sessions().host != MessageRequest.vc {
            issues.append("host")
        }
        if MessageRequest.send(sender: 42, receiver: 7, text: "你好", device: "device-1", timestamp: 1, csrf: "jct-token")?.method != "POST" {
            issues.append("send method")
        }
        return issues
    }

    static func writeAndExit() -> Never {
        let found = cases()
        let issues = failures()
        let payload: [String: Any] = [
            "ok": issues.isEmpty,
            "checked": found.count,
            "failures": issues,
            "cases": found.map { item in
                [
                    "name": item.name,
                    "method": item.method,
                    "host": item.host,
                    "path": item.path,
                    "body": item.body,
                    "expect": item.expect,
                    "csrf": item.csrf
                ] as [String: Any]
            }
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        try? data.write(to: LaunchClock.documents.appendingPathComponent("message-proof.json"), options: .atomic)
        if let text = String(data: data, encoding: .utf8) {
            print("MESSAGE_PROOF_BEGIN")
            print(text)
            print("MESSAGE_PROOF_END")
            fflush(stdout)
        }
        exit(issues.isEmpty ? 0 : 1)
    }

    private static func check(_ name: String, _ call: MessageCall, _ expect: String, csrf: Bool) -> Case {
        Case(name: name, method: call.method, host: call.host, path: call.path, body: call.body, expect: expect, csrf: csrf)
    }
}

enum MessageUIProof {
    static func record(_ payload: [String: Any]) {
        guard let screen = LaunchMode.screen else { return }
        guard screen == "messages" || screen == "guest-messages" || screen == "guest-chat" else { return }
        var body = payload
        body["screen"] = screen
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { return }
        try? data.write(to: LaunchClock.documents.appendingPathComponent("message-ui.json"), options: .atomic)
    }
}
