import UIKit

/// Downsamples covers away from the main thread and keeps the bitmaps in memory.
/// Feed scrolling should upload a ready image instead of decoding a full JPEG on the UI thread.
actor ImageStore {
    static let shared = ImageStore()

    /// Thread-safe bitmap cache. Views read it synchronously so a prepared
    /// cover can appear without a main-thread decode or a later state update.
    nonisolated(unsafe) static let storage = NSCache<NSString, UIImage>()
    nonisolated(unsafe) static var prepareHits = 0
    nonisolated(unsafe) static var prepareMisses = 0
    nonisolated(unsafe) static var preparedCount = 0

    private var inflight: [String: Task<UIImage?, Never>] = [:]

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 160 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpAdditionalHeaders = [
            "Referer": "https://www.bilibili.com",
            "User-Agent": BiliHTTP.userAgent
        ]
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    init() {
        Self.storage.countLimit = 240
        Self.storage.totalCostLimit = 48 * 1024 * 1024
    }

    nonisolated static func cacheKey(url: URL, maxPixel: CGFloat) -> String {
        "\(url.absoluteString)#\(Int(maxPixel))"
    }

    nonisolated static func cachedImage(url: URL, maxPixel: CGFloat) -> UIImage? {
        let image = storage.object(forKey: cacheKey(url: url, maxPixel: maxPixel) as NSString)
        if image != nil {
            prepareHits += 1
        } else {
            prepareMisses += 1
        }
        return image
    }

    func image(url: URL, maxPixel: CGFloat) async -> UIImage? {
        let key = Self.cacheKey(url: url, maxPixel: maxPixel)
        if let cached = Self.storage.object(forKey: key as NSString) {
            return cached
        }
        if let existing = inflight[key] { return await existing.value }
        let session = self.session
        let task = Task.detached(priority: .userInitiated) { () -> UIImage? in
            await ImageDecoder.load(session: session, url: url, maxPixel: maxPixel)
        }
        inflight[key] = task
        let loaded = await task.value
        inflight[key] = nil
        if let loaded {
            let cost = (loaded.cgImage?.width ?? 0) * (loaded.cgImage?.height ?? 0) * 4
            Self.storage.setObject(loaded, forKey: key as NSString, cost: max(cost, 1))
        }
        return loaded
    }

    /// Decode a window of covers concurrently. The decode gate still caps parallelism.
    func prepare(urls: [String], maxPixel: CGFloat) async {
        let unique = Array(Set(urls.filter { !$0.isEmpty }))
        let ready = await withTaskGroup(of: Int.self) { group in
            for raw in unique {
                guard let url = URL(string: raw) else { continue }
                group.addTask { await self.image(url: url, maxPixel: maxPixel) == nil ? 0 : 1 }
            }
            var count = 0
            for await item in group { count += item }
            return count
        }
        Self.preparedCount = ready
    }

    func prefetch(urls: [String], maxPixel: CGFloat) async {
        await prepare(urls: Array(urls.prefix(24)), maxPixel: maxPixel)
    }
}

private enum ImageDecoder {
    private static let gate = DecodeGate(limit: 3)

    static func load(session: URLSession, url: URL, maxPixel: CGFloat) async -> UIImage? {
        await gate.acquire()
        defer { Task { await gate.release() } }
        let data: Data?
        if url.isFileURL {
            data = try? Data(contentsOf: url, options: .mappedIfSafe)
        } else {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            data = try? await session.data(for: request).0
        }
        guard let data, !data.isEmpty else { return nil }
        return downsample(data: data, maxPixel: maxPixel)
    }

    static func downsample(data: Data, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(64, maxPixel),
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let image = UIImage(cgImage: cgImage)
        return image.preparingForDisplay() ?? image
    }
}

private actor DecodeGate {
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let limit: Int

    init(limit: Int) { self.limit = limit }

    func acquire() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            active -= 1
        }
    }
}
