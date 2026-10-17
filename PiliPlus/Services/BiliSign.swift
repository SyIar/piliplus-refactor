import Foundation
import CryptoKit

/// MD5 hex. WBI and the TV app sign both use this, matching upstream `crypto/md5`.
enum InsecureMD5 {
    static func hex(_ data: Data, uppercase: Bool = false) -> String {
        let digest = Insecure.MD5.hash(data: data)
        let text = digest.map { String(format: "%02x", $0) }.joined()
        return uppercase ? text.uppercased() : text
    }

    static func hex(_ text: String) -> String {
        hex(Data(text.utf8))
    }
}

enum PercentEncoding {
    /// `encodeURIComponent` / Dart `Uri.encodeComponent`.
    static func encodeURIComponent(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }
}

/// WBI query signing. Upstream `lib/utils/wbi_sign.dart`, table is the first 32 mixin indexes.
enum WBISigner {
    private static let mixinKeyEncTab = [
        46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49,
        33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13
    ]
    private static let stripped = CharacterSet(charactersIn: "!'()*")

    static func mixinKey(imgURL: String, subURL: String) -> String {
        let raw = fileStem(imgURL) + fileStem(subURL)
        let chars = Array(raw)
        var mixed = ""
        for index in mixinKeyEncTab where chars.indices.contains(index) {
            mixed.append(chars[index])
        }
        return mixed
    }

    static func sign(_ params: [String: String], mixinKey: String, now: Date = Date()) -> [String: String] {
        var signed = params
        signed["wts"] = String(Int(now.timeIntervalSince1970))
        let keys = signed.keys.sorted()
        let query = keys.map { key in
            let value = signed[key, default: ""].components(separatedBy: stripped).joined()
            return "\(PercentEncoding.encodeURIComponent(key))=\(PercentEncoding.encodeURIComponent(value))"
        }.joined(separator: "&")
        signed["w_rid"] = InsecureMD5.hex(query + mixinKey)
        return signed
    }

    private static func fileStem(_ url: String) -> String {
        var name = url.split(separator: "/").last.map(String.init) ?? ""
        if let dot = name.lastIndex(of: ".") {
            name = String(name[..<dot])
        }
        return name
    }
}

/// Android HD app sign used by upstream `LoginHttp.getHDcode` / `codePoll`.
enum AppSign {
    static let appKey = "dfca71928277209b"
    static let appSec = "b5475a8825547a4fc26c7d518eaaa02e"

    static func sign(_ params: [String: String], now: Date = Date()) -> [String: String] {
        var signed = params
        signed["appkey"] = appKey
        signed["ts"] = String(Int(now.timeIntervalSince1970))
        let query = signed.keys.sorted().map { key in
            let value = signed[key, default: ""]
            if value.isEmpty { return PercentEncoding.encodeURIComponent(key) }
            return "\(PercentEncoding.encodeURIComponent(key))=\(PercentEncoding.encodeURIComponent(value))"
        }.joined(separator: "&")
        signed["sign"] = InsecureMD5.hex(query + appSec)
        return signed
    }
}

enum WBICache {
    private static let dayKey = "piliplus.wbi.day"
    private static let mixinKey = "piliplus.wbi.mixin"

    static func load(now: Date = Date()) -> String? {
        let storedDay = UserDefaults.standard.string(forKey: dayKey)
        let stored = UserDefaults.standard.string(forKey: mixinKey)
        guard storedDay == dayStamp(now), let stored, !stored.isEmpty else { return nil }
        return stored
    }

    static func save(_ mixin: String, now: Date = Date()) {
        guard !mixin.isEmpty else { return }
        UserDefaults.standard.set(dayStamp(now), forKey: dayKey)
        UserDefaults.standard.set(mixin, forKey: mixinKey)
    }

    private static func dayStamp(_ date: Date) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
