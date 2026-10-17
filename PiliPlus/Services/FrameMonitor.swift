import QuartzCore
import UIKit

/// Records display-link intervals while a scripted scroll is running.
/// The first sample after start is dropped; it usually includes the gap
/// between scheduling the link and the next refresh.
final class FrameMonitor: NSObject {
    static let shared = FrameMonitor()

    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var samples: [Double] = []
    private(set) var refreshHz: Double = 60

    func start() {
        samples.removeAll(keepingCapacity: true)
        last = 0
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() -> FrameStats {
        link?.invalidate()
        link = nil
        return FrameStats(samples: samples, refreshHz: refreshHz)
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        if last > 0 {
            let ms = (now - last) * 1000
            if ms > 0.4, ms < 500 { samples.append(ms) }
        }
        last = now
        if link.duration > 0 {
            refreshHz = 1 / link.duration
        }
    }
}

struct FrameStats {
    var count: Int
    var avgMs: Double
    var p50Ms: Double
    var p95Ms: Double
    var p99Ms: Double
    var maxMs: Double
    var hitchOver20: Int
    var hitchOver33: Int
    var refreshHz: Double

    init(samples: [Double], refreshHz: Double) {
        let sorted = samples.sorted()
        count = sorted.count
        self.refreshHz = refreshHz
        if sorted.isEmpty {
            avgMs = 0
            p50Ms = 0
            p95Ms = 0
            p99Ms = 0
            maxMs = 0
            hitchOver20 = 0
            hitchOver33 = 0
            return
        }
        avgMs = sorted.reduce(0, +) / Double(sorted.count)
        p50Ms = Self.percentile(sorted, 0.50)
        p95Ms = Self.percentile(sorted, 0.95)
        p99Ms = Self.percentile(sorted, 0.99)
        maxMs = sorted.last ?? 0
        hitchOver20 = sorted.filter { $0 > 20 }.count
        hitchOver33 = sorted.filter { $0 > 33 }.count
    }

    var dictionary: [String: Any] {
        [
            "frames": count,
            "avgMs": rounded(avgMs),
            "p50Ms": rounded(p50Ms),
            "p95Ms": rounded(p95Ms),
            "p99Ms": rounded(p99Ms),
            "maxMs": rounded(maxMs),
            "hitchOver20": hitchOver20,
            "hitchOver33": hitchOver33,
            "refreshHz": rounded(refreshHz)
        ]
    }

    private func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = Int((Double(sorted.count - 1) * p).rounded())
        return sorted[min(max(0, index), sorted.count - 1)]
    }
}
