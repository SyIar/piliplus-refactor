import Darwin
import Foundation

/// Followed-dynamics, comment, and search calls before they touch the network.
enum SocialRequest {
    static func followFeed(type: String, offset: String) -> SignedForm {
        SignedForm(method: "GET", path: "/x/polymer/web-dynamic/v1/feed/all", fields: [
            "timezone_offset": "-480",
            "type": type,
            "offset": offset,
            "features": "itemOpusStyle"
        ])
    }

    static func replyList(oid: Int, sort: Int, page: Int) -> SignedForm {
        SignedForm(method: "GET", path: "/x/v2/reply", fields: [
            "type": "1",
            "oid": "\(oid)",
            "sort": "\(sort)",
            "pn": "\(max(1, page))",
            "ps": "20"
        ])
    }

    static func replyThread(oid: Int, root: Int, page: Int) -> SignedForm {
        SignedForm(method: "GET", path: "/x/v2/reply/reply", fields: [
            "type": "1",
            "oid": "\(oid)",
            "root": "\(root)",
            "pn": "\(max(1, page))",
            "ps": "10"
        ])
    }

    /// Top-level send leaves `root` and `parent` at 0, so they stay off the form.
    static func replyAdd(oid: Int, message: String, root: Int, parent: Int, csrf: String) -> SignedForm {
        var fields = [
            "type": "1",
            "oid": "\(oid)",
            "message": message,
            "plat": "1",
            "csrf": csrf
        ]
        if root > 0 { fields["root"] = "\(root)" }
        if parent > 0 { fields["parent"] = "\(parent)" }
        return SignedForm(method: "POST", path: "/x/v2/reply/add", fields: fields)
    }

    static func search(type: String, keyword: String, page: Int, order: String = "", duration: Int = 0, tid: Int = 0) -> SignedForm {
        var fields = [
            "search_type": type,
            "keyword": keyword,
            "page": "\(max(1, page))"
        ]
        if !order.isEmpty { fields["order"] = order }
        if duration > 0 { fields["duration"] = "\(duration)" }
        if tid > 0 { fields["tids"] = "\(tid)" }
        return SignedForm(method: "GET", path: "/x/web-interface/search/type", fields: fields)
    }

    static func searchType(for tab: String) -> String {
        switch tab {
        case "番剧": return "media_bangumi"
        case "影视": return "media_ft"
        case "直播间": return "live_room"
        case "用户": return "bili_user"
        case "专栏": return "article"
        default: return "video"
        }
    }

    static func dynamicType(for tab: String) -> String {
        switch tab {
        case "投稿": return "video"
        case "番剧": return "pgc"
        case "专栏": return "article"
        default: return "all"
        }
    }
}

enum SocialRequestProof {
    struct Case: Sendable {
        var name: String
        var method: String
        var path: String
        var body: String
        var expect: String
        var csrf: Bool
    }

    static func cases() -> [Case] {
        let csrf = "jct-token"
        return [
            check("feed", SocialRequest.followFeed(type: "all", offset: ""), "features=itemOpusStyle&offset=&timezone_offset=-480&type=all", csrf: false),
            check("feed-video", SocialRequest.followFeed(type: "video", offset: "cursor"), "features=itemOpusStyle&offset=cursor&timezone_offset=-480&type=video", csrf: false),
            check("reply-hot", SocialRequest.replyList(oid: 42, sort: 1, page: 1), "oid=42&pn=1&ps=20&sort=1&type=1", csrf: false),
            check("reply-time", SocialRequest.replyList(oid: 42, sort: 0, page: 2), "oid=42&pn=2&ps=20&sort=0&type=1", csrf: false),
            check("reply-thread", SocialRequest.replyThread(oid: 42, root: 9, page: 1), "oid=42&pn=1&ps=10&root=9&type=1", csrf: false),
            check("reply-add", SocialRequest.replyAdd(oid: 42, message: "你好", root: 0, parent: 0, csrf: csrf), "csrf=jct-token&message=%E4%BD%A0%E5%A5%BD&oid=42&plat=1&type=1", csrf: true),
            check("reply-to", SocialRequest.replyAdd(oid: 42, message: "你好", root: 9, parent: 9, csrf: csrf), "csrf=jct-token&message=%E4%BD%A0%E5%A5%BD&oid=42&parent=9&plat=1&root=9&type=1", csrf: true),
            check("search-video", SocialRequest.search(type: "video", keyword: "原神", page: 1), "keyword=%E5%8E%9F%E7%A5%9E&page=1&search_type=video", csrf: false),
            check("search-filter", SocialRequest.search(type: "video", keyword: "原神", page: 1, order: "click", duration: 1, tid: 4), "duration=1&keyword=%E5%8E%9F%E7%A5%9E&order=click&page=1&search_type=video&tids=4", csrf: false),
            check("search-user", SocialRequest.search(type: "bili_user", keyword: "罗翔", page: 1), "keyword=%E7%BD%97%E7%BF%94&page=1&search_type=bili_user", csrf: false),
            check("search-bangumi", SocialRequest.search(type: "media_bangumi", keyword: "鬼灭之刃", page: 1), "keyword=%E9%AC%BC%E7%81%AD%E4%B9%8B%E5%88%83&page=1&search_type=media_bangumi", csrf: false),
            check("search-live", SocialRequest.search(type: "live_room", keyword: "原神", page: 1), "keyword=%E5%8E%9F%E7%A5%9E&page=1&search_type=live_room", csrf: false),
            check("search-article", SocialRequest.search(type: "article", keyword: "原神", page: 1), "keyword=%E5%8E%9F%E7%A5%9E&page=1&search_type=article", csrf: false)
        ]
    }

    static func failures() -> [String] {
        var issues: [String] = []
        for item in cases() {
            if item.body != item.expect || item.method.isEmpty || item.path.isEmpty {
                issues.append("\(item.name) body \(item.body)")
            }
            if item.csrf {
                if !item.body.contains("csrf=jct-token") { issues.append("\(item.name) csrf") }
                if !AccountRequest.isReady(SignedForm(method: "POST", path: item.path, fields: ["csrf": "jct-token"])) {
                    issues.append("\(item.name) ready")
                }
            } else if item.body.contains("csrf=") {
                issues.append("\(item.name) unexpected csrf")
            }
        }
        let empty = SocialRequest.replyAdd(oid: 1, message: "a", root: 0, parent: 0, csrf: "")
        if empty.hasCSRF || AccountRequest.isReady(empty) {
            issues.append("empty csrf was treated as signed")
        }
        if SocialRequest.searchType(for: "用户") != "bili_user" || SocialRequest.dynamicType(for: "投稿") != "video" {
            issues.append("tab map")
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
                    "path": item.path,
                    "body": item.body,
                    "expect": item.expect,
                    "csrf": item.csrf
                ] as [String: Any]
            }
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        try? data.write(to: LaunchClock.documents.appendingPathComponent("social-proof.json"), options: .atomic)
        if let text = String(data: data, encoding: .utf8) {
            print("SOCIAL_PROOF_BEGIN")
            print(text)
            print("SOCIAL_PROOF_END")
            fflush(stdout)
        }
        exit(issues.isEmpty ? 0 : 1)
    }

    private static func check(_ name: String, _ form: SignedForm, _ expect: String, csrf: Bool) -> Case {
        Case(name: name, method: form.method, path: form.path, body: form.body, expect: expect, csrf: csrf)
    }
}

enum SocialUIProof {
    static func record(_ payload: [String: Any]) {
        guard let screen = LaunchMode.screen else { return }
        let watched = screen == "dynamics" || screen == "guest-dynamics" || screen == "comments" || screen.hasPrefix("search-")
        guard watched else { return }
        var body = payload
        body["screen"] = screen
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { return }
        let name = screen == "comments" || screen.hasPrefix("search-") ? "social-ui.json" : "social-ui.json"
        try? data.write(to: LaunchClock.documents.appendingPathComponent(name), options: .atomic)
    }
}
