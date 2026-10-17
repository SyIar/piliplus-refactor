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
        if let url = item["baseUrl"].string, !url.isEmpty { return url }
        if let url = item["base_url"].string, !url.isEmpty { return url }
        if let url = item["backupUrl"].array?.first?.string, !url.isEmpty { return url }
        if let url = item["backup_url"].array?.first?.string, !url.isEmpty { return url }
        return ""
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
        let videoAsset = AVURLAsset(url: videoURL, options: options)
        if let audioURL {
            let audioAsset = AVURLAsset(url: audioURL, options: options)
            if let mixed = try? await mix(video: videoAsset, audio: audioAsset) {
                return mixed
            }
        }
        return await AVPlayerItem(asset: videoAsset)
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
        return await AVPlayerItem(asset: composition)
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
