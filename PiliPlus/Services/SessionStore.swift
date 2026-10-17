import Foundation
import Security

/// Web cookies and the profile snapshot that came with them.
/// Cookie names follow upstream `cookie_info.cookies` (SESSDATA, bili_jct, DedeUserID).
struct BiliSession: Codable, Sendable, Equatable {
    var cookies: [String: String]
    var accessToken: String?
    var refreshToken: String?
    var mid: Int
    var name: String
    var face: String
    var level: Int
    var coins: Int
    var exp: Int
    var nextExp: Int
    var following: Int
    var followers: Int
    var dynamicCount: Int

    var csrf: String { cookies["bili_jct"] ?? "" }
    var sessdata: String { cookies["SESSDATA"] ?? "" }

    var cookieHeader: String {
        cookies
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: "; ")
    }

    var hasLoginCookie: Bool { !sessdata.isEmpty }

    static func make(
        cookies: [String: String],
        accessToken: String? = nil,
        refreshToken: String? = nil,
        mid: Int = 0
    ) -> BiliSession {
        BiliSession(
            cookies: cookies,
            accessToken: accessToken,
            refreshToken: refreshToken,
            mid: mid,
            name: "",
            face: "",
            level: 0,
            coins: 0,
            exp: 0,
            nextExp: 0,
            following: 0,
            followers: 0,
            dynamicCount: 0
        )
    }

    static func parseCookieHeader(_ raw: String) -> [String: String] {
        var result: [String: String] = [:]
        for part in raw.split(separator: ";") {
            let piece = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let eq = piece.firstIndex(of: "=") else { continue }
            let name = String(piece[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(piece[piece.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !value.isEmpty else { continue }
            result[name] = value
        }
        return result
    }
}

/// In-memory copy of the keychain session so requests can attach Cookie without a hop to the main actor.
final class SessionVault: @unchecked Sendable {
    static let shared = SessionVault()
    private let lock = NSLock()
    private var session: BiliSession?

    func current() -> BiliSession? {
        lock.lock()
        defer { lock.unlock() }
        return session
    }

    func cookieHeader() -> String? {
        let header = current()?.cookieHeader ?? ""
        return header.isEmpty ? nil : header
    }

    /// Remember a session already stored in the keychain.
    func install(_ session: BiliSession?) {
        lock.lock()
        self.session = session
        lock.unlock()
    }

    func replace(_ session: BiliSession?) {
        install(session)
        if let session {
            KeychainStore.save(session)
        } else {
            KeychainStore.clear()
        }
    }
}

enum KeychainStore {
    private static let service = "com.syiar.piliplus.session"
    private static let account = "main"

    static func load() -> BiliSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(BiliSession.self, from: data)
    }

    static func save(_ session: BiliSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            for (key, value) in attrs { add[key] = value }
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum DeviceIdentity {
    /// Upstream `LoginUtils.generateBuvid`: `XY` plus three hex digits plus the MD5.
    static var buvid: String {
        let key = "piliplus.buvid"
        if let existing = UserDefaults.standard.string(forKey: key), existing.hasPrefix("XY") {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let digest = InsecureMD5.hex(Data(bytes), uppercase: true)
        let chars = Array(digest)
        let value = "XY\(chars[2])\(chars[12])\(chars[22])\(digest)"
        UserDefaults.standard.set(value, forKey: key)
        return value
    }
}
