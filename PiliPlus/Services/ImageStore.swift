import UIKit

/// Downsamples covers away from the main thread and keeps the bitmaps in memory.
/// Feed scrolling should upload a ready image instead of decoding a full JPEG on the UI thread.
actor ImageStore {
    static let shared = ImageStore()

    private let memory = NSCache<NSString, UIImage>()
    private var inflight: [String: Task<UIImage?, Never>] = [:]

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 160 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpAdditionalHeaders = [
            "Referer": "https://www.bilibili.com",
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 27_0 like Mac OS X) AppleWebKit/605.1.15"
        ]
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    init() {
        memory.countLimit = 240
        memory.totalCostLimit = 48 * 1024 * 1024
    }

    func image(url: URL, maxPixel: CGFloat) async -> UIImage? {
        let key = "\(url.absoluteString)#\(Int(maxPixel))"
        if let cached = memory.object(forKey: key as NSString) { return cached }
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
            memory.setObject(loaded, forKey: key as NSString, cost: max(cost, 1))
        }
        return loaded
    }

    /// Warm the first screen after the feed arrives. Later cells decode as they approach.
    func prefetch(urls: [String], maxPixel: CGFloat) async {
        for raw in urls.prefix(8) {
            guard let url = URL(string: raw) else { continue }
            _ = await image(url: url, maxPixel: maxPixel)
        }
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
