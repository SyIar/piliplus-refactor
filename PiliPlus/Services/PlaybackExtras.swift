import Darwin
import Foundation
import UIKit

struct ChapterMark: Identifiable, Hashable, Sendable {
    var id: Int { from }
    var from: Int
    var to: Int
    var title: String
}

struct EpisodeItem: Identifiable, Hashable, Sendable {
    var id: Int
    var title: String
    var longTitle: String
    var bvid: String
    var cid: Int
    var aid: Int
    var duration: Int
    var badge: String

    var label: String {
        if longTitle.isEmpty || longTitle == title { return title }
        return "\(title) \(longTitle)"
    }
}

struct SeasonGuide: Sendable {
    var seasonID: Int
    var title: String
    var episodes: [EpisodeItem]
}

struct VideoShotPage: Sendable {
    var images: [String]
    var index: [Int]
    var columns: Int
    var rows: Int
}

enum PlaybackMemory {
    private static let key = "piliplus.playback.progress.v1"

    static func position(cid: Int) -> Double {
        guard cid > 0, let bag = UserDefaults.standard.dictionary(forKey: key) else { return 0 }
        return (bag["\(cid)"] as? NSNumber)?.doubleValue ?? 0
    }

    static func remember(bvid: String, cid: Int, seconds: Double) {
        guard cid > 0, seconds.isFinite, seconds >= 0 else { return }
        // A pre-seek 0 would wipe a real position and the last-played resume target.
        if seconds < 0.8 { return }
        var bag = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        bag["\(cid)"] = seconds
        bag["lastBvid"] = bvid
        bag["lastCid"] = cid
        bag["lastSeconds"] = seconds
        UserDefaults.standard.set(bag, forKey: key)
    }

    static func last() -> (bvid: String, cid: Int, seconds: Double)? {
        guard let bag = UserDefaults.standard.dictionary(forKey: key),
              let bvid = bag["lastBvid"] as? String, !bvid.isEmpty else { return nil }
        let cid = (bag["lastCid"] as? NSNumber)?.intValue ?? 0
        let seconds = (bag["lastSeconds"] as? NSNumber)?.doubleValue ?? 0
        guard cid > 0, seconds > 1 else { return nil }
        return (bvid, cid, seconds)
    }
}

enum PlaybackRequest {
    static func heartbeat(bvid: String, cid: Int, played: Int, csrf: String, type: Int = 3) -> SignedForm {
        SignedForm(method: "POST", path: "/x/click-interface/web/heartbeat", fields: [
            "bvid": bvid,
            "cid": "\(cid)",
            "played_time": "\(max(0, played))",
            "type": "\(type)",
            "csrf": csrf
        ])
    }

    static func historyReport(aid: Int, csrf: String, type: Int = 3) -> SignedForm {
        SignedForm(method: "POST", path: "/x/v2/history/report", fields: [
            "aid": "\(aid)",
            "type": "\(type)",
            "csrf": csrf
        ])
    }

    /// `progress` is milliseconds. `rnd` is fixed in the proof so the form stays stable.
    static func danmaku(bvid: String, cid: Int, message: String, progress: Int, rnd: Int, csrf: String) -> SignedForm? {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, cid > 0, !bvid.isEmpty, !csrf.isEmpty else { return nil }
        return SignedForm(method: "POST", path: "/x/v2/dm/post", fields: [
            "type": "1",
            "oid": "\(cid)",
            "msg": text,
            "bvid": bvid,
            "progress": "\(max(0, progress))",
            "color": "16777215",
            "fontsize": "25",
            "mode": "1",
            "pool": "0",
            "rnd": "\(rnd)",
            "csrf": csrf
        ])
    }

    static func videoshot(bvid: String, cid: Int) -> SignedForm {
        SignedForm(method: "GET", path: "/x/player/videoshot", fields: [
            "bvid": bvid,
            "cid": "\(cid)",
            "index": "1"
        ])
    }

    static func playerInfo(bvid: String, cid: Int) -> SignedForm {
        SignedForm(method: "GET", path: "/x/player/wbi/v2", fields: [
            "bvid": bvid,
            "cid": "\(cid)"
        ])
    }
}

enum PlaybackMarkup {
    static func chapters(from data: JSON) -> [ChapterMark] {
        let list = data["data"]["view_points"].array ?? data["view_points"].array ?? []
        return list.compactMap { item in
            let from = item["from"].int ?? 0
            let title = item["content"].string ?? ""
            guard from >= 0, !title.isEmpty else { return nil }
            return ChapterMark(from: from, to: item["to"].int ?? from, title: title)
        }.sorted { $0.from < $1.from }
    }

    static func energy(from data: JSON) -> [Double] {
        let list = data["events"]["default"].array
            ?? data["data"]["events"]["default"].array
            ?? []
        let values = list.compactMap(\.double)
        guard let peak = values.max(), peak > 0 else { return values }
        return values.map { min(1, max(0, $0 / peak)) }
    }

    static func shot(from data: JSON) -> VideoShotPage? {
        let bag = data["data"]
        let images = (bag["image"].array ?? []).compactMap { $0.string }.map(BiliClient.https)
        let index = (bag["index"].array ?? []).compactMap(\.int)
        let columns = bag["img_x_len"].int ?? 10
        let rows = bag["img_y_len"].int ?? 10
        guard !images.isEmpty, !index.isEmpty, columns > 0, rows > 0 else { return nil }
        return VideoShotPage(images: images, index: index, columns: columns, rows: rows)
    }

    static func season(from data: JSON, seasonID: Int) -> SeasonGuide? {
        let bag = data["result"].string == nil && data["result"]["title"].string != nil ? data["result"] : data["data"]
        let title = bag["title"].string ?? bag["season_title"].string ?? ""
        var episodes = (bag["episodes"].array ?? []).compactMap { episode($0) }
        for section in bag["section"].array ?? [] {
            episodes.append(contentsOf: (section["episodes"].array ?? []).compactMap { episode($0) })
        }
        guard !title.isEmpty, !episodes.isEmpty else { return nil }
        return SeasonGuide(seasonID: bag["season_id"].int ?? seasonID, title: title, episodes: episodes)
    }

    static func frameIndex(at seconds: Double, index: [Int]) -> Int {
        guard !index.isEmpty else { return 0 }
        let last = index.last ?? 0
        let scale = last > 20_000 ? 1000.0 : 1.0
        let target = Int(seconds * scale)
        var best = 0
        var bestDelta = Int.max
        for (offset, stamp) in index.enumerated() {
            let delta = abs(stamp - target)
            if delta < bestDelta {
                bestDelta = delta
                best = offset
            }
        }
        return best
    }

    static func crop(sheet: UIImage, columns: Int, rows: Int, cell: Int) -> UIImage? {
        guard columns > 0, rows > 0, let cg = sheet.cgImage else { return nil }
        let per = columns * rows
        let local = ((cell % per) + per) % per
        let col = local % columns
        let row = local / columns
        let width = cg.width / columns
        let height = cg.height / rows
        guard width > 0, height > 0 else { return nil }
        let rect = CGRect(x: col * width, y: row * height, width: width, height: height)
        guard let piece = cg.cropping(to: rect) else { return nil }
        return UIImage(cgImage: piece, scale: sheet.scale, orientation: sheet.imageOrientation)
    }

    private static func episode(_ item: JSON) -> EpisodeItem? {
        let id = item["ep_id"].int ?? item["id"].int ?? 0
        let cid = item["cid"].int ?? 0
        let title = item["title"].string ?? item["index_title"].string ?? ""
        guard id > 0, cid > 0, !title.isEmpty else { return nil }
        return EpisodeItem(
            id: id,
            title: title,
            longTitle: item["long_title"].string ?? "",
            bvid: item["bvid"].string ?? "",
            cid: cid,
            aid: item["aid"].int ?? 0,
            duration: item["duration"].int ?? 0,
            badge: item["badge"].string ?? ""
        )
    }
}

enum PlaybackLog {
    static func line(_ text: String) {
        print(text)
        fflush(stdout)
    }
}

enum PlaybackUIProof {
    static func record(_ name: String, _ payload: [String: Any]) {
        guard LaunchMode.screen == name else { return }
        var body = payload
        body["screen"] = name
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { return }
        try? data.write(to: LaunchClock.documents.appendingPathComponent("\(name)-proof.json"), options: .atomic)
    }
}

enum PlaybackRequestProof {
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
        let send = PlaybackRequest.danmaku(bvid: "BV1", cid: 7, message: "你好", progress: 12_000, rnd: 1_700_000_000, csrf: csrf)!
        return [
            check("heartbeat", PlaybackRequest.heartbeat(bvid: "BV1", cid: 7, played: 12, csrf: csrf), "bvid=BV1&cid=7&csrf=jct-token&played_time=12&type=3", csrf: true),
            check("history-report", PlaybackRequest.historyReport(aid: 42, csrf: csrf), "aid=42&csrf=jct-token&type=3", csrf: true),
            check("danmaku", send, "bvid=BV1&color=16777215&csrf=jct-token&fontsize=25&mode=1&msg=%E4%BD%A0%E5%A5%BD&oid=7&pool=0&progress=12000&rnd=1700000000&type=1", csrf: true),
            check("videoshot", PlaybackRequest.videoshot(bvid: "BV1", cid: 7), "bvid=BV1&cid=7&index=1", csrf: false),
            check("player-info", PlaybackRequest.playerInfo(bvid: "BV1", cid: 7), "bvid=BV1&cid=7", csrf: false)
        ]
    }

    static func failures() -> [String] {
        var issues: [String] = []
        for item in cases() {
            if item.body != item.expect || item.path.isEmpty {
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
        if PlaybackRequest.danmaku(bvid: "BV1", cid: 7, message: "  ", progress: 0, rnd: 1, csrf: "jct-token") != nil {
            issues.append("blank danmaku was signed")
        }
        if PlaybackRequest.danmaku(bvid: "BV1", cid: 7, message: "你好", progress: 0, rnd: 1, csrf: "") != nil {
            issues.append("empty csrf was signed")
        }
        let options = ["不开启", "15 分钟", "30 分钟", "60 分钟", "播完当前"]
        if PlaybackSleep.options != options { issues.append("sleep options") }
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
        try? data.write(to: LaunchClock.documents.appendingPathComponent("playback-extra-proof.json"), options: .atomic)
        if let text = String(data: data, encoding: .utf8) {
            print("PLAYBACK_EXTRA_BEGIN")
            print(text)
            print("PLAYBACK_EXTRA_END")
            fflush(stdout)
        }
        exit(issues.isEmpty ? 0 : 1)
    }

    private static func check(_ name: String, _ form: SignedForm, _ expect: String, csrf: Bool) -> Case {
        Case(name: name, method: form.method, path: form.path, body: form.body, expect: expect, csrf: csrf)
    }
}

enum PlaybackSleep {
    static let options = ["不开启", "15 分钟", "30 分钟", "60 分钟", "播完当前"]

    static func deadline(for choice: String, now: Date = Date()) -> Date? {
        switch choice {
        case "15 分钟": return now.addingTimeInterval(15 * 60)
        case "30 分钟": return now.addingTimeInterval(30 * 60)
        case "60 分钟": return now.addingTimeInterval(60 * 60)
        default: return nil
        }
    }
}
