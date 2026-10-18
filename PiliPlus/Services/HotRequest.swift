import Foundation

struct WeeklyIssue: Identifiable, Hashable, Sendable {
    var id: Int { number }
    var number: Int
    var name: String
    var subject: String
}

enum HotRequest {
    static func issues() -> SignedForm {
        SignedForm(method: "GET", path: "/x/web-interface/popular/series/list", fields: [:])
    }

    static func issue(_ number: Int) -> SignedForm {
        SignedForm(method: "GET", path: "/x/web-interface/popular/series/one", fields: [
            "number": "\(number)"
        ])
    }

    static func precious() -> SignedForm {
        SignedForm(method: "GET", path: "/x/web-interface/popular/precious", fields: [:])
    }
}

enum HotRequestProof {
    static func writeAndExit() -> Never {
        let csrf = false
        let cases: [(String, SignedForm, String)] = [
            ("weekly-list", HotRequest.issues(), ""),
            ("weekly-one", HotRequest.issue(395), "number=395"),
            ("precious", HotRequest.precious(), "")
        ]
        var failures: [String] = []
        var found: [[String: Any]] = []
        for (name, form, body) in cases {
            let item: [String: Any] = [
                "name": name,
                "method": form.method,
                "host": "https://api.bilibili.com",
                "path": form.path,
                "body": form.body,
                "csrf": form.hasCSRF
            ]
            found.append(item)
            if form.method != "GET" || form.body != body || form.hasCSRF != csrf || form.endpoint == nil {
                failures.append(name)
            }
        }
        let payload: [String: Any] = [
            "ok": failures.isEmpty,
            "checked": found.count,
            "failures": failures,
            "cases": found
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        try? data.write(to: LaunchClock.documents.appendingPathComponent("hot-proof.json"), options: .atomic)
        if let text = String(data: data, encoding: .utf8) {
            print("HOT_PROOF_BEGIN")
            print(text)
            print("HOT_PROOF_END")
            fflush(stdout)
        }
        exit(failures.isEmpty ? 0 : 1)
    }
}

enum HotUIProof {
    static func record(_ payload: [String: Any]) {
        guard let screen = LaunchMode.screen, screen.hasPrefix("hot-") else { return }
        var body = payload
        body["screen"] = screen
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { return }
        try? data.write(to: LaunchClock.documents.appendingPathComponent("hot-ui.json"), options: .atomic)
    }
}
