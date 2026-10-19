import Foundation

enum LibraryRequest {
    static func orderCode(_ label: String) -> String {
        switch label {
        case "最多播放": "view"
        case "最近投稿": "pubtime"
        default: "mtime"
        }
    }

    static func folderQuery(mediaID: Int, page: Int, keyword: String, order: String) -> SignedForm {
        var fields = [
            "media_id": "\(mediaID)",
            "pn": "\(page)",
            "ps": "20"
        ]
        if !keyword.isEmpty { fields["keyword"] = keyword }
        if !order.isEmpty { fields["order"] = order }
        return SignedForm(method: "GET", path: "/x/v3/fav/resource/list", fields: fields)
    }

    static func batchUnfavorite(mediaID: Int, aids: [Int], csrf: String) -> SignedForm {
        SignedForm(method: "POST", path: "/x/v3/fav/resource/batch-del", fields: [
            "media_id": "\(mediaID)",
            "resources": aids.map { "\($0):2" }.joined(separator: ","),
            "csrf": csrf
        ])
    }

    static func bangumiFollow(vmid: Int, type: Int, page: Int) -> SignedForm {
        SignedForm(method: "GET", path: "/x/space/bangumi/follow/list", fields: [
            "type": "\(type)",
            "pn": "\(page)",
            "ps": "20",
            "vmid": "\(vmid)"
        ])
    }
}

enum LibraryRequestProof {
    static func writeAndExit() -> Never {
        let csrf = "jct-token"
        let cases: [(String, SignedForm, String, Bool)] = [
            ("fav-query", LibraryRequest.folderQuery(mediaID: 11, page: 1, keyword: "AI", order: "view"), "keyword=AI&media_id=11&order=view&pn=1&ps=20", false),
            ("fav-batch", LibraryRequest.batchUnfavorite(mediaID: 11, aids: [8, 9], csrf: csrf), "csrf=jct-token&media_id=11&resources=8%3A2%2C9%3A2", true),
            ("bangumi", LibraryRequest.bangumiFollow(vmid: 7, type: 1, page: 1), "pn=1&ps=20&type=1&vmid=7", false),
            ("series", SpaceRequest.series(mid: 42, page: 1), "mid=42&page_num=1&page_size=20", false)
        ]
        var failures: [String] = []
        var found: [[String: Any]] = []
        for (name, form, body, needsCSRF) in cases {
            found.append([
                "name": name,
                "method": form.method,
                "path": form.path,
                "body": form.body,
                "csrf": form.hasCSRF
            ])
            if form.body != body || form.hasCSRF != needsCSRF || form.endpoint == nil {
                failures.append("\(name) \(form.body)")
            }
        }
        let payload: [String: Any] = [
            "ok": failures.isEmpty,
            "checked": found.count,
            "failures": failures,
            "cases": found
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        try? data.write(to: LaunchClock.documents.appendingPathComponent("library-proof.json"), options: .atomic)
        if let text = String(data: data, encoding: .utf8) {
            print("LIBRARY_PROOF_BEGIN")
            print(text)
            print("LIBRARY_PROOF_END")
            fflush(stdout)
        }
        exit(failures.isEmpty ? 0 : 1)
    }
}

enum LibraryUIProof {
    static func record(_ payload: [String: Any]) {
        guard let screen = LaunchMode.screen, screen.hasPrefix("lib-") else { return }
        var body = payload
        body["screen"] = screen
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { return }
        try? data.write(to: LaunchClock.documents.appendingPathComponent("library-ui.json"), options: .atomic)
    }
}
