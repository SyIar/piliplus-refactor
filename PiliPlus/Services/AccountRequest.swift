import Darwin
import Foundation

/// A Bilibili account call before it touches the network.
/// Writes are form posts sorted and percent-encoded the same way as `postForm`.
/// `csrf` is the bili_jct token those writes must carry.
struct SignedForm: Equatable, Sendable {
    var method: String
    var path: String
    var fields: [String: String]

    var body: String {
        fields.keys.sorted().map { key in
            "\(PercentEncoding.encodeURIComponent(key))=\(PercentEncoding.encodeURIComponent(fields[key, default: ""]))"
        }.joined(separator: "&")
    }

    var hasCSRF: Bool {
        let value = fields["csrf"] ?? ""
        return !value.isEmpty
    }

    var endpoint: URL? {
        let base = "https://api.bilibili.com" + path
        if method == "GET" {
            if fields.isEmpty { return URL(string: base) }
            return URL(string: base + "?" + body)
        }
        return URL(string: base)
    }
}

enum AccountRequest {
    static func historyList(max: Int, viewAt: Int, business: String = "") -> SignedForm {
        SignedForm(method: "GET", path: "/x/web-interface/history/cursor", fields: [
            "max": "\(max)",
            "view_at": "\(viewAt)",
            "business": business,
            "ps": "20"
        ])
    }

    static func deleteHistory(aid: Int, csrf: String) -> SignedForm {
        write("/x/v2/history/delete", [
            "kid": "archive_\(aid)",
            "csrf": csrf
        ])
    }

    static func clearHistory(csrf: String) -> SignedForm {
        write("/x/v2/history/clear", ["csrf": csrf])
    }

    static func historyShadow() -> SignedForm {
        SignedForm(method: "GET", path: "/x/v2/history/shadow", fields: [:])
    }

    static func pauseHistory(paused: Bool, csrf: String) -> SignedForm {
        write("/x/v2/history/shadow/set", [
            "switch": paused ? "true" : "false",
            "csrf": csrf
        ])
    }

    static func watchLaterList() -> SignedForm {
        SignedForm(method: "GET", path: "/x/v2/history/toview", fields: [:])
    }

    static func addWatchLater(aid: Int, csrf: String) -> SignedForm {
        write("/x/v2/history/toview/add", [
            "aid": "\(aid)",
            "csrf": csrf
        ])
    }

    static func removeWatchLater(aid: Int, csrf: String) -> SignedForm {
        write("/x/v2/history/toview/del", [
            "aid": "\(aid)",
            "csrf": csrf
        ])
    }

    static func clearWatchLater(csrf: String) -> SignedForm {
        write("/x/v2/history/toview/clear", ["csrf": csrf])
    }

    static func createdFolders(mid: Int, rid: Int? = nil) -> SignedForm {
        var fields = ["up_mid": "\(mid)"]
        if let rid, rid > 0 {
            fields["rid"] = "\(rid)"
            fields["type"] = "2"
        }
        return SignedForm(method: "GET", path: "/x/v3/fav/folder/created/list-all", fields: fields)
    }

    static func folderContents(mediaID: Int, page: Int) -> SignedForm {
        SignedForm(method: "GET", path: "/x/v3/fav/resource/list", fields: [
            "media_id": "\(mediaID)",
            "pn": "\(page)",
            "ps": "20"
        ])
    }

    static func dealFavorite(aid: Int, add: [Int], remove: [Int], csrf: String) -> SignedForm {
        write("/x/v3/fav/resource/deal", [
            "rid": "\(aid)",
            "type": "2",
            "add_media_ids": add.sorted().map(String.init).joined(separator: ","),
            "del_media_ids": remove.sorted().map(String.init).joined(separator: ","),
            "csrf": csrf
        ])
    }

    static func createFolder(title: String, csrf: String) -> SignedForm {
        write("/x/v3/fav/folder/add", [
            "title": title,
            "privacy": "0",
            "csrf": csrf
        ])
    }

    /// `liked` true sends `like=1`. Cancelling sends `like=2`.
    static func like(aid: Int, liked: Bool, csrf: String) -> SignedForm {
        write("/x/web-interface/archive/like", [
            "aid": "\(aid)",
            "like": liked ? "1" : "2",
            "csrf": csrf
        ])
    }

    /// `multiply` is only 1 or 2. `alsoLike` sets `select_like`.
    static func coin(aid: Int, multiply: Int, alsoLike: Bool, csrf: String) -> SignedForm {
        let count = multiply == 2 ? 2 : 1
        return write("/x/web-interface/coin/add", [
            "aid": "\(aid)",
            "multiply": "\(count)",
            "select_like": alsoLike ? "1" : "0",
            "csrf": csrf
        ])
    }

    static func triple(aid: Int, csrf: String) -> SignedForm {
        write("/x/web-interface/archive/like/triple", [
            "aid": "\(aid)",
            "csrf": csrf
        ])
    }

    static func isReady(_ form: SignedForm) -> Bool {
        form.method == "POST" && form.hasCSRF && form.endpoint != nil
    }

    private static func write(_ path: String, _ fields: [String: String]) -> SignedForm {
        SignedForm(method: "POST", path: path, fields: fields)
    }
}

/// Pure checks for the form builder. The simulator launches `-screen accountProof`
/// and the pass script rejects the run when any case drifts.
enum AccountRequestProof {
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
            check("like", AccountRequest.like(aid: 42, liked: true, csrf: csrf), "aid=42&csrf=jct-token&like=1", csrf: true),
            check("unlike", AccountRequest.like(aid: 42, liked: false, csrf: csrf), "aid=42&csrf=jct-token&like=2", csrf: true),
            check("coin-2-like", AccountRequest.coin(aid: 7, multiply: 2, alsoLike: true, csrf: csrf), "aid=7&csrf=jct-token&multiply=2&select_like=1", csrf: true),
            check("coin-1", AccountRequest.coin(aid: 7, multiply: 1, alsoLike: false, csrf: csrf), "aid=7&csrf=jct-token&multiply=1&select_like=0", csrf: true),
            check("coin-clamp", AccountRequest.coin(aid: 7, multiply: 5, alsoLike: false, csrf: csrf), "aid=7&csrf=jct-token&multiply=1&select_like=0", csrf: true),
            check("triple", AccountRequest.triple(aid: 9, csrf: csrf), "aid=9&csrf=jct-token", csrf: true),
            check("history-delete", AccountRequest.deleteHistory(aid: 100, csrf: csrf), "csrf=jct-token&kid=archive_100", csrf: true),
            check("history-clear", AccountRequest.clearHistory(csrf: csrf), "csrf=jct-token", csrf: true),
            check("history-pause", AccountRequest.pauseHistory(paused: true, csrf: csrf), "csrf=jct-token&switch=true", csrf: true),
            check("history-resume", AccountRequest.pauseHistory(paused: false, csrf: csrf), "csrf=jct-token&switch=false", csrf: true),
            check("later-add", AccountRequest.addWatchLater(aid: 5, csrf: csrf), "aid=5&csrf=jct-token", csrf: true),
            check("later-del", AccountRequest.removeWatchLater(aid: 5, csrf: csrf), "aid=5&csrf=jct-token", csrf: true),
            check("later-clear", AccountRequest.clearWatchLater(csrf: csrf), "csrf=jct-token", csrf: true),
            check("fav-deal", AccountRequest.dealFavorite(aid: 8, add: [22, 11], remove: [33], csrf: csrf), "add_media_ids=11%2C22&csrf=jct-token&del_media_ids=33&rid=8&type=2", csrf: true),
            check("fav-add", AccountRequest.createFolder(title: "学习", csrf: csrf), "csrf=jct-token&privacy=0&title=%E5%AD%A6%E4%B9%A0", csrf: true),
            check("history-list", AccountRequest.historyList(max: 0, viewAt: 0), "business=&max=0&ps=20&view_at=0", csrf: false),
            check("history-page", AccountRequest.historyList(max: 900, viewAt: 1_600_000_000, business: "archive"), "business=archive&max=900&ps=20&view_at=1600000000", csrf: false),
            check("history-shadow", AccountRequest.historyShadow(), "", csrf: false),
            check("later-list", AccountRequest.watchLaterList(), "", csrf: false),
            check("fav-folders", AccountRequest.createdFolders(mid: 99), "up_mid=99", csrf: false),
            check("fav-folders-rid", AccountRequest.createdFolders(mid: 99, rid: 8), "rid=8&type=2&up_mid=99", csrf: false),
            check("fav-contents", AccountRequest.folderContents(mediaID: 11, page: 2), "media_id=11&pn=2&ps=20", csrf: false)
        ]
    }

    static func failures() -> [String] {
        var issues: [String] = []
        for item in cases() {
            if item.body != item.expect {
                issues.append("\(item.name) body \(item.body) != \(item.expect)")
            }
            if item.csrf {
                if !item.body.contains("csrf=jct-token") {
                    issues.append("\(item.name) missing csrf")
                }
                let form = SignedForm(method: item.method, path: item.path, fields: ["csrf": "jct-token"])
                if !AccountRequest.isReady(SignedForm(method: "POST", path: item.path, fields: ["csrf": "jct-token", "aid": "1"])) {
                    issues.append("\(item.name) ready")
                }
                _ = form
            } else if item.body.contains("csrf=") {
                issues.append("\(item.name) unexpected csrf")
            }
        }
        let empty = AccountRequest.like(aid: 1, liked: true, csrf: "")
        if empty.fields["csrf"] != "" || empty.hasCSRF || AccountRequest.isReady(empty) {
            issues.append("empty csrf was treated as signed")
        }
        if AccountRequest.like(aid: 1, liked: true, csrf: "jct-token").endpoint == nil {
            issues.append("like endpoint")
        }
        let page = AccountRequest.historyList(max: 900, viewAt: 1_600_000_000, business: "archive")
        if page.endpoint?.absoluteString.contains("view_at=1600000000") != true {
            issues.append("history page query")
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
        let url = LaunchClock.documents.appendingPathComponent("account-proof.json")
        try? data.write(to: url, options: .atomic)
        if let text = String(data: data, encoding: .utf8) {
            print("ACCOUNT_PROOF_BEGIN")
            print(text)
            print("ACCOUNT_PROOF_END")
            fflush(stdout)
        }
        exit(issues.isEmpty ? 0 : 1)
    }

    private static func check(_ name: String, _ form: SignedForm, _ expect: String, csrf: Bool) -> Case {
        Case(name: name, method: form.method, path: form.path, body: form.body, expect: expect, csrf: csrf)
    }
}

enum AccountUIProof {
    static func record(_ payload: [String: Any]) {
        guard let screen = LaunchMode.screen else { return }
        let watched = ["history", "later", "fav", "favsheet"].contains(screen) || screen.hasPrefix("guest-")
        guard watched else { return }
        var body = payload
        body["screen"] = screen
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { return }
        let url = LaunchClock.documents.appendingPathComponent("account-ui.json")
        try? data.write(to: url, options: .atomic)
    }
}
