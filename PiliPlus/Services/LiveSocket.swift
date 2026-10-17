import Compression
import Foundation

struct LiveChatLine: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var text: String
    var born: Date
}

/// Bilibili live broadcast packet. Big-endian header, then a body.
/// Op 7 authenticates, op 2 is the heartbeat, op 5 carries notifications.
/// Body version 2 is zlib and version 3 is brotli; both wrap more packets.
enum LivePacket {
    private static var inflateLogs = 0
    struct Frame {
        var op: Int
        var body: Data
    }

    static func decode(_ data: Data, depth: Int = 0) -> [Frame] {
        guard depth < 6 else { return [] }
        let bytes = [UInt8](data)
        var found: [Frame] = []
        var offset = 0
        while offset + 16 <= bytes.count {
            let length = int32(bytes, offset)
            let header = int16(bytes, offset + 4)
            let version = int16(bytes, offset + 6)
            let op = int32(bytes, offset + 8)
            guard length >= 16, offset + length <= bytes.count else { break }
            let bodyStart = offset + (header >= 16 && header <= length ? header : 16)
            let body = Data(bytes[bodyStart..<(offset + length)])
            if op == 5 && (version == 2 || version == 3) {
                if let inflated = LiveInflate.decompress(body, brotli: version == 3) {
                    let nested = decode(inflated, depth: depth + 1)
                    if nested.isEmpty {
                        found.append(Frame(op: 5, body: inflated))
                    } else {
                        found.append(contentsOf: nested)
                    }
                } else if depth == 0, inflateLogs < 4 {
                    inflateLogs += 1
                    print("live danmu inflate failed \(body.count) ver \(version)")
                }
            } else if op == 5 {
                found.append(Frame(op: 5, body: body))
            }
            offset += length
        }
        return found
    }

    static func chatLine(in body: Data) -> LiveChatLine? {
        var body = body
        while body.last == 0 { body.removeLast() }
        if let brace = body.firstIndex(of: UInt8(ascii: "{")), brace > body.startIndex {
            body = Data(body[brace...])
        }
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        let cmd = object["cmd"] as? String ?? ""
        guard cmd == "DANMU_MSG" || cmd.hasPrefix("DANMU_MSG:") else { return nil }
        guard let info = object["info"] as? [Any], info.count > 1 else { return nil }
        let text = (info[1] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var name = ""
        if info.count > 2, let user = info[2] as? [Any], user.count > 1 {
            name = user[1] as? String ?? ""
        }
        return LiveChatLine(id: UUID().uuidString, name: name, text: text, born: Date())
    }

    static func authBody(room: Int, token: String, uid: Int) -> Data {
        let object: [String: Any] = [
            "uid": uid,
            "roomid": room,
            "protover": 3,
            "platform": "web",
            "type": 2,
            "key": token
        ]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    static func packet(op: UInt32, body: Data) -> Data {
        var data = Data()
        data.reserveCapacity(16 + body.count)
        append(&data, UInt32(16 + body.count).bigEndian)
        append(&data, UInt16(16).bigEndian)
        append(&data, UInt16(1).bigEndian)
        append(&data, op.bigEndian)
        append(&data, UInt32(1).bigEndian)
        data.append(body)
        return data
    }

    private static func append<T: FixedWidthInteger>(_ data: inout Data, _ value: T) {
        var value = value
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    private static func int32(_ bytes: [UInt8], _ offset: Int) -> Int {
        (Int(bytes[offset]) << 24) | (Int(bytes[offset + 1]) << 16) | (Int(bytes[offset + 2]) << 8) | Int(bytes[offset + 3])
    }

    private static func int16(_ bytes: [UInt8], _ offset: Int) -> Int {
        (Int(bytes[offset]) << 8) | Int(bytes[offset + 1])
    }
}

enum LiveInflate {
    static func decompress(_ source: Data, brotli: Bool) -> Data? {
        guard !source.isEmpty else { return Data() }
        let algorithm: compression_algorithm = brotli ? COMPRESSION_BROTLI : COMPRESSION_ZLIB
        return source.withUnsafeBytes { raw in
            guard let src = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
            let page = 128 * 1024
            let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: page)
            defer { destination.deallocate() }
            var stream = compression_stream(
                dst_ptr: destination,
                dst_size: page,
                src_ptr: src,
                src_size: source.count,
                state: nil
            )
            guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, algorithm) == COMPRESSION_STATUS_OK else {
                return nil
            }
            defer { compression_stream_destroy(&stream) }
            stream.src_ptr = src
            stream.src_size = source.count
            var output = Data()
            while output.count < 8_000_000 {
                stream.dst_ptr = destination
                stream.dst_size = page
                let result = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = page - stream.dst_size
                if produced > 0 { output.append(destination, count: produced) }
                if result == COMPRESSION_STATUS_END { return output }
                if result == COMPRESSION_STATUS_OK {
                    if produced == 0 && stream.src_size == 0 { return output.isEmpty ? nil : output }
                    continue
                }
                return output.isEmpty ? nil : output
            }
            return output
        }
    }
}

@MainActor
@Observable
final class LiveDanmuFeed {
    private(set) var lines: [LiveChatLine] = []
    private(set) var count = 0
    @ObservationIgnored private var socket: LiveSocket?

    func connect(room: Int, info: LiveDanmuInfo) {
        socket?.stop()
        let socket = LiveSocket(room: room, token: info.token, hosts: info.hosts)
        socket.onLine = { [weak self] line in
            self?.append(line)
        }
        self.socket = socket
        socket.start()
    }

    func stop() {
        socket?.stop()
        socket = nil
    }

    private func append(_ line: LiveChatLine) {
        lines.append(line)
        if lines.count > 240 {
            lines.removeFirst(lines.count - 240)
        }
        count += 1
        if count == 1 || count % 10 == 0 {
            print("live danmu count \(count)")
        }
    }
}

@MainActor
final class LiveSocket {
    var onLine: ((LiveChatLine) -> Void)?
    private let room: Int
    private let token: String
    private let hosts: [LiveDanmuHost]
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var heartbeat: Task<Void, Never>?
    private var hostIndex = 0
    private var stopped = false
    private var loggedPackets = 0
    private var loggedCommands = 0
    private var gotPacket = false
    private var switchTask: Task<Void, Never>?

    init(room: Int, token: String, hosts: [LiveDanmuHost]) {
        self.room = room
        self.token = token
        self.hosts = hosts
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }

    func start() {
        guard heartbeat == nil else { return }
        stopped = false
        open(0)
        armSwitch()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                self?.send(op: 2, body: Data())
            }
        }
    }

    func stop() {
        stopped = true
        heartbeat?.cancel()
        heartbeat = nil
        switchTask?.cancel()
        switchTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session.invalidateAndCancel()
    }

    private func open(_ index: Int) {
        guard !stopped, hosts.indices.contains(index) else { return }
        hostIndex = index
        loggedPackets = 0
        loggedCommands = 0
        gotPacket = false
        let host = hosts[index]
        guard let url = URL(string: "wss://\(host.host):\(host.wssPort)/sub") else {
            open(index + 1)
            return
        }
        task?.cancel(with: .goingAway, reason: nil)
        var request = URLRequest(url: url)
        request.setValue("https://live.bilibili.com", forHTTPHeaderField: "Origin")
        request.setValue(BiliHTTP.pcUserAgent, forHTTPHeaderField: "User-Agent")
        let cookie = BiliHTTP.mergedCookie(includeSession: true, override: nil)
        if !cookie.isEmpty { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        let uid = SessionVault.shared.current()?.mid ?? 0
        send(op: 7, body: LivePacket.authBody(room: room, token: token, uid: uid))
        send(op: 2, body: Data())
        print("live danmu connect \(host.host):\(host.wssPort)")
        receive(task)
    }

    private func receive(_ socket: URLSessionWebSocketTask) {
        socket.receive { [weak self] result in
            Task { @MainActor in
                guard let self, !self.stopped, self.task === socket else { return }
                switch result {
                case .success(let message):
                    switch message {
                    case .data(let data): self.ingest(data)
                    case .string(let text): self.ingest(Data(text.utf8))
                    @unknown default: break
                    }
                    self.receive(socket)
                case .failure(let error):
                    print("live danmu failed \(error.localizedDescription)")
                    self.open(self.hostIndex + 1)
                }
            }
        }
    }

    private func ingest(_ data: Data) {
        gotPacket = true
        let frames = LivePacket.decode(data)
        if loggedPackets < 3 {
            loggedPackets += 1
            print("live danmu packet \(data.count) frames \(frames.count)")
        }
        if frames.isEmpty {
            if let line = LivePacket.chatLine(in: data) { note(line) }
            return
        }
        for frame in frames {
            if let line = LivePacket.chatLine(in: frame.body) {
                note(line)
            } else if loggedCommands < 8 {
                loggedCommands += 1
                print("live danmu cmd \(Self.command(in: frame.body))")
            }
        }
    }

    private func note(_ line: LiveChatLine) {
        switchTask?.cancel()
        onLine?(line)
    }

    /// Leave a host only when it sends nothing. A live socket keeps chat on the first host that answers.
    private func armSwitch() {
        switchTask?.cancel()
        switchTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, !self.gotPacket, !self.stopped else { return }
            let next = self.hostIndex + 1
            guard self.hosts.indices.contains(next) else { return }
            print("live danmu silent, next host")
            self.open(next)
            self.armSwitch()
        }
    }

    private static func command(in body: Data) -> String {
        var bytes = body
        while bytes.last == 0 { bytes.removeLast() }
        if let brace = bytes.firstIndex(of: UInt8(ascii: "{")) {
            bytes = Data(bytes[brace...])
        }
        guard let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
            return "\(body.count)b"
        }
        let cmd = object["cmd"] as? String ?? "?"
        guard let info = object["info"] as? [Any], info.count > 1 else { return cmd }
        let kind = String(describing: type(of: info[1]))
        return "\(cmd) info1 \(kind)"
    }

    private func send(op: UInt32, body: Data) {
        let packet = LivePacket.packet(op: op, body: body)
        task?.send(.data(packet)) { _ in }
    }
}
