import Darwin
import Foundation

/// Public user-space calls, plus the follow write, before they touch the network.
enum SpaceRequest {
    static func profile(mid: Int) -> SignedForm {
        SignedForm(method: "GET", path: "/x/web-interface/card", fields: [
            "mid": "\(mid)"
        ])
    }

    /// `order` is `pubdate` (newest) or `click` (hottest). WBI is added at send time.
    static func videos(mid: Int, page: Int, order: String) -> SignedForm {
        SignedForm(method: "GET", path: "/x/space/wbi/arc/search", fields: [
            "mid": "\(mid)",
            "pn": "\(max(1, page))",
            "ps": "30",
            "order": order
        ])
    }

    static func dynamics(mid: Int, offset: String) -> SignedForm {
        SignedForm(method: "GET", path: "/x/polymer/web-dynamic/v1/feed/space", fields: [
            "host_mid": "\(mid)",
            "offset": offset,
            "timezone_offset": "-480",
            "features": "itemOpusStyle"
        ])
    }

    static func folders(mid: Int) -> SignedForm {
        SignedForm(method: "GET", path: "/x/v3/fav/folder/created/list-all", fields: [
            "up_mid": "\(mid)"
        ])
    }

    static func bangumi(mid: Int, page: Int) -> SignedForm {
        SignedForm(method: "GET", path: "/x/space/bangumi/follow/list", fields: [
            "vmid": "\(mid)",
            "type": "1",
            "follow_status": "0",
            "pn": "\(max(1, page))",
            "ps": "20"
        ])
    }

    static func series(mid: Int, page: Int) -> SignedForm {
        SignedForm(method: "GET", path: "/x/polymer/web-space/seasons_series_list", fields: [
            "mid": "\(mid)",
            "page_num": "\(max(1, page))",
            "page_size": "20"
        ])
    }

    /// `follow` true posts `act=1`. Unfollow posts `act=2`.
    static func relation(mid: Int, follow: Bool, csrf: String) -> SignedForm {
        SignedForm(method: "POST", path: "/x/relation/modify", fields: [
            "fid": "\(mid)",
            "act": follow ? "1" : "2",
            "re_src": "11",
            "csrf": csrf
        ])
    }

    static func videoOrder(for title: String) -> String {
        title == "最热" ? "click" : "pubdate"
    }
}

enum SpaceRequestProof {
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
            check("profile", SpaceRequest.profile(mid: 42), "mid=42", csrf: false),
            check("videos-new", SpaceRequest.videos(mid: 42, page: 1, order: "pubdate"), "mid=42&order=pubdate&pn=1&ps=30", csrf: false),
            check("videos-hot", SpaceRequest.videos(mid: 42, page: 2, order: "click"), "mid=42&order=click&pn=2&ps=30", csrf: false),
            check("dynamics", SpaceRequest.dynamics(mid: 42, offset: ""), "features=itemOpusStyle&host_mid=42&offset=&timezone_offset=-480", csrf: false),
            check("folders", SpaceRequest.folders(mid: 42), "up_mid=42", csrf: false),
            check("bangumi", SpaceRequest.bangumi(mid: 42, page: 1), "follow_status=0&pn=1&ps=20&type=1&vmid=42", csrf: false),
            check("series", SpaceRequest.series(mid: 42, page: 1), "mid=42&page_num=1&page_size=20", csrf: false),
            check("follow", SpaceRequest.relation(mid: 42, follow: true, csrf: csrf), "act=1&csrf=jct-token&fid=42&re_src=11", csrf: true),
            check("unfollow", SpaceRequest.relation(mid: 42, follow: false, csrf: csrf), "act=2&csrf=jct-token&fid=42&re_src=11", csrf: true)
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
        let empty = SpaceRequest.relation(mid: 1, follow: true, csrf: "")
        if empty.hasCSRF || AccountRequest.isReady(empty) {
            issues.append("empty csrf was treated as signed")
        }
        if SpaceRequest.videoOrder(for: "最热") != "click" || SpaceRequest.videoOrder(for: "最新") != "pubdate" {
            issues.append("order map")
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
        try? data.write(to: LaunchClock.documents.appendingPathComponent("space-proof.json"), options: .atomic)
        if let text = String(data: data, encoding: .utf8) {
            print("SPACE_PROOF_BEGIN")
            print(text)
            print("SPACE_PROOF_END")
            fflush(stdout)
        }
        exit(issues.isEmpty ? 0 : 1)
    }

    private static func check(_ name: String, _ form: SignedForm, _ expect: String, csrf: Bool) -> Case {
        Case(name: name, method: form.method, path: form.path, body: form.body, expect: expect, csrf: csrf)
    }
}

enum SpaceUIProof {
    static func record(_ payload: [String: Any]) {
        guard let screen = LaunchMode.screen else { return }
        guard screen == "space" || screen.hasPrefix("space-") else { return }
        var body = payload
        body["screen"] = screen
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { return }
        try? data.write(to: LaunchClock.documents.appendingPathComponent("space-ui.json"), options: .atomic)
    }
}
