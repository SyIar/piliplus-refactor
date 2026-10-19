import CryptoKit
import Foundation
import SwiftUI

enum SponsorAction: String, CaseIterable, Identifiable {
    case skip = "自动跳过"
    case prompt = "提示"
    case ignore = "忽略"
    var id: String { rawValue }
}

struct SponsorCategory: Identifiable, Hashable {
    var id: String
    var title: String
    var detail: String
    var color: Color
    var fallback: SponsorAction
}

struct SponsorSegment: Identifiable {
    var id: String
    var category: String
    var actionType: String
    var start: Double
    var end: Double
    var videoDuration: Double
    var votes: Int

    var title: String { SponsorCatalog.title(category) }
    var color: Color { SponsorCatalog.color(category) }
}

enum SponsorCatalog {
    static let categories: [SponsorCategory] = [
        .init(id: "sponsor", title: "赞助", detail: "付费推广和直接广告", color: Color(hex: 0x00D400), fallback: .skip),
        .init(id: "selfpromo", title: "推广", detail: "无偿或自我推广", color: Color(hex: 0xC6B400), fallback: .skip),
        .init(id: "exclusive_access", title: "品牌合作", detail: "整集都是品牌内容时使用", color: Color(hex: 0x008A5C), fallback: .prompt),
        .init(id: "interaction", title: "三连提醒", detail: "提醒点赞、投币、收藏或关注", color: Color(hex: 0xCC00FF), fallback: .skip),
        .init(id: "poi_highlight", title: "精彩时刻", detail: "大多数人想空降到的时间点", color: Color(hex: 0xFF1684), fallback: .prompt),
        .init(id: "intro", title: "开场", detail: "没有正片内容的片头", color: Color(hex: 0x00A3A3), fallback: .skip),
        .init(id: "outro", title: "片尾", detail: "鸣谢或结束画面", color: Color(hex: 0x4C6FFF), fallback: .skip),
        .init(id: "preview", title: "预览", detail: "稍后会再次出现的画面集锦", color: Color(hex: 0x008FD6), fallback: .skip),
        .init(id: "padding", title: "填充", detail: "片头片尾的黑屏或无关画面", color: Color(hex: 0x8E8E93), fallback: .skip),
        .init(id: "filler", title: "离题", detail: "不影响理解正片的闲聊", color: Color(hex: 0x7300FF), fallback: .ignore),
        .init(id: "music_offtopic", title: "非音乐", detail: "音乐视频里不属于音乐的部分", color: Color(hex: 0xFF9900), fallback: .ignore)
    ]

    static func title(_ id: String) -> String {
        categories.first { $0.id == id }?.title ?? id
    }

    static func color(_ id: String) -> Color {
        categories.first { $0.id == id }?.color ?? .white
    }

    static func fallback(_ id: String) -> SponsorAction {
        categories.first { $0.id == id }?.fallback ?? .prompt
    }

    /// Videos checked on bsbsb.top. The first playable one with segments is the proof.
    static let proofCandidates = ["BV1Yo3sz6EbG", "BV1nQmcBWE4W", "BV1D4411t7Ci"]
}

enum SponsorStore {
    private static let key = "piliplus.sponsor.actions"

    static func action(for category: String) -> SponsorAction {
        let saved = UserDefaults.standard.dictionary(forKey: key) as? [String: String]
        if let raw = saved?[category], let action = SponsorAction(rawValue: raw) { return action }
        return SponsorCatalog.fallback(category)
    }

    static func set(_ action: SponsorAction, for category: String) {
        var saved = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        saved[category] = action.rawValue
        UserDefaults.standard.set(saved, forKey: key)
    }
}

enum SponsorClient {
    /// Upstream asks `sponsor.ajay.app` and the Bilibili mirror `bsbsb.top` with a 4-character SHA-256 prefix of the bvid.
    static let servers = ["https://sponsor.ajay.app", "https://bsbsb.top"]

    static func hashPrefix(for bvid: String) -> String {
        String(digest(bvid).prefix(4))
    }

    static func segments(for bvid: String) async -> (items: [SponsorSegment], server: String, prefix: String) {
        let full = digest(bvid)
        let prefix = String(full.prefix(4))
        for server in servers {
            do {
                let items = try await fetch(server: server, prefix: prefix, bvid: bvid)
                print("sponsor \(server) \(prefix) \(items.count)")
                if !items.isEmpty { return (items, server, prefix) }
            } catch {
                print("sponsor \(server) \(prefix) \(error.localizedDescription)")
            }
        }
        return ([], "", prefix)
    }

    private static func fetch(server: String, prefix: String, bvid: String) async throws -> [SponsorSegment] {
        guard let url = URL(string: "\(server)/api/skipSegments/\(prefix)") else { return [] }
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("PiliPlus/2.0.0", forHTTPHeaderField: "User-Agent")
        request.setValue("PiliPlus", forHTTPHeaderField: "Origin")
        request.setValue("2.0.0", forHTTPHeaderField: "x-ext-version")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { return [] }
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        var found: [SponsorSegment] = []
        for row in rows {
            guard (row["videoID"] as? String) == bvid else { continue }
            for item in row["segments"] as? [[String: Any]] ?? [] {
                guard let segment = segment(from: item) else { continue }
                found.append(segment)
            }
        }
        return found.sorted { $0.start < $1.start }
    }

    private static func segment(from item: [String: Any]) -> SponsorSegment? {
        guard let times = item["segment"] as? [Any], times.count >= 2 else { return nil }
        let start = number(times[0])
        let end = number(times[1])
        guard end > start else { return nil }
        let category = item["category"] as? String ?? "sponsor"
        let uuid = item["UUID"] as? String ?? "\(category)-\(start)-\(end)"
        return SponsorSegment(
            id: uuid,
            category: category,
            actionType: item["actionType"] as? String ?? "skip",
            start: start,
            end: end,
            videoDuration: number(item["videoDuration"] ?? 0),
            votes: Int(number(item["votes"] ?? 0))
        )
    }

    private static func number(_ value: Any) -> Double {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) ?? 0 }
        return 0
    }

    private static func digest(_ bvid: String) -> String {
        SHA256.hash(data: Data(bvid.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum SponsorProof {
    static func record(_ payload: [String: Any]) {
        guard LaunchMode.screen == "sponsor" else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
        try? data.write(to: LaunchClock.documents.appendingPathComponent("sponsor-proof.json"), options: .atomic)
    }
}

enum SponsorSettingsProof {
    static func record() {
        guard LaunchMode.screen == "sponsor-settings" else { return }
        let actions = Dictionary(uniqueKeysWithValues: SponsorCatalog.categories.map { ($0.id, SponsorStore.action(for: $0.id).rawValue) })
        let payload: [String: Any] = [
            "screen": "sponsor-settings",
            "sponsor": actions["sponsor"] ?? "",
            "actions": actions
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
        try? data.write(to: LaunchClock.documents.appendingPathComponent("sponsor-settings-proof.json"), options: .atomic)
    }
}
