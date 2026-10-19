import Foundation

/// Publish, repost, like, topic, and detail calls before they touch the network.
enum DynamicRequest {
    static let features = "itemOpusStyle"
    static let likeURL = "https://api.vc.bilibili.com/dynamic_like/v1/dynamic_like/thumb"
    static let repostURL = "https://api.vc.bilibili.com/dynamic_repost/v1/dynamic_repost/repost"
    static let uploadPath = "/x/dynamic/feed/draw/upload_bfs"

    static func detailQuery(id: String) -> String {
        SignedForm(method: "GET", path: "/x/polymer/web-dynamic/v1/detail", fields: [
            "timezone_offset": "-480",
            "id": id,
            "features": features
        ]).body
    }

    static func likeFields(dynamicID: String, liked: Bool, csrf: String) -> [String: String] {
        [
            "dynamic_id": dynamicID,
            "up": liked ? "1" : "2",
            "csrf": csrf
        ]
    }

    static func likeBody(dynamicID: String, liked: Bool, csrf: String) -> String {
        SignedForm(method: "POST", path: "/dynamic_like/v1/dynamic_like/thumb", fields: likeFields(dynamicID: dynamicID, liked: liked, csrf: csrf)).body
    }

    static func repostFields(dynamicID: String, content: String, csrf: String) -> [String: String] {
        [
            "dynamic_id": dynamicID,
            "content": content,
            "extension": "{\"emoji_type\":1}",
            "csrf": csrf
        ]
    }

    static func repostBody(dynamicID: String, content: String, csrf: String) -> String {
        SignedForm(method: "POST", path: "/dynamic_repost/v1/dynamic_repost/repost", fields: repostFields(dynamicID: dynamicID, content: content, csrf: csrf)).body
    }

    static func topicQuery(path: String, fields: [String: String]) -> String {
        SignedForm(method: "GET", path: path, fields: fields).body
    }

    static func createObject(text: String, images: [String], topicID: Int, topicName: String, repostID: String) -> [String: Any] {
        var dyn: [String: Any] = [
            "content": [
                "contents": [
                    ["biz_id": "", "raw_text": text, "type": 1]
                ]
            ],
            "scene": repostID.isEmpty ? (images.isEmpty ? 1 : 2) : 4
        ]
        if !images.isEmpty {
            dyn["pics"] = images.map { ["img_src": $0] }
        }
        if topicID > 0 || !topicName.isEmpty {
            dyn["topic"] = ["id": topicID, "name": topicName]
        }
        if !repostID.isEmpty {
            dyn["repost_src"] = ["dyn_id_str": repostID]
        }
        return ["dyn_req": dyn]
    }

    static func createBody(text: String, images: [String], topicID: Int, topicName: String, repostID: String) -> String {
        let object = createObject(text: text, images: images, topicID: topicID, topicName: topicName, repostID: repostID)
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return Self.utf8JSON(String(data: data, encoding: .utf8) ?? "")
    }

    /// `JSONSerialization` writes non-ASCII as `\uXXXX`. The create call sends the characters themselves.
    private static func utf8JSON(_ text: String) -> String {
        var output = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "\\",
               let marker = text.index(index, offsetBy: 1, limitedBy: text.endIndex),
               marker < text.endIndex,
               text[marker] == "u",
               let end = text.index(marker, offsetBy: 5, limitedBy: text.endIndex),
               let value = UInt32(text[text.index(after: marker)..<end], radix: 16) {
                if (0xD800...0xDBFF).contains(value),
                   let lowStart = text.index(end, offsetBy: 0, limitedBy: text.endIndex),
                   text[lowStart...].hasPrefix("\\u"),
                   let lowEnd = text.index(lowStart, offsetBy: 6, limitedBy: text.endIndex),
                   let low = UInt32(text[text.index(lowStart, offsetBy: 2)..<lowEnd], radix: 16),
                   (0xDC00...0xDFFF).contains(low) {
                    let combined = 0x10000 + (Int(value) - 0xD800) * 0x400 + (Int(low) - 0xDC00)
                    if let scalar = UnicodeScalar(combined) {
                        output.append(Character(scalar))
                        index = lowEnd
                        continue
                    }
                }
                if let scalar = UnicodeScalar(value) {
                    output.append(Character(scalar))
                    index = end
                    continue
                }
            }
            output.append(text[index])
            index = text.index(after: index)
        }
        return output
    }
}

enum DynamicRequestProof {
    struct Case: Sendable {
        var name: String
        var method: String
        var path: String
        var body: String
        var expect: String
        var csrf: Bool
    }

    static func cases() -> [Case] {
        let csrf = "jct-token"
        return [
            Case(name: "detail", method: "GET", path: "/x/polymer/web-dynamic/v1/detail", body: DynamicRequest.detailQuery(id: "99"), expect: "features=itemOpusStyle&id=99&timezone_offset=-480", csrf: false),
            Case(name: "like", method: "POST", path: "/dynamic_like/v1/dynamic_like/thumb", body: DynamicRequest.likeBody(dynamicID: "99", liked: true, csrf: csrf), expect: "csrf=jct-token&dynamic_id=99&up=1", csrf: true),
            Case(name: "unlike", method: "POST", path: "/dynamic_like/v1/dynamic_like/thumb", body: DynamicRequest.likeBody(dynamicID: "99", liked: false, csrf: csrf), expect: "csrf=jct-token&dynamic_id=99&up=2", csrf: true),
            Case(name: "repost", method: "POST", path: "/dynamic_repost/v1/dynamic_repost/repost", body: DynamicRequest.repostBody(dynamicID: "99", content: "转", csrf: csrf), expect: "content=%E8%BD%AC&csrf=jct-token&dynamic_id=99&extension=%7B%22emoji_type%22%3A1%7D", csrf: true),
            Case(name: "create", method: "POST", path: "/x/dynamic/feed/create/dyn", body: DynamicRequest.createBody(text: "你好", images: [], topicID: 0, topicName: "", repostID: ""), expect: "{\"dyn_req\":{\"content\":{\"contents\":[{\"biz_id\":\"\",\"raw_text\":\"你好\",\"type\":1}]},\"scene\":1}}", csrf: true),
            Case(name: "create-image", method: "POST", path: "/x/dynamic/feed/create/dyn", body: DynamicRequest.createBody(text: "看", images: ["https://i0.hdslb.com/a.jpg"], topicID: 0, topicName: "", repostID: ""), expect: "{\"dyn_req\":{\"content\":{\"contents\":[{\"biz_id\":\"\",\"raw_text\":\"看\",\"type\":1}]},\"pics\":[{\"img_src\":\"https://i0.hdslb.com/a.jpg\"}],\"scene\":2}}", csrf: true),
            Case(name: "create-repost", method: "POST", path: "/x/dynamic/feed/create/dyn", body: DynamicRequest.createBody(text: "转", images: [], topicID: 0, topicName: "", repostID: "99"), expect: "{\"dyn_req\":{\"content\":{\"contents\":[{\"biz_id\":\"\",\"raw_text\":\"转\",\"type\":1}]},\"repost_src\":{\"dyn_id_str\":\"99\"},\"scene\":4}}", csrf: true),
            Case(name: "topic-hot", method: "GET", path: "/x/topic/web/hot", body: DynamicRequest.topicQuery(path: "/x/topic/web/hot", fields: ["page_num": "1", "page_size": "20"]), expect: "page_num=1&page_size=20", csrf: false),
            Case(name: "topic-fav", method: "GET", path: "/x/topic/web/fav/list", body: DynamicRequest.topicQuery(path: "/x/topic/web/fav/list", fields: ["page_num": "1", "page_size": "20"]), expect: "page_num=1&page_size=20", csrf: false),
            Case(name: "upload", method: "POST", path: DynamicRequest.uploadPath, body: "category=daily&csrf=jct-token", expect: "category=daily&csrf=jct-token", csrf: true)
        ]
    }

    static func failures() -> [String] {
        var issues: [String] = []
        for item in cases() where item.body != item.expect || item.path.isEmpty {
            issues.append("\(item.name) body \(item.body)")
        }
        let blank = DynamicRequest.likeFields(dynamicID: "1", liked: true, csrf: "")
        let form = SignedForm(method: "POST", path: "/dynamic_like/v1/dynamic_like/thumb", fields: blank)
        if AccountRequest.isReady(form) {
            issues.append("empty csrf was treated as signed")
        }
        if !DynamicRequest.likeURL.contains("api.vc.bilibili.com") || !DynamicRequest.repostURL.contains("dynamic_repost") {
            issues.append("host")
        }
        return issues
    }

    static func writeAndExit() -> Never {
        let found = cases()
        let issues = failures()
        let payload: [String: Any] = [
            "ok": issues.isEmpty,
            "checked": found.count,
            "failures": issues
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        try? data.write(to: LaunchClock.documents.appendingPathComponent("dynamic-proof.json"), options: .atomic)
        if let text = String(data: data, encoding: .utf8) {
            print("DYNAMIC_PROOF_BEGIN")
            print(text)
            print("DYNAMIC_PROOF_END")
            fflush(stdout)
        }
        exit(issues.isEmpty ? 0 : 1)
    }
}

enum DynamicUIProof {
    static func record(_ payload: [String: Any]) {
        guard let screen = LaunchMode.screen, screen.hasPrefix("dyn-") else { return }
        var body = payload
        body["screen"] = screen
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { return }
        try? data.write(to: LaunchClock.documents.appendingPathComponent("dynamic-ui.json"), options: .atomic)
    }
}
