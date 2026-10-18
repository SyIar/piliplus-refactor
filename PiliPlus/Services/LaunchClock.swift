import Darwin
import Foundation
import SwiftUI
import UIKit

/// Cold-start and first-frame timing. Process start comes from the kernel
/// proc table so the number includes dynamic linker work before `main`.
enum LaunchClock {
    static let processStartWall: TimeInterval = processStartDate()
    private(set) static var mainWall: TimeInterval = 0
    private(set) static var firstFrameWall: TimeInterval?
    private static var waiters: [CheckedContinuation<Void, Never>] = []

    static func markMain() {
        if mainWall == 0 { mainWall = Date().timeIntervalSince1970 }
        _ = processStartWall
    }

    static func markFirstFrame() {
        guard firstFrameWall == nil else { return }
        firstFrameWall = Date().timeIntervalSince1970
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
        if LaunchMode.perfStartup {
            write(["phase": "startup"])
            // Let the write hit the simulator filesystem before exiting.
            fflush(stdout)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                exit(0)
            }
        }
    }

    static func waitForFirstFrame() async {
        if firstFrameWall != nil { return }
        await withCheckedContinuation { continuation in
            if firstFrameWall != nil {
                continuation.resume()
            } else {
                waiters.append(continuation)
            }
        }
    }

    static var processToFirstFrameMs: Double? {
        guard let firstFrameWall else { return nil }
        return (firstFrameWall - processStartWall) * 1000
    }

    static var mainToFirstFrameMs: Double? {
        guard let firstFrameWall, mainWall > 0 else { return nil }
        return (firstFrameWall - mainWall) * 1000
    }

    static func write(_ extra: [String: Any]) {
        var payload: [String: Any] = extra
        payload["processToFirstFrameMs"] = processToFirstFrameMs ?? -1
        payload["mainToFirstFrameMs"] = mainToFirstFrameMs ?? -1
        payload["device"] = deviceName()
        if let label = LaunchMode.label { payload["label"] = label }
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        let url = documents.appendingPathComponent("perf.json")
        try? data.write(to: url, options: .atomic)
        if let text = String(data: data, encoding: .utf8) {
            print("PERF_JSON_BEGIN")
            print(text)
            print("PERF_JSON_END")
            fflush(stdout)
        }
    }

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static func deviceName() -> String {
        var system = utsname()
        uname(&system)
        return withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }

    private static func processStartDate() -> TimeInterval {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let result = mib.withUnsafeMutableBufferPointer { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return -1 }
            return sysctl(base, u_int(buffer.count), &info, &size, nil, 0)
        }
        if result == 0 {
            let sec = TimeInterval(info.kp_proc.p_starttime.tv_sec)
            let usec = TimeInterval(info.kp_proc.p_starttime.tv_usec)
            return sec + usec / 1_000_000
        }
        return Date().timeIntervalSince1970
    }
}

enum HomeProof {
    static func record(_ payload: [String: Any]) {
        guard let screen = LaunchMode.screen, ["home", "rank", "bangumi", "cinema"].contains(screen) else { return }
        var body = payload
        body["screen"] = screen
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { return }
        let url = LaunchClock.documents.appendingPathComponent("home-proof.json")
        try? data.write(to: url, options: .atomic)
    }
}

enum LaunchMode {
    private static var args: [String] { ProcessInfo.processInfo.arguments }

    static var screen: String? {
        guard let index = args.firstIndex(of: "-screen"), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    static var perfStartup: Bool { args.contains("-perfStartup") }
    static var perfScroll: Bool { args.contains("-perfScroll") }
    static var searchCapture: (tab: String, keyword: String, type: String)? {
        switch screen {
        case "search-video": return ("视频", "原神", "video")
        case "search-user": return ("用户", "罗翔", "bili_user")
        case "search-bangumi": return ("番剧", "名侦探柯南", "media_bangumi")
        case "search-live": return ("直播间", "原神", "live_room")
        case "search-article": return ("专栏", "原神", "article")
        default: return nil
        }
    }

    static var accountPreview: Bool {
        switch screen {
        case "history", "later", "fav", "favsheet": return true
        default: return false
        }
    }

    static var usesFixtures: Bool {
        if screen == "playback" || screen == "home" || screen == "rank" || screen == "bangumi" || screen == "cinema" {
            return false
        }
        if screen == "accountProof" || screen == "socialProof" || screen == "spaceProof" || screen == "comments" { return false }
        if screen?.hasPrefix("guest-") == true || screen?.hasPrefix("search-") == true { return false }
        if screen == "space" || screen?.hasPrefix("space-") == true { return false }
        if screen == "live" || screen == "live-area" || screen == "live-room" || screen == "liveProof" { return false }
        if screen == "sponsor" || screen == "sponsor-settings" { return false }
        if screen == "downloads" || screen == "offline" { return false }
        if screen == "messageProof" || screen == "messages" { return false }
        if screen == "playbackExtra" || screen == "resume" || screen == "autoplay" || screen == "bangumi-play" { return false }
        if screen == "chapters" || screen == "scrub" || screen == "sleep" { return false }
        if perfScroll { return false }
        return screen != nil || perfStartup
    }
    static var label: String? {
        guard let index = args.firstIndex(of: "-perfLabel"), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    /// Simulator builds often cannot decode the AV1 rendition. The playback
    /// screenshot pass asks for AVC so a real frame can advance.
    static func playbackCodec(preferred: String) -> String {
        let forced = screen == "playback" || screen == "sponsor" || screen == "resume" || screen == "autoplay"
            || screen == "bangumi-play" || screen == "chapters" || screen == "scrub" || screen == "sleep"
        guard forced, ProcessInfo.processInfo.environment["SIMULATOR_UDID"] != nil else {
            return preferred
        }
        return "avc1"
    }
}

/// Fires on the first display refresh after the root view is in a window.
/// That is the splash-to-first-frame point we report.
struct FirstFrameProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {}
}

final class ProbeView: UIView {
    private var link: CADisplayLink?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick() {
        link?.invalidate()
        link = nil
        LaunchClock.markFirstFrame()
    }
}
