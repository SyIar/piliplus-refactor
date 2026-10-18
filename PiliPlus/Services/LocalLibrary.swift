import Foundation

/// On-device history and watch-later. Cloud lists stay behind login; these rows are videos this phone actually played or queued.
enum LocalLibrary {
    private static let historyKey = "piliplus.local.history.v1"
    private static let laterKey = "piliplus.local.later.v1"

    static func isFixture(_ video: VideoItem) -> Bool {
        let bvid = video.bvid.lowercased()
        return video.title.contains("液态玻璃")
            || bvid.contains("fixture")
            || video.ownerName.contains("玻璃试验")
    }

    static func history() -> [VideoItem] {
        decode(historyKey).filter { !isFixture($0) }
    }

    static func rememberHistory(_ video: VideoItem) {
        guard !video.bvid.isEmpty, !isFixture(video) else { return }
        var items = history().filter { $0.bvid != video.bvid }
        items.insert(stripped(video), at: 0)
        if items.count > 50 { items = Array(items.prefix(50)) }
        encode(items, historyKey)
    }

    static func removeHistory(_ bvid: String) {
        encode(history().filter { $0.bvid != bvid }, historyKey)
    }

    static func clearHistory() {
        UserDefaults.standard.removeObject(forKey: historyKey)
    }

    static func later() -> [VideoItem] {
        decode(laterKey).filter { !isFixture($0) }
    }

    static func addLater(_ video: VideoItem) {
        guard !video.bvid.isEmpty, !isFixture(video) else { return }
        var items = later().filter { $0.bvid != video.bvid }
        items.insert(stripped(video), at: 0)
        if items.count > 50 { items = Array(items.prefix(50)) }
        encode(items, laterKey)
    }

    static func removeLater(_ bvid: String) {
        encode(later().filter { $0.bvid != bvid }, laterKey)
    }

    static func clearLater() {
        UserDefaults.standard.removeObject(forKey: laterKey)
    }

    private static func stripped(_ video: VideoItem) -> VideoItem {
        var copy = video
        copy.playURL = nil
        copy.audioURL = nil
        return copy
    }

    private static func decode(_ key: String) -> [VideoItem] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([VideoItem].self, from: data)) ?? []
    }

    private static func encode(_ items: [VideoItem], _ key: String) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
