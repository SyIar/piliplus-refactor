import Darwin
import Foundation

struct LiveOffer: Equatable, Sendable {
    var url: String
    var alternates: [String]
    var protocolName: String
    var qualities: [String]
    var qualityIDs: [Int]
    var selectedQN: Int
    var selectedName: String
}

struct LiveDanmuHost: Equatable, Sendable {
    var host: String
    var wssPort: Int
}

struct LiveDanmuInfo: Equatable, Sendable {
    var token: String
    var hosts: [LiveDanmuHost]
}

/// Live list, play, danmaku, and send calls before they touch the network.
enum LiveRequest {
    static func recommend(page: Int) -> SignedForm {
        SignedForm(method: "GET", path: "/xlive/web-interface/v1/second/getUserRecommend", fields: [
            "page": "\(max(1, page))",
            "page_size": "30",
            "platform": "web"
        ])
    }

    /// Homepage rail. Rooms sit in `data.recommend_room_list`.
    static func moreRecommend() -> SignedForm {
        SignedForm(method: "GET", path: "/xlive/web-interface/v1/webMain/getMoreRecList", fields: [
            "platform": "web",
            "web_location": "333.1007"
        ])
    }

    static func area(parent: Int, page: Int, sort: String = "") -> SignedForm {
        SignedForm(method: "GET", path: "/xlive/web-interface/v1/second/getList", fields: [
            "platform": "web",
            "parent_area_id": "\(parent)",
            "area_id": "0",
            "sort_type": sort,
            "page": "\(max(1, page))"
        ])
    }

    /// App homepage feed. Rooms sit in `card_list[].card_data.small_card_v1`.
    static func appFeed(page: Int) -> SignedForm {
        SignedForm(method: "GET", path: "/xlive/app-interface/v2/index/feed", fields: appFields(page: page, extra: [:]))
    }

    /// Room list for one parent area. `/room/v1/Area/getList` only returns the area tree.
    static func roomList(parent: Int, page: Int) -> SignedForm {
        SignedForm(method: "GET", path: "/room/v3/Area/getRoomList", fields: [
            "platform": "web",
            "parent_area_id": "\(parent)",
            "area_id": "0",
            "page": "\(max(1, page))",
            "page_size": "30",
            "sort_type": "online"
        ])
    }

    /// App area list. Rooms sit in `data.list`.
    static func appArea(parent: Int, page: Int) -> SignedForm {
        SignedForm(method: "GET", path: "/xlive/app-interface/v2/second/getList", fields: appFields(page: page, extra: [
            "area_id": "0",
            "parent_area_id": "\(parent)",
            "module_select": "0",
            "page_size": "20",
            "qn": "0",
            "sort_type": "online",
            "tag_version": "1"
        ]))
    }

    private static func appFields(page: Int, extra: [String: String]) -> [String: String] {
        var fields = [
            "actionKey": "appkey",
            "build": "8430300",
            "c_locale": "zh_CN",
            "channel": "master",
            "device": "android",
            "device_name": "android",
            "device_type": "0",
            "disable_rcmd": "0",
            "fnval": "912",
            "https_url_req": "1",
            "mobi_app": "android",
            "network": "wifi",
            "page": "\(max(1, page))",
            "platform": "android",
            "s_locale": "zh_CN",
            "scale": "2",
            "statistics": #"{"appId":1,"platform":3,"version":"8.43.0","abtest":""}"#,
            "version": "8.43.0"
        ]
        for (key, value) in extra { fields[key] = value }
        return fields
    }

    static func roomInfo(room: Int) -> SignedForm {
        SignedForm(method: "GET", path: "/xlive/web-room/v1/index/getH5InfoByRoom", fields: [
            "room_id": "\(room)"
        ])
    }

    /// `protocol`/`format`/`codec` ask for both HLS and FLV. The parser prefers HLS.
    static func playInfo(room: Int, qn: Int) -> SignedForm {
        SignedForm(method: "GET", path: "/xlive/web-room/v2/index/getRoomPlayInfo", fields: [
            "room_id": "\(room)",
            "protocol": "0,1",
            "format": "0,1,2",
            "codec": "0,1,2",
            "qn": "\(qn)",
            "platform": "web",
            "ptype": "8",
            "dolby": "5",
            "panorama": "1",
            "web_location": "444.8"
        ])
    }

    static func danmuInfo(room: Int) -> SignedForm {
        SignedForm(method: "GET", path: "/xlive/web-room/v1/index/getDanmuInfo", fields: [
            "id": "\(room)",
            "web_location": "444.8"
        ])
    }

    static func send(room: Int, message: String, csrf: String, rnd: Int) -> SignedForm {
        SignedForm(method: "POST", path: "/msg/send", fields: [
            "bubble": "0",
            "msg": message,
            "color": "16777215",
            "mode": "1",
            "room_type": "0",
            "fontsize": "25",
            "rnd": "\(rnd)",
            "roomid": "\(room)",
            "csrf": csrf,
            "csrf_token": csrf
        ])
    }

    static func qualityName(_ qn: Int) -> String {
        switch qn {
        case 30000: "杜比"
        case 20000: "4K"
        case 10000: "原画"
        case 400: "蓝光"
        case 250: "超清"
        case 150: "高清"
        case 80: "流畅"
        default: "清晰"
        }
    }

    static func qn(for name: String) -> Int {
        switch name {
        case "杜比": 30000
        case "4K": 20000
        case "原画": 10000
        case "蓝光": 400
        case "超清": 250
        case "高清": 150
        case "流畅": 80
        default: 10000
        }
    }

    /// Parent area ids used by `/xlive/web-interface/v1/second/getList`.
    static func parentID(for area: String) -> Int {
        switch area {
        case "娱乐": 1
        case "网游": 2
        case "手游": 3
        case "电台": 5
        case "单机": 6
        case "虚拟主播": 9
        case "生活": 10
        case "知识": 11
        case "赛事": 13
        default: 0
        }
    }
}

enum LiveRequestProof {
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
            check("recommend", LiveRequest.recommend(page: 1), "page=1&page_size=30&platform=web", csrf: false),
            check("area", LiveRequest.area(parent: 9, page: 1), "area_id=0&page=1&parent_area_id=9&platform=web&sort_type=", csrf: false),
            check("room", LiveRequest.roomInfo(room: 42), "room_id=42", csrf: false),
            check(
                "play",
                LiveRequest.playInfo(room: 42, qn: 10000),
                "codec=0%2C1%2C2&dolby=5&format=0%2C1%2C2&panorama=1&platform=web&protocol=0%2C1&ptype=8&qn=10000&room_id=42&web_location=444.8",
                csrf: false
            ),
            check("danmu", LiveRequest.danmuInfo(room: 42), "id=42&web_location=444.8", csrf: false),
            check(
                "send",
                LiveRequest.send(room: 42, message: "你好", csrf: csrf, rnd: 1_700_000_000),
                "bubble=0&color=16777215&csrf=jct-token&csrf_token=jct-token&fontsize=25&mode=1&msg=%E4%BD%A0%E5%A5%BD&rnd=1700000000&room_type=0&roomid=42",
                csrf: true
            )
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
        let empty = LiveRequest.send(room: 1, message: "a", csrf: "", rnd: 1)
        if empty.hasCSRF || AccountRequest.isReady(empty) {
            issues.append("empty csrf was treated as signed")
        }
        if LiveRequest.qualityName(10000) != "原画" || LiveRequest.qualityName(400) != "蓝光" || LiveRequest.qn(for: "原画") != 10000 {
            issues.append("quality map")
        }
        if LiveRequest.parentID(for: "虚拟主播") != 9 || LiveRequest.parentID(for: "网游") != 2 || LiveRequest.parentID(for: "推荐") != 0 {
            issues.append("area id")
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
        try? data.write(to: LaunchClock.documents.appendingPathComponent("live-proof.json"), options: .atomic)
        if let text = String(data: data, encoding: .utf8) {
            print("LIVE_PROOF_BEGIN")
            print(text)
            print("LIVE_PROOF_END")
            fflush(stdout)
        }
        exit(issues.isEmpty ? 0 : 1)
    }

    private static func check(_ name: String, _ form: SignedForm, _ expect: String, csrf: Bool) -> Case {
        Case(name: name, method: form.method, path: form.path, body: form.body, expect: expect, csrf: csrf)
    }
}

enum LiveUIProof {
    static func record(_ payload: [String: Any]) {
        guard let screen = LaunchMode.screen, screen == "live" || screen == "live-area" else { return }
        var body = payload
        body["screen"] = screen
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { return }
        try? data.write(to: LaunchClock.documents.appendingPathComponent("live-ui.json"), options: .atomic)
    }
}

enum LiveRoomProof {
    static func record(_ payload: [String: Any]) {
        guard LaunchMode.screen == "live-room" else { return }
        var body = payload
        body["screen"] = "live-room"
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { return }
        try? data.write(to: LaunchClock.documents.appendingPathComponent("live-room-proof.json"), options: .atomic)
    }
}
