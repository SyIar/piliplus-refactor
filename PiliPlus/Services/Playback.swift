import AVFoundation
import AVKit
import Foundation
import zlib

struct PlaybackOffer: Sendable {
    var videoURL: String
    var audioURL: String?
    var qualities: [String]
    var qualityIDs: [Int]
    var selectedQN: Int
    var selectedName: String
    var codec: String
}

struct SubtitleLine: Sendable, Hashable {
    var from: Double
    var to: Double
    var text: String
}

enum BiliHTTP {
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Mobile/15E148 Safari/604.1"
    /// Desktop Safari. Space dynamics uses this, matching upstream `BrowserUa.pc`.
    static let pcUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.2 Safari/605.1.15"
    static let origin = "https://www.bilibili.com"

    static func referer(bvid: String) -> String {
        bvid.isEmpty ? origin : "https://www.bilibili.com/video/\(bvid)"
    }

    static func assetHeaders(bvid: String) -> [String: String] {
        var headers = [
            "User-Agent": userAgent,
            "Referer": referer(bvid: bvid),
            "Origin": origin
        ]
        let cookie = mergedCookie(includeSession: true, override: nil)
        if !cookie.isEmpty { headers["Cookie"] = cookie }
        return headers
    }

    static func liveAssetHeaders(room: Int) -> [String: String] {
        var headers = [
            "User-Agent": userAgent,
            "Referer": "https://live.bilibili.com/\(room)",
            "Origin": "https://live.bilibili.com"
        ]
        let cookie = mergedCookie(includeSession: true, override: nil)
        if !cookie.isEmpty { headers["Cookie"] = cookie }
        return headers
    }

    static func mergedCookie(includeSession: Bool, override: String?) -> String {
        var parts: [String] = []
        if let guest = GuestIdentity.cachedHeader() { parts.append(guest) }
        if let override, !override.isEmpty {
            parts.append(override)
        } else if includeSession, let session = SessionVault.shared.cookieHeader(), !session.isEmpty {
            parts.append(session)
        }
        return parts.joined(separator: "; ")
    }

    /// Upstream `Utils.base64EncodeRandomString`, with the trailing padding cut off.
    static func randomToken(minCount: Int, maxCount: Int) -> String {
        let count = Int.random(in: minCount...max(minCount, maxCount))
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let encoded = Data(bytes).base64EncodedString()
        return encoded.count > 2 ? String(encoded.dropLast(2)) : encoded
    }
}

enum GuestIdentity {
    private static let buvid3Key = "piliplus.buvid3"
    private static let buvid4Key = "piliplus.buvid4"
    private static let bNutKey = "piliplus.b_nut"
    private static let bLsidKey = "piliplus.b_lsid"
    private static let ticketKey = "piliplus.bili_ticket"
    private static let ticketExpiresKey = "piliplus.bili_ticket_expires"
    private static let lock = NSLock()

    static func cachedHeader() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let buvid3 = UserDefaults.standard.string(forKey: buvid3Key), !buvid3.isEmpty,
              let buvid4 = UserDefaults.standard.string(forKey: buvid4Key), !buvid4.isEmpty,
              let bNut = UserDefaults.standard.string(forKey: bNutKey), !bNut.isEmpty else { return nil }
        let lsid = UserDefaults.standard.string(forKey: bLsidKey) ?? makeLsid()
        var header = "buvid3=\(buvid3); buvid4=\(buvid4); b_nut=\(bNut); b_lsid=\(lsid)"
        if let ticket = UserDefaults.standard.string(forKey: ticketKey), !ticket.isEmpty {
            let expires = UserDefaults.standard.string(forKey: ticketExpiresKey) ?? ""
            header += "; bili_ticket=\(ticket)"
            if !expires.isEmpty { header += "; bili_ticket_expires=\(expires)" }
        }
        return header
    }

    static func prepare(session: URLSession) async {
        if cachedHeader() != nil, hasTicket { return }
        await refresh(session: session)
    }

    static func refresh(session: URLSession) async {
        var buvid3 = ""
        var buvid4 = ""
        var bNut = String(Int(Date().timeIntervalSince1970))
        if let remote = try? await spi(session: session) {
            buvid3 = remote.buvid3
            buvid4 = remote.buvid4
        }
        if buvid3.isEmpty || buvid4.isEmpty {
            let homepage = (try? await homepageCookies(session: session)) ?? (buvid3: "", bNut: "")
            if buvid3.isEmpty { buvid3 = homepage.buvid3 }
            if homepage.bNut.isEmpty == false { bNut = homepage.bNut }
        }
        if buvid3.isEmpty { buvid3 = makeBuvid3() }
        if buvid4.isEmpty { buvid4 = makeBuvid4() }
        let lsid = makeLsid()
        let ticket = try? await webTicket(session: session)
        lock.lock()
        UserDefaults.standard.set(buvid3, forKey: buvid3Key)
        UserDefaults.standard.set(buvid4, forKey: buvid4Key)
        UserDefaults.standard.set(bNut, forKey: bNutKey)
        UserDefaults.standard.set(lsid, forKey: bLsidKey)
        if let ticket {
            UserDefaults.standard.set(ticket.token, forKey: ticketKey)
            UserDefaults.standard.set(ticket.expires, forKey: ticketExpiresKey)
        }
        lock.unlock()
    }

    private static var hasTicket: Bool {
        lock.lock()
        defer { lock.unlock() }
        let ticket = UserDefaults.standard.string(forKey: ticketKey) ?? ""
        return !ticket.isEmpty
    }

    /// `POST /bapis/bilibili.api.ticket.v1.Ticket/GenWebTicket`.
    private static func webTicket(session: URLSession) async throws -> (token: String, expires: String) {
        let timestamp = Int(Date().timeIntervalSince1970)
        let hex = WebTicket.hexSign(timestamp: timestamp)
        let fields = [
            "key_id": "ec02",
            "hexsign": hex,
            "context[ts]": "\(timestamp)",
            "csrf": ""
        ]
        let query = fields.keys.sorted().map { key in
            "\(PercentEncoding.encodeURIComponent(key))=\(PercentEncoding.encodeURIComponent(fields[key, default: ""]))"
        }.joined(separator: "&")
        guard let url = URL(string: "https://api.bilibili.com/bapis/bilibili.api.ticket.v1.Ticket/GenWebTicket?\(query)") else {
            throw BiliError.message("地址无效")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(BiliHTTP.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(BiliHTTP.origin, forHTTPHeaderField: "Referer")
        request.setValue(BiliHTTP.origin, forHTTPHeaderField: "Origin")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BiliError.status(http.statusCode)
        }
        let json = JSON(try JSONSerialization.jsonObject(with: data))
        guard json["code"].int == 0 else { throw BiliError.message(json["message"].string ?? "无法获取 bili_ticket") }
        let token = json["data"]["ticket"].string ?? ""
        guard !token.isEmpty else { throw BiliError.message("bili_ticket 为空") }
        let created = json["data"]["created_at"].int ?? timestamp
        let ttl = json["data"]["ttl"].int ?? 259_200
        return (token, String(created + ttl))
    }

    private static func spi(session: URLSession) async throws -> (buvid3: String, buvid4: String) {
        guard let url = URL(string: "https://api.bilibili.com/x/frontend/finger/spi") else {
            throw BiliError.message("地址无效")
        }
        var request = URLRequest(url: url)
        request.setValue(BiliHTTP.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(BiliHTTP.origin, forHTTPHeaderField: "Referer")
        request.setValue(BiliHTTP.origin, forHTTPHeaderField: "Origin")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BiliError.status(http.statusCode)
        }
        let object = try JSONSerialization.jsonObject(with: data)
        let json = JSON(object)
        guard json["code"].int == 0 else { throw BiliError.message(json["message"].string ?? "无法获取 buvid") }
        let buvid3 = json["data"]["b_3"].string ?? ""
        let buvid4 = json["data"]["b_4"].string ?? ""
        guard !buvid3.isEmpty, !buvid4.isEmpty else { throw BiliError.message("buvid 为空") }
        return (buvid3, buvid4)
    }

    private static func homepageCookies(session: URLSession) async throws -> (buvid3: String, bNut: String) {
        guard let url = URL(string: "https://www.bilibili.com/") else { throw BiliError.message("地址无效") }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(BiliHTTP.userAgent, forHTTPHeaderField: "User-Agent")
        let (_, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        let fields = http.map { cookieHeaderFields($0, url: url) } ?? []
        let buvid3 = fields.first { $0.name == "buvid3" }?.value ?? ""
        let bNut = fields.first { $0.name == "b_nut" }?.value ?? ""
        return (buvid3, bNut)
    }

    private static func makeBuvid3() -> String {
        let suffix = String(format: "%05d", Int.random(in: 0...99999))
        return UUID().uuidString.uppercased() + suffix + "infoc"
    }

    private static func makeBuvid4() -> String {
        makeBuvid3()
    }

    private static func cookieHeaderFields(_ response: HTTPURLResponse, url: URL) -> [HTTPCookie] {
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            guard let name = key as? String, let text = value as? String else { continue }
            headers[name] = text
        }
        return HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
    }

    private static func makeLsid() -> String {
        let alphabet = Array("0123456789ABCDEF")
        let head = String((0..<8).map { _ in alphabet.randomElement() ?? "A" })
        return head + "_" + String(Int(Date().timeIntervalSince1970), radix: 16, uppercase: true)
    }
}

enum PlaybackProof {
    private static let lock = NSLock()
    private static var lastSeconds = -10.0
    private static var failed = false

    static func record(seconds: Double, quality: String, codec: String, error: String) {
        guard LaunchMode.screen == "playback" else { return }
        lock.lock()
        if !error.isEmpty {
            failed = true
        } else if failed && seconds < 0.5 {
            lock.unlock()
            return
        } else if seconds >= 0.5 {
            failed = false
        }
        let due = !error.isEmpty || seconds - lastSeconds >= 0.45 || lastSeconds < 0
        if due { lastSeconds = error.isEmpty ? seconds : -10 }
        lock.unlock()
        guard due else { return }
        let payload: [String: Any] = [
            "seconds": seconds,
            "quality": quality,
            "codec": codec,
            "error": error
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
        let url = LaunchClock.documents.appendingPathComponent("playback-proof.json")
        try? data.write(to: url, options: .atomic)
    }
}

enum QualityMap {
    static let labels: [(id: Int, name: String)] = [
        (16, "流畅 360P"),
        (32, "清晰 480P"),
        (64, "高清 720P"),
        (80, "高清 1080P"),
        (112, "高清 1080P+"),
        (116, "高清 1080P60"),
        (120, "超清 4K")
    ]

    static func name(for id: Int) -> String {
        labels.first { $0.id == id }?.name ?? "qn \(id)"
    }

    /// "自动" asks for the top rung. The response then snaps to the best stream that actually exists.
    static func qn(for name: String) -> Int {
        if let exact = labels.first(where: { $0.name == name }) { return exact.id }
        if name.contains("8K") { return 127 }
        if name.contains("4K") || name.contains("2160") { return 120 }
        if name.contains("1080P60") || name.contains("60") { return 116 }
        if name.contains("1080+") || name.contains("1080P+") { return 112 }
        if name.contains("1080") { return 80 }
        if name.contains("720") { return 64 }
        if name.contains("480") { return 32 }
        if name.contains("360") || name.contains("流畅") { return 16 }
        return 120
    }

    static func audioID(for name: String) -> Int {
        if name.contains("64") { return 30216 }
        if name.contains("132") { return 30232 }
        if name.contains("杜比") { return 30250 }
        if name.lowercased().contains("hi") { return 30251 }
        return 30280
    }
}

struct DashStream: Sendable {
    var id: Int
    var url: String
    var codecs: String
    var bandwidth: Int
}

enum PlaybackParser {
    static func offer(from data: JSON, requestedQN: Int, codecPreference: String, audioPreference: String) -> PlaybackOffer? {
        let payload = data["data"]
        let videos = streams(payload["dash"]["video"])
        if let video = pickVideo(videos, qn: requestedQN, codecPreference: codecPreference) {
            var audioStreams = streams(payload["dash"]["audio"])
            audioStreams += streams(payload["dash"]["dolby"]["audio"])
            audioStreams += streams(payload["dash"]["flac"]["audio"])
            let audio = pickAudio(audioStreams, preference: audioPreference)
            let ids = Array(Set(videos.map(\.id))).sorted()
            let names = ids.map(QualityMap.name(for:))
            return PlaybackOffer(
                videoURL: video.url,
                audioURL: audio?.url,
                qualities: names,
                qualityIDs: ids,
                selectedQN: video.id,
                selectedName: QualityMap.name(for: video.id),
                codec: codecLabel(video.codecs)
            )
        }
        let progressive = payload["durl"][0]["url"].string ?? ""
        guard !progressive.isEmpty else { return nil }
        let ids = (payload["accept_quality"].array ?? []).compactMap(\.int)
        let names = (payload["accept_description"].array ?? []).compactMap(\.string)
        let selected = payload["quality"].int ?? requestedQN
        return PlaybackOffer(
            videoURL: progressive,
            audioURL: nil,
            qualities: names,
            qualityIDs: ids,
            selectedQN: selected,
            selectedName: QualityMap.name(for: selected),
            codec: "progressive"
        )
    }

    private static func streams(_ node: JSON) -> [DashStream] {
        (node.array ?? []).compactMap { item in
            let url = mediaURL(item)
            let id = item["id"].int ?? 0
            guard id > 0, !url.isEmpty else { return nil }
            return DashStream(
                id: id,
                url: url,
                codecs: item["codecs"].string ?? "",
                bandwidth: item["bandwidth"].int ?? 0
            )
        }
    }

    private static func mediaURL(_ item: JSON) -> String {
        let raw: String
        if let url = item["baseUrl"].string, !url.isEmpty { raw = url }
        else if let url = item["base_url"].string, !url.isEmpty { raw = url }
        else if let url = item["backupUrl"].array?.first?.string, !url.isEmpty { raw = url }
        else if let url = item["backup_url"].array?.first?.string, !url.isEmpty { raw = url }
        else { return "" }
        return BiliClient.https(raw)
    }

    static func pickVideo(_ streams: [DashStream], qn: Int, codecPreference: String) -> DashStream? {
        let ids = Set(streams.map(\.id))
        guard let target = ids.filter({ $0 <= qn }).max() ?? ids.min() else { return nil }
        let pool = streams.filter { $0.id == target }
        return pool.min { lhs, rhs in
            let left = codecRank(lhs.codecs, preference: codecPreference)
            let right = codecRank(rhs.codecs, preference: codecPreference)
            if left != right { return left < right }
            return lhs.bandwidth > rhs.bandwidth
        }
    }

    static func pickAudio(_ streams: [DashStream], preference: String) -> DashStream? {
        guard !streams.isEmpty else { return nil }
        let wanted = QualityMap.audioID(for: preference)
        if let exact = streams.filter({ $0.id == wanted }).max(by: { $0.bandwidth < $1.bandwidth }) {
            return exact
        }
        if wanted >= 30250 {
            return streams.max { $0.bandwidth < $1.bandwidth }
        }
        let normal = streams.filter { $0.id < 30250 }
        return normal.max { $0.bandwidth < $1.bandwidth } ?? streams.max { $0.bandwidth < $1.bandwidth }
    }

    static func codecRank(_ codecs: String, preference: String) -> Int {
        let value = codecs.lowercased()
        let pref = preference.lowercased()
        let preferred: Bool
        switch pref {
        case "av1": preferred = value.contains("av01")
        case "hev1", "hevc", "hvc1": preferred = value.contains("hvc1") || value.contains("hev1")
        default: preferred = value.contains("avc1")
        }
        if preferred { return 0 }
        if value.contains("avc1") { return 1 }
        return 2
    }

    static func codecLabel(_ codecs: String) -> String {
        let value = codecs.lowercased()
        if value.contains("av01") { return "av01" }
        if value.contains("hvc1") || value.contains("hev1") { return "hvc1" }
        if value.contains("avc1") { return "avc1" }
        return codecs.isEmpty ? "progressive" : codecs
    }
}

enum RawInflate {
    static func expand(_ source: Data) -> Data? {
        guard !source.isEmpty else { return nil }
        if looksLikeXML(source) { return source }
        return decompress(source, windowBits: -15) ?? decompress(source, windowBits: 15)
    }

    private static func looksLikeXML(_ data: Data) -> Bool {
        data.starts(with: Data("<?xml".utf8)) || data.starts(with: Data("<i".utf8))
    }

    private static func decompress(_ source: Data, windowBits: Int32) -> Data? {
        var stream = z_stream()
        guard inflateInit2_(&stream, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            return nil
        }
        defer { inflateEnd(&stream) }
        var output = Data()
        let chunk = 65_536
        let status: Int32 = source.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return Z_DATA_ERROR }
            stream.next_in = UnsafeMutablePointer(mutating: base)
            stream.avail_in = uInt(source.count)
            var code: Int32 = Z_OK
            while code == Z_OK {
                var buffer = [UInt8](repeating: 0, count: chunk)
                code = buffer.withUnsafeMutableBytes { out -> Int32 in
                    guard let outBase = out.bindMemory(to: UInt8.self).baseAddress else { return Z_DATA_ERROR }
                    stream.next_out = outBase
                    stream.avail_out = uInt(chunk)
                    let result = zlib.inflate(&stream, Z_NO_FLUSH)
                    let count = chunk - Int(stream.avail_out)
                    if count > 0 {
                        output.append(outBase, count: count)
                    }
                    return result
                }
            }
            return code
        }
        guard status == Z_STREAM_END, !output.isEmpty else { return nil }
        return output
    }
}

final class DanmakuXML: NSObject, XMLParserDelegate {
    private var cues: [DanmakuCue] = []
    private var time: Double?
    private var mode = 1
    private var color: UInt32 = 0xFFFFFF
    private var text = ""

    static func parse(_ data: Data) -> [DanmakuCue] {
        let parser = XMLParser(data: data)
        let delegate = DanmakuXML()
        parser.delegate = delegate
        parser.parse()
        return Array(delegate.cues.sorted { $0.time < $1.time }.prefix(2500))
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "d", let raw = attributeDict["p"] else {
            time = nil
            return
        }
        let parts = raw.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count >= 4, let stamp = Double(parts[0]) else {
            time = nil
            return
        }
        time = stamp
        mode = Int(parts[1]) ?? 1
        color = UInt32(parts[3]) ?? 0xFFFFFF
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if time != nil { text += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName == "d", let time else { return }
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !line.isEmpty {
            cues.append(DanmakuCue(time: time, text: line, color: color, mode: mode))
        }
        self.time = nil
        text = ""
    }
}

enum SubtitlePicker {
    static func pick(lan: String, doc: String, preference: String) -> Int {
        let language = lan.lowercased()
        switch preference {
        case "简中":
            if language.contains("zh-hans") || language == "zh-cn" || language.contains("ai-zh") || doc.contains("简") { return 0 }
        case "繁中":
            if language.contains("hant") || language.contains("zh-hk") || language.contains("zh-tw") || doc.contains("繁") { return 0 }
        case "英语":
            if language.hasPrefix("en") || doc.contains("英") { return 0 }
        case "日语":
            if language.hasPrefix("ja") || doc.contains("日") { return 0 }
        default:
            return 0
        }
        return 1
    }
}

enum StreamComposer {
    static func item(videoURL: URL, audioURL: URL?, headers: [String: String]) async -> AVPlayerItem {
        let options = ["AVURLAssetHTTPHeaderFieldsKey": headers]
        if let audioURL {
            let slot = MixedItem()
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    let videoAsset = AVURLAsset(url: videoURL, options: options)
                    let audioAsset = AVURLAsset(url: audioURL, options: options)
                    if let mixed = try? await mix(video: videoAsset, audio: audioAsset) {
                        slot.store(mixed)
                    }
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(8))
                }
                await group.next()
                group.cancelAll()
            }
            if let mixed = slot.take() { return mixed }
        }
        return AVPlayerItem(asset: AVURLAsset(url: videoURL, options: options))
    }

    private static func mix(video: AVURLAsset, audio: AVURLAsset) async throws -> AVPlayerItem {
        async let videoTracks = video.loadTracks(withMediaType: .video)
        async let audioTracks = audio.loadTracks(withMediaType: .audio)
        async let videoDuration = video.load(.duration)
        async let audioDuration = audio.load(.duration)
        let loadedVideo = try await videoTracks
        let loadedAudio = try await audioTracks
        guard let videoTrack = loadedVideo.first, let audioTrack = loadedAudio.first else {
            throw BiliError.message("缺少音视频轨")
        }
        let duration = try await videoDuration
        let soundDuration = try await audioDuration
        let composition = AVMutableComposition()
        guard let composedVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let composedAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw BiliError.message("无法合成")
        }
        try composedVideo.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: videoTrack, at: .zero)
        let audioSpan = CMTimeMinimum(duration, soundDuration)
        try composedAudio.insertTimeRange(CMTimeRange(start: .zero, duration: audioSpan), of: audioTrack, at: .zero)
        return AVPlayerItem(asset: composition)
    }
}

/// Holds the composed item across a timeout race. `AVPlayerItem` is not `Sendable`.
private final class MixedItem: @unchecked Sendable {
    private let lock = NSLock()
    private var item: AVPlayerItem?

    func store(_ item: AVPlayerItem) {
        lock.lock()
        self.item = item
        lock.unlock()
    }

    func take() -> AVPlayerItem? {
        lock.lock()
        let item = self.item
        lock.unlock()
        return item
    }
}

@MainActor
final class PictureInPictureBridge {
    static let shared = PictureInPictureBridge()
    weak var controller: AVPictureInPictureController?

    var supported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else {
            controller.startPictureInPicture()
        }
    }
}
