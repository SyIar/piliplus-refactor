import AVFoundation
import Foundation

struct OfflineItem: Codable, Identifiable, Hashable {
    var id: String
    var bvid: String
    var aid: Int
    var cid: Int
    var page: Int
    var pageTitle: String
    var title: String
    var owner: String
    var duration: Int
    var quality: String
    var qn: Int
    var codec: String
    var state: String
    var fraction: Double
    var bytesWritten: Int64
    var bytesExpected: Int64
    var danmakuCount: Int
    var error: String

    var label: String {
        switch state {
        case "queued": "等待中"
        case "running": "下载中"
        case "paused": "已暂停"
        case "merging": "正在合成"
        case "ready": "已完成"
        case "failed": "失败"
        default: state
        }
    }
}

enum OfflineFiles {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Offline", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func folder(bvid: String, cid: Int) -> URL {
        let dir = root
            .appendingPathComponent(safe(bvid), isDirectory: true)
            .appendingPathComponent("\(cid)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func video(_ item: OfflineItem) -> URL { folder(bvid: item.bvid, cid: item.cid).appendingPathComponent("video.m4s") }
    static func audio(_ item: OfflineItem) -> URL { folder(bvid: item.bvid, cid: item.cid).appendingPathComponent("audio.m4s") }
    static func movie(_ item: OfflineItem) -> URL { folder(bvid: item.bvid, cid: item.cid).appendingPathComponent("movie.mp4") }
    static func danmaku(_ item: OfflineItem) -> URL { folder(bvid: item.bvid, cid: item.cid).appendingPathComponent("danmaku.xml") }
    static func cover(_ item: OfflineItem) -> URL { folder(bvid: item.bvid, cid: item.cid).appendingPathComponent("cover.jpg") }

    static func usage() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }

    private static func safe(_ bvid: String) -> String {
        let allowed = CharacterSet.alphanumerics
        return bvid.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
    }
}

/// Rejects http(s) while an offline playback proof is on screen. File URLs never reach this.
final class OfflineFirewall: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var enabled = false

    override class func canInit(with request: URLRequest) -> Bool {
        guard enabled, let scheme = request.url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}

    static func install() {
        enabled = true
        URLProtocol.registerClass(OfflineFirewall.self)
    }
}

enum OfflineProof {
    static func downloads(_ item: OfflineItem?, error: String = "", merge: MergeProbe? = nil) {
        let movie = item.map { OfflineFiles.movie($0) }
        let video = item.map { OfflineFiles.video($0) }
        let file = [movie, video].compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
        let exists = file != nil
        var payload: [String: Any] = [
            "screen": "downloads",
            "bvid": item?.bvid ?? "",
            "title": item?.title ?? "",
            "cid": item?.cid ?? 0,
            "quality": item?.quality ?? "",
            "codec": item?.codec ?? "",
            "state": item?.state ?? "failed",
            "fraction": item?.fraction ?? 0,
            "bytes": item?.bytesWritten ?? 0,
            "danmaku": item?.danmakuCount ?? 0,
            "storage": OfflineFiles.usage(),
            "asset": exists ? (file?.absoluteString ?? "") : "",
            "scheme": exists ? (file?.scheme ?? "") : "",
            "error": error.isEmpty ? (item?.error ?? "") : error
        ]
        if let merge {
            payload["mergeFrames"] = merge.frames
            payload["mergeP95"] = merge.p95
            payload["mergeMax"] = merge.max
            payload["mergeScrolls"] = merge.scrolls
            payload["mergeOnMain"] = merge.onMain
            payload["mergeMs"] = merge.ms
            payload["mergeWorkMs"] = merge.workMs
        }
        write("downloads-proof.json", payload)
    }

    static func playback(item: OfflineItem, asset: String, seconds: Double, danmaku: Int, error: String) {
        write("offline-proof.json", [
            "screen": "offline",
            "bvid": item.bvid,
            "title": item.title,
            "quality": item.quality,
            "codec": item.codec,
            "asset": asset,
            "scheme": URL(string: asset)?.scheme ?? "",
            "seconds": seconds,
            "danmaku": danmaku,
            "error": error
        ])
    }

    private static func write(_ name: String, _ payload: [String: Any]) {
        guard LaunchMode.screen == "downloads" || LaunchMode.screen == "offline" else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
        try? data.write(to: LaunchClock.documents.appendingPathComponent(name), options: .atomic)
    }
}

final class DownloadBridge: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = DownloadBridge()
    private var session: URLSession?
    private var foreground: URLSession?
    var backgroundCompletion: (() -> Void)?

    func ensureSession() -> URLSession {
        if let session { return session }
        let config = URLSessionConfiguration.background(withIdentifier: "com.syiar.piliplus.downloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        let created = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        session = created
        return created
    }

    /// Simulator background transfers fail with NSURLErrorUnknown. The same delegate then saves the DASH file in-process.
    func startInProcess(id: String, kind: String, url: URL, headers: [String: String]) {
        if foreground == nil {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForResource = 300
            foreground = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        }
        var request = URLRequest(url: url)
        for (key, value) in headers where !value.isEmpty {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let task = foreground!.downloadTask(with: request)
        task.taskDescription = "\(kind)|\(id)"
        task.resume()
    }

    func start(id: String, kind: String, url: URL, headers: [String: String]) {
        var request = URLRequest(url: url)
        for (key, value) in headers where !value.isEmpty {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let task = ensureSession().downloadTask(with: request)
        task.taskDescription = "\(kind)|\(id)"
        task.resume()
    }

    func suspend(id: String) {
        tasks(id: id) { $0.suspend() }
    }

    func resume(id: String) {
        tasks(id: id) { $0.resume() }
    }

    func cancel(id: String) {
        tasks(id: id) { $0.cancel() }
    }

    private func tasks(id: String, body: @escaping (URLSessionDownloadTask) -> Void) {
        let apply: ([URLSessionTask]) -> Void = { tasks in
            for case let task as URLSessionDownloadTask in tasks where task.taskDescription == "video|\(id)" || task.taskDescription == "audio|\(id)" {
                body(task)
            }
        }
        ensureSession().getAllTasks(completionHandler: apply)
        foreground?.getAllTasks(completionHandler: apply)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let parts = parts(of: downloadTask) else { return }
        let expected = totalBytesExpectedToWrite
        Task { @MainActor in
            DownloadCenter.current?.note(id: parts.id, kind: parts.kind, written: totalBytesWritten, expected: expected)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let parts = parts(of: downloadTask) else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        let folder = Self.folder(for: parts.id)
        let destination = folder.appendingPathComponent(parts.kind == "audio" ? "audio.m4s" : "video.m4s")
        var moved = false
        if (200..<300).contains(status) {
            try? FileManager.default.removeItem(at: destination)
            moved = (try? FileManager.default.moveItem(at: location, to: destination)) != nil
        }
        let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let header: String = {
            guard let handle = try? FileHandle(forReadingFrom: destination),
                  let data = try? handle.read(upToCount: 12) else { return "" }
            try? handle.close()
            return data.map { String(format: "%02x", $0) }.joined()
        }()
        print("offline file \(parts.kind) \(size) \(status) \(header)")
        let ok = moved && size > 10_000
        Task { @MainActor in
            DownloadCenter.current?.finished(id: parts.id, kind: parts.kind, ok: ok, status: status)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let parts = parts(of: task) else { return }
        let ns = error as NSError
        if ns.code == NSURLErrorCancelled { return }
        print("offline task \(ns.domain) \(ns.code) \(parts.kind)")
        let backgroundGaveUp = session.configuration.identifier != nil && ns.domain == NSURLErrorDomain && (
            ns.code == URLError.unknown.rawValue || ns.code == URLError.backgroundSessionWasDisconnected.rawValue
        )
        Task { @MainActor in
            if backgroundGaveUp {
                DownloadCenter.current?.backgroundFailed(id: parts.id, kind: parts.kind, code: ns.code)
            } else {
                DownloadCenter.current?.failed(id: parts.id, message: "\(ns.domain) \(ns.code)")
            }
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let handler = backgroundCompletion
        backgroundCompletion = nil
        DispatchQueue.main.async { handler?() }
    }

    private func parts(of task: URLSessionTask) -> (id: String, kind: String)? {
        guard let raw = task.taskDescription else { return nil }
        let bits = raw.split(separator: "|", maxSplits: 1).map(String.init)
        guard bits.count == 2 else { return nil }
        return (bits[1], bits[0])
    }

    private static func folder(for id: String) -> URL {
        let bits = id.split(separator: "|", maxSplits: 1).map(String.init)
        let bvid = bits.first ?? "video"
        let cid = bits.count > 1 ? Int(bits[1]) ?? 0 : 0
        return OfflineFiles.folder(bvid: bvid, cid: cid)
    }
}

struct MergeProbe: Sendable {
    var frames: Int
    var p95: Double
    var max: Double
    var scrolls: Int
    var onMain: Bool
    var ms: Double
    var workMs: Double
}

struct RemuxOutcome: Sendable {
    var ok: Bool
    var onMain: Bool
}

/// Rebuilds a progressive movie off the main actor.
///
/// `Task.detached` from `DownloadCenter` stayed on the main actor: the closure was
/// formed in a `@MainActor` method, and `Task.detached` keeps that isolation.
/// `writeMovie` also printed only after the parse finished, so a slow parse looked
/// like a task that never started. `AVAssetExportSession` still cannot open the
/// iso5 `.m4s` (`AVFoundationErrorDomain` -11828). The main actor awaits this
/// actor and applies progress back on itself.
actor OfflineRemux {
    static let shared = OfflineRemux()

    func writeMovie(video: URL, audio: URL?, to output: URL, progress: @escaping @Sendable (Double) -> Void) -> RemuxOutcome {
        let onMain = Thread.isMainThread
        print("offline remux actor main=\(onMain) \(video.lastPathComponent)")
        progress(0.05)
        do {
            try FragmentRemux.writeMovie(video: video, audio: audio, to: output, progress: progress)
        } catch {
            print("offline remux \(error.localizedDescription)")
            return RemuxOutcome(ok: false, onMain: onMain)
        }
        let size = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        print("offline remux wrote \(size)")
        return RemuxOutcome(ok: size > 10_000, onMain: onMain)
    }
}

@MainActor
@Observable
final class DownloadCenter {
    static weak var current: DownloadCenter?

    private(set) var items: [OfflineItem] = []
    private var client = BiliClient()
    private var jobs: [DownloadJob] = []
    private var draining = false
    private var tracks: [String: TrackPair] = [:]
    private var waiters: [String: CheckedContinuation<TrackResult, Never>] = [:]
    var storageBytes: Int64 = 0
    /// Bumps while a merge is in flight so the downloads list scrolls on the main actor.
    var mergeOffset = 0

    var storageLabel: String {
        ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file)
    }

    var active: [OfflineItem] { items.filter { $0.state != "ready" } }

    var completedGroups: [(bvid: String, title: String, parts: [OfflineItem])] {
        var order: [String] = []
        var map: [String: [OfflineItem]] = [:]
        for item in items where item.state == "ready" {
            if map[item.bvid] == nil { order.append(item.bvid) }
            map[item.bvid, default: []].append(item)
        }
        return order.map { (bvid: $0, title: map[$0]?.first?.title ?? $0, parts: map[$0] ?? []) }
    }

    var latestReady: OfflineItem? { items.last { $0.state == "ready" } }

    func item(_ id: String) -> OfflineItem? { items.first { $0.id == id } }

    init() {
        items = Self.load()
        storageBytes = OfflineFiles.usage()
        DownloadCenter.current = self
    }

    func bind(_ client: BiliClient) {
        self.client = client
    }

    func enqueue(video: VideoItem, pages: [VideoPage], quality: String, codec: String, limit: Int64?) {
        let chosen = pages.filter { $0.cid > 0 }
        guard !chosen.isEmpty else { return }
        for page in chosen {
            let id = Self.makeID(bvid: video.bvid, cid: page.cid)
            if let existing = items.first(where: { $0.id == id }), existing.state != "failed" { continue }
            items.removeAll { $0.id == id }
            items.append(OfflineItem(
                id: id,
                bvid: video.bvid,
                aid: video.aid,
                cid: page.cid,
                page: page.index,
                pageTitle: page.title.isEmpty ? "P\(page.index)" : page.title,
                title: video.title,
                owner: video.ownerName,
                duration: page.duration > 0 ? page.duration : video.duration,
                quality: quality,
                qn: QualityMap.qn(for: quality),
                codec: codec,
                state: "queued",
                fraction: 0,
                bytesWritten: 0,
                bytesExpected: 0,
                danmakuCount: 0,
                error: ""
            ))
        }
        jobs.append(DownloadJob(bvid: video.bvid, pages: chosen, quality: quality, codec: codec, limit: limit, cover: video.cover))
        save()
        Task { await drain() }
    }

    func pause(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].state == "running" else { return }
        items[index].state = "paused"
        DownloadBridge.shared.suspend(id: id)
        save()
        publish(items[index])
    }

    func resume(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if items[index].state == "paused" {
            items[index].state = "running"
            DownloadBridge.shared.resume(id: id)
            save()
            publish(items[index])
            return
        }
        if items[index].state == "failed" {
            items[index].state = "queued"
            items[index].error = ""
            items[index].fraction = 0
            save()
            let item = items[index]
            jobs.append(DownloadJob(
                bvid: item.bvid,
                pages: [VideoPage(cid: item.cid, index: item.page, title: item.pageTitle, duration: item.duration)],
                quality: item.quality,
                codec: item.codec,
                limit: nil,
                cover: ""
            ))
            Task { await drain() }
        }
    }

    func cancel(_ id: String) {
        DownloadBridge.shared.cancel(id: id)
        finishWait(id: id, result: .cancelled)
        tracks[id] = nil
        if let item = items.first(where: { $0.id == id }) {
            try? FileManager.default.removeItem(at: OfflineFiles.folder(bvid: item.bvid, cid: item.cid))
        }
        items.removeAll { $0.id == id }
        storageBytes = OfflineFiles.usage()
        save()
    }

    func prove(using model: AppModel) async {
        guard LaunchMode.screen == "downloads" else { return }
        if let ready = items.last(where: { $0.state == "ready" && $0.danmakuCount > 0 }) {
            OfflineProof.downloads(ready)
            return
        }
        if model.feed.isEmpty { await model.loadRecommend(reset: true) }
        var details: [VideoItem] = []
        for video in model.feed.prefix(8) where !video.bvid.isEmpty {
            if let detail = try? await client.detail(bvid: video.bvid) { details.append(detail) }
        }
        let ranked = details.sorted { lhs, rhs in
            let left = lhs.pages.first?.duration ?? lhs.duration
            let right = rhs.pages.first?.duration ?? rhs.duration
            let leftScore = (20...90).contains(left) ? 0 : 1
            let rightScore = (20...90).contains(right) ? 0 : 1
            if leftScore != rightScore { return leftScore < rightScore }
            return left < right
        }
        for detail in ranked.prefix(4) {
            let page = detail.pages.first ?? VideoPage(cid: detail.cid, index: 1, title: "P1", duration: detail.duration)
            guard page.cid > 0 else { continue }
            let seconds = page.duration > 0 ? page.duration : detail.duration
            let quality = seconds > 75 ? "流畅 360P" : "高清 720P"
            let id = Self.makeID(bvid: detail.bvid, cid: page.cid)
            await run(DownloadJob(bvid: detail.bvid, pages: [page], quality: quality, codec: "avc1", limit: nil, cover: detail.cover), video: detail)
            if let item = items.first(where: { $0.id == id }), item.state == "ready", item.danmakuCount > 0 {
                return
            }
        }
        OfflineProof.downloads(items.last, error: items.last?.error ?? "没有下载到可播放的视频")
    }

    func note(id: String, kind: String, written: Int64, expected: Int64) {
        var pair = tracks[id] ?? TrackPair()
        if kind == "audio" {
            pair.audioWritten = written
            pair.audioExpected = expected
        } else {
            pair.videoWritten = written
            pair.videoExpected = expected
        }
        tracks[id] = pair
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].bytesWritten = pair.videoWritten + pair.audioWritten
        items[index].bytesExpected = max(0, pair.videoExpected) + max(0, pair.audioExpected)
        items[index].fraction = pair.fraction
        if items[index].state == "queued" { items[index].state = "running" }
        storageBytes = max(storageBytes, items.filter { $0.state == "ready" }.reduce(Int64(0)) { $0 + $1.bytesWritten } + items[index].bytesWritten)
        publish(items[index])
    }

    func finished(id: String, kind: String, ok: Bool, status: Int) {
        var pair = tracks[id] ?? TrackPair()
        if kind == "audio" { pair.audioDone = ok } else { pair.videoDone = ok }
        tracks[id] = pair
        guard ok else {
            failed(id: id, message: "下载失败 \(status)")
            return
        }
        if pair.videoDone && (pair.audioDone || !pair.wantsAudio) {
            finishWait(id: id, result: .files)
        }
    }

    func backgroundFailed(id: String, kind: String, code: Int) {
        guard let state = items.first(where: { $0.id == id })?.state, state == "running" || state == "queued" else { return }
        guard var pair = tracks[id] else {
            failed(id: id, message: "后台下载 \(code)")
            return
        }
        let recovered = kind == "audio" ? pair.audioRecovered : pair.videoRecovered
        let remote = kind == "audio" ? pair.audioURL : pair.videoURL
        guard !recovered, let remote else {
            failed(id: id, message: "后台下载 \(code)")
            return
        }
        if kind == "audio" { pair.audioRecovered = true } else { pair.videoRecovered = true }
        tracks[id] = pair
        print("offline background \(code) \(kind) \(remote.host ?? ""), retry in process")
        DownloadBridge.shared.startInProcess(id: id, kind: kind, url: remote, headers: pair.headers)
    }

    /// Formed outside the main actor so the remux actor can call it without hopping back.
    private nonisolated static func mergeProgress(id: String) -> @Sendable (Double) -> Void {
        { fraction in
            Task { @MainActor in
                DownloadCenter.current?.reportMerge(id: id, fraction: fraction)
            }
        }
    }

    func reportMerge(id: String, fraction: Double) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].state == "merging" else { return }
        items[index].fraction = min(1, max(0, fraction))
    }

    private func mergeFailed(id: String, message: String, merge: MergeProbe? = nil) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].state = "failed"
        items[index].error = message
        save()
        publish(items[index], merge: merge)
        print("offline fail \(id) \(message)")
    }

    func failed(id: String, message: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard items[index].state == "running" || items[index].state == "queued" || items[index].state == "paused" else { return }
        items[index].state = "failed"
        items[index].error = message
        save()
        publish(items[index])
        finishWait(id: id, result: .failed(message))
        print("offline fail \(id) \(message)")
    }

    private func finishWait(id: String, result: TrackResult) {
        guard let waiter = waiters[id] else { return }
        waiters[id] = nil
        waiter.resume(returning: result)
    }

    private func drain() async {
        guard !draining else { return }
        draining = true
        defer { draining = false }
        while !jobs.isEmpty {
            let job = jobs.removeFirst()
            await run(job, video: nil)
        }
    }

    private func run(_ job: DownloadJob, video supplied: VideoItem?) async {
        let video: VideoItem
        if let supplied {
            video = supplied
        } else if let loaded = try? await client.detail(bvid: job.bvid) {
            video = loaded
        } else {
            return
        }
        for page in job.pages where page.cid > 0 {
            let id = Self.makeID(bvid: video.bvid, cid: page.cid)
            if items.contains(where: { $0.id == id && $0.state == "ready" }) { continue }
            if !items.contains(where: { $0.id == id }) {
                items.append(OfflineItem(
                    id: id,
                    bvid: video.bvid,
                    aid: video.aid,
                    cid: page.cid,
                    page: page.index,
                    pageTitle: page.title.isEmpty ? "P\(page.index)" : page.title,
                    title: video.title,
                    owner: video.ownerName,
                    duration: page.duration > 0 ? page.duration : video.duration,
                    quality: job.quality,
                    qn: QualityMap.qn(for: job.quality),
                    codec: job.codec,
                    state: "queued",
                    fraction: 0,
                    bytesWritten: 0,
                    bytesExpected: 0,
                    danmakuCount: 0,
                    error: ""
                ))
            }
            await fetchPart(id: id, video: video, page: page, quality: job.quality, codec: job.codec, limit: job.limit, cover: job.cover.isEmpty ? video.cover : job.cover)
        }
    }

    private func fetchPart(id: String, video: VideoItem, page: VideoPage, quality: String, codec: String, limit: Int64?, cover: String) async {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if let limit, OfflineFiles.usage() > limit {
            failed(id: id, message: "超过缓存上限")
            return
        }
        items[index].state = "running"
        items[index].error = ""
        save()
        publish(items[index])
        let qns = [QualityMap.qn(for: quality), 64, 32, 16]
        var offer: PlaybackOffer?
        for qn in qns where offer == nil {
            guard let found = try? await client.playback(
                bvid: video.bvid,
                cid: page.cid,
                qn: qn,
                tryLook: true,
                codecPreference: codec,
                audioPreference: "高码率"
            ), let media = found.audioURL, !media.isEmpty, Self.codecMatches(found.codec, preference: codec) else { continue }
            offer = found
        }
        guard let offer, let audioURL = offer.audioURL.flatMap(URL.init(string:)), let videoURL = URL(string: offer.videoURL) else {
            failed(id: id, message: "没有可用的音视频分轨")
            return
        }
        guard var current = items.first(where: { $0.id == id }) else { return }
        current.quality = offer.selectedName
        current.qn = offer.selectedQN
        current.codec = offer.codec
        replace(current)
        let xml = try? await client.danmakuDocument(cid: page.cid)
        if let xml {
            try? xml.write(to: OfflineFiles.danmaku(current), options: .atomic)
            current.danmakuCount = DanmakuXML.parse(xml).count
            replace(current)
        }
        if let remote = URL(string: cover), let (data, _) = try? await URLSession.shared.data(from: remote), !data.isEmpty {
            try? data.write(to: OfflineFiles.cover(current), options: .atomic)
        }
        let headers = BiliHTTP.assetHeaders(bvid: video.bvid)
        var pair = TrackPair()
        pair.wantsAudio = true
        pair.videoURL = videoURL
        pair.audioURL = audioURL
        pair.headers = headers
        tracks[id] = pair
        print("offline start \(video.bvid) \(page.cid) \(offer.selectedName) \(offer.codec)")
        DownloadBridge.shared.start(id: id, kind: "video", url: videoURL, headers: headers)
        DownloadBridge.shared.start(id: id, kind: "audio", url: audioURL, headers: headers)
        let timeout = Task { @MainActor in
            try? await Task.sleep(for: .seconds(180))
            self.finishWait(id: id, result: .failed("下载超时"))
        }
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<TrackResult, Never>) in
            if tracks[id]?.videoDone == true && tracks[id]?.audioDone == true {
                continuation.resume(returning: .files)
            } else {
                waiters[id] = continuation
            }
        }
        timeout.cancel()
        guard case .files = result, var done = items.first(where: { $0.id == id }) else { return }
        done.state = "merging"
        done.fraction = 1
        replace(done)
        publish(done)
        try? await Task.sleep(for: .seconds(2))
        let movie = OfflineFiles.movie(done)
        let videoFile = OfflineFiles.video(done)
        let audioFile = OfflineFiles.audio(done)
        let progress = Self.mergeProgress(id: id)
        FrameMonitor.shared.start()
        mergeOffset = 0
        let scrolling = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self else { return }
                self.mergeOffset += 1
            }
        }
        let clock = Date()
        var outcome = await OfflineRemux.shared.writeMovie(video: videoFile, audio: audioFile, to: movie, progress: progress)
        if !outcome.ok {
            print("offline remux drop audio")
            let retry = await OfflineRemux.shared.writeMovie(video: videoFile, audio: nil, to: movie, progress: progress)
            outcome = RemuxOutcome(ok: retry.ok, onMain: outcome.onMain || retry.onMain)
        }
        let workMs = Date().timeIntervalSince(clock) * 1000
        // The file is already written off the main actor. Stay in "merging" long enough
        // for the list to scroll and the display link to record a frame interval.
        try? await Task.sleep(for: .seconds(1))
        scrolling.cancel()
        let scrolls = mergeOffset
        let stats = FrameMonitor.shared.stop()
        let mergeMs = Date().timeIntervalSince(clock) * 1000
        let probe = MergeProbe(
            frames: stats.count,
            p95: (stats.p95Ms * 100).rounded() / 100,
            max: (stats.maxMs * 100).rounded() / 100,
            scrolls: scrolls,
            onMain: outcome.onMain,
            ms: (mergeMs * 100).rounded() / 100,
            workMs: (workMs * 100).rounded() / 100
        )
        print("offline merge main=\(probe.onMain) frames=\(probe.frames) p95=\(probe.p95) max=\(probe.max) scrolls=\(probe.scrolls) ms=\(probe.ms) workMs=\(probe.workMs)")
        guard outcome.ok else {
            mergeOffset = 0
            mergeFailed(id: id, message: "合成文件无法播放", merge: probe)
            return
        }
        done.state = "ready"
        done.fraction = 1
        done.error = ""
        done.bytesWritten = Int64((try? movie.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        replace(done)
        storageBytes = OfflineFiles.usage()
        save()
        mergeOffset = 0
        try? await Task.sleep(for: .milliseconds(400))
        publish(done, merge: probe)
        print("offline ready \(done.bvid) \(done.bytesWritten) danmaku \(done.danmakuCount)")
    }

    private func replace(_ item: OfflineItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }

    private func publish(_ item: OfflineItem, merge: MergeProbe? = nil) {
        OfflineProof.downloads(item, merge: merge)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: OfflineFiles.root.appendingPathComponent("index.json"), options: .atomic)
    }

    private static func load() -> [OfflineItem] {
        let url = OfflineFiles.root.appendingPathComponent("index.json")
        guard let data = try? Data(contentsOf: url), let items = try? JSONDecoder().decode([OfflineItem].self, from: data) else { return [] }
        return items
    }

    static func makeID(bvid: String, cid: Int) -> String { "\(bvid)|\(cid)" }

    private static func codecMatches(_ codec: String, preference: String) -> Bool {
        let value = codec.lowercased()
        switch preference.lowercased() {
        case "av1": return value.contains("av01") || value == "av1"
        case "hev1", "hevc", "hvc1": return value.contains("hvc") || value.contains("hev")
        default: return value.contains("avc")
        }
    }
}

private struct DownloadJob {
    var bvid: String
    var pages: [VideoPage]
    var quality: String
    var codec: String
    var limit: Int64?
    var cover: String
}

private struct TrackPair {
    var videoWritten: Int64 = 0
    var audioWritten: Int64 = 0
    var videoExpected: Int64 = 0
    var audioExpected: Int64 = 0
    var videoDone = false
    var audioDone = false
    var wantsAudio = false
    var videoURL: URL?
    var audioURL: URL?
    var headers: [String: String] = [:]
    var videoRecovered = false
    var audioRecovered = false

    var fraction: Double {
        let video = portion(written: videoWritten, expected: videoExpected)
        if !wantsAudio { return video }
        return (video + portion(written: audioWritten, expected: audioExpected)) / 2
    }

    private func portion(written: Int64, expected: Int64) -> Double {
        guard expected > 0 else { return written > 0 ? 0.05 : 0 }
        return min(1, Double(written) / Double(expected))
    }
}

private enum TrackResult {
    case files
    case failed(String)
    case cancelled
}
