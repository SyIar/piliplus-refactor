import Darwin
import Foundation

struct CastDevice: Identifiable, Hashable, Sendable {
    var id: String { location }
    var name: String
    var location: String
}

struct ReleaseNote: Sendable {
    var tag: String
    var name: String
    var notes: String
    var page: String
}

enum GapProof {
    static func record(_ payload: [String: Any]) {
        guard let screen = LaunchMode.screen, screen.hasPrefix("gap-") else { return }
        var body = payload
        body["screen"] = screen
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { return }
        try? data.write(to: LaunchClock.documents.appendingPathComponent("gap-ui.json"), options: .atomic)
    }
}

enum ReleaseCheck {
    static var current: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return value.isEmpty ? "2.0.1" : value
    }

    static func latest() async throws -> ReleaseNote {
        guard let url = URL(string: "https://api.github.com/repos/SyIar/piliplus-refactor/releases/latest") else {
            throw BiliError.message("更新地址无效")
        }
        var request = URLRequest(url: url)
        request.setValue("PiliPlus/\(current)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if !LaunchMode.githubToken.isEmpty {
            request.setValue("Bearer \(LaunchMode.githubToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String ?? ""
            let detail = message.replacingOccurrences(of: "\n", with: " ")
            throw BiliError.message("更新检查失败 \(code) \(detail.prefix(80))")
        }
        let tag = object["tag_name"] as? String ?? ""
        let name = (object["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = object["body"] as? String ?? ""
        guard tag.hasPrefix("v"), !name.isEmpty, notes.trimmingCharacters(in: .whitespacesAndNewlines).count >= 12 else {
            throw BiliError.message("没有读到发行说明")
        }
        return ReleaseNote(tag: tag, name: name, notes: notes, page: object["html_url"] as? String ?? "")
    }

    static func headline(current: String, tag: String) -> String {
        switch VersionSort.compare(current, tag) {
        case .orderedAscending: return "有新版本"
        default: return "已是最新"
        }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
}

enum VersionSort {
    static func compare(_ local: String, _ remote: String) -> ComparisonResult {
        let left = parts(local)
        let right = parts(remote)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a < b { return .orderedAscending }
            if a > b { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func parts(_ raw: String) -> [Int] {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("v") { text.removeFirst() }
        return text.split(separator: ".").map { piece in
            Int(piece.prefix { $0.isNumber }) ?? 0
        }
    }
}

enum WebDAVStore {
    static func put(base: String, user: String, password: String, body: Data) async -> String {
        guard let url = endpoint(base) else { return "地址无效" }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("", forHTTPHeaderField: "Expect")
        authorize(&request, user: user, password: password)
        do {
            let (_, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else { return "写入失败 \(code)" }
            return "已备份"
        } catch {
            return error.localizedDescription
        }
    }

    static func get(base: String, user: String, password: String) async -> (Data?, String) {
        guard let url = endpoint(base) else { return (nil, "地址无效") }
        var request = URLRequest(url: url)
        authorize(&request, user: user, password: password)
        do {
            let (data, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code), !data.isEmpty else { return (nil, "读取失败 \(code)") }
            return (data, "已读取")
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    static func endpoint(_ base: String) -> URL? {
        var raw = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if !raw.contains("://") { raw = "https://" + raw }
        guard var parts = URLComponents(string: raw), parts.host != nil else { return nil }
        if parts.path.isEmpty || parts.path == "/" {
            parts.path = "/piliplus-settings.json"
        } else if !parts.path.hasSuffix(".json") {
            parts.path = parts.path.hasSuffix("/") ? parts.path + "piliplus-settings.json" : parts.path + "/piliplus-settings.json"
        }
        return parts.url
    }

    private static func authorize(_ request: inout URLRequest, user: String, password: String) {
        let name = user.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty || !password.isEmpty else { return }
        let token = Data("\(name):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
}

enum CastFinder {
    /// SSDP M-SEARCH for MediaRenderer. An empty list means the search finished with no device.
    static func search(timeout: TimeInterval = 2.4) async -> [CastDevice] {
        let seconds = timeout
        return await Task.detached(priority: .userInitiated) {
            discover(timeout: seconds)
        }.value
    }

    private static func discover(timeout: TimeInterval) -> [CastDevice] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { Darwin.close(fd) }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var local = sockaddr_in()
        local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        local.sin_family = sa_family_t(AF_INET)
        local.sin_port = 0
        local.sin_addr.s_addr = inet_addr("0.0.0.0")
        let bound = withUnsafePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return [] }
        var wait = timeval(tv_sec: 0, tv_usec: 400_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
        let targets = [
            "urn:schemas-upnp-org:device:MediaRenderer:1",
            "urn:schemas-upnp-org:service:AVTransport:1"
        ]
        for target in targets {
            let message = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 1\r\nST: \(target)\r\n\r\n"
            send(Array(message.utf8), fd: fd)
        }
        var found: [String: CastDevice] = [:]
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = [UInt8](repeating: 0, count: 2048)
        while Date() < deadline {
            let count = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return recv(fd, base, raw.count, 0)
            }
            guard count > 0 else { continue }
            let text = String(decoding: buffer.prefix(count), as: UTF8.self)
            guard let device = parse(text) else { continue }
            found[device.location] = device
        }
        return found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func send(_ bytes: [UInt8], fd: Int32) {
        var dest = sockaddr_in()
        dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = UInt16(1900).bigEndian
        dest.sin_addr.s_addr = inet_addr("239.255.255.250")
        bytes.withUnsafeBytes { buffer in
            withUnsafePointer(to: &dest) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sock in
                    _ = sendto(fd, buffer.baseAddress, buffer.count, 0, sock, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    private static func parse(_ text: String) -> CastDevice? {
        let lines = text.components(separatedBy: "\r\n")
        func field(_ name: String) -> String {
            let prefix = name.lowercased() + ":"
            guard let line = lines.first(where: { $0.lowercased().hasPrefix(prefix) }) else { return "" }
            return line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        }
        let location = field("location")
        guard location.lowercased().hasPrefix("http") else { return nil }
        let server = field("server")
        let name = server.isEmpty ? location : server
        return CastDevice(name: name, location: location)
    }
}

extension AppModel {
    func settingsArchive() -> Data? {
        var clean = values
        for key in Array(clean.keys) where key.contains("密码") {
            clean.removeValue(forKey: key)
        }
        let payload: [String: Any] = [
            "toggles": toggles,
            "values": clean,
            "theme": theme.rawValue,
            "homeTabs": homeTabs,
            "navItems": navItems,
            "searchHistory": searchHistory,
            "anonymity": anonymity
        ]
        return try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    @discardableResult
    func applySettingsArchive(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        guard object["values"] is [String: String] || object["toggles"] is [String: Bool] else { return false }
        let passwords = values.filter { $0.key.contains("密码") }
        if let toggles = object["toggles"] as? [String: Bool] { self.toggles = toggles }
        if let incoming = object["values"] as? [String: String] {
            var next = incoming.filter { !$0.key.contains("密码") }
            for (key, value) in passwords { next[key] = value }
            values = next
        }
        if let raw = object["theme"] as? String, let choice = ThemeChoice(rawValue: raw) { theme = choice }
        if let tabs = object["homeTabs"] as? [String], !tabs.isEmpty { homeTabs = tabs }
        if let items = object["navItems"] as? [String], !items.isEmpty { navItems = items }
        if let history = object["searchHistory"] as? [String] { searchHistory = history }
        if let flag = object["anonymity"] as? Bool { anonymity = flag }
        danmakuOn = flag("弹幕开关") || toggles["弹幕开关"] == nil
        save()
        return true
    }

    func backupSettingsToWebDAV() async -> String {
        guard let data = settingsArchive() else { return "设置无法打包" }
        return await WebDAVStore.put(
            base: values["WebDAV 地址"] ?? "",
            user: values["用户名"] ?? "",
            password: values["密码"] ?? "",
            body: data
        )
    }

    func restoreSettingsFromWebDAV() async -> String {
        let (data, status) = await WebDAVStore.get(
            base: values["WebDAV 地址"] ?? "",
            user: values["用户名"] ?? "",
            password: values["密码"] ?? ""
        )
        guard let data else { return status }
        return applySettingsArchive(data) ? "已恢复" : "备份不是设置文件"
    }

    func publicVideo(preferred bvid: String) async -> VideoItem? {
        if !bvid.isEmpty {
            if let cached = video(bvid), !LocalLibrary.isFixture(cached), cached.bvid.hasPrefix("BV") {
                return cached
            }
            if let loaded = try? await client.detail(bvid: bvid), !LocalLibrary.isFixture(loaded), loaded.bvid.hasPrefix("BV") {
                store(loaded)
                return loaded
            }
        }
        if feed.isEmpty { await loadRecommend(reset: true) }
        return feed.first { item in
            item.bvid.hasPrefix("BV")
                && !item.title.isEmpty
                && !item.ownerName.isEmpty
                && !item.cover.isEmpty
                && !LocalLibrary.isFixture(item)
        }
    }
}
