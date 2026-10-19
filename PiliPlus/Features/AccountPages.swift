import SwiftUI

private enum AccountMids {
    static let likes = 8_047_632
    static let coins = 37_663_924
    static let articles = 8_047_632
    static let charge = 8_047_632
}

struct FollowManagePage: View {
    @Environment(AppModel.self) private var model
    @State private var mode = "全部关注"
    private let modes = ["全部关注", "特别关注", "悄悄关注", "互相关注", "分组"]

    var body: some View {
        VStack(spacing: 0) {
            Picker("关注", selection: $mode) {
                ForEach(modes, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            LoginPrompt(title: "登录后查看\(mode)", systemImage: "person.2")
        }
        .navigationTitle("关注")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            AccountManageUIProof.record([
                "state": "login",
                "rows": 0,
                "mode": mode,
                "modes": modes,
                "error": ""
            ])
        }
    }
}

struct BlacklistPage: View {
    var body: some View {
        LoginPrompt(title: "登录后查看黑名单", systemImage: "hand.raised")
            .navigationTitle("黑名单")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                AccountManageUIProof.record(["state": "login", "rows": 0, "error": ""])
            }
    }
}

struct LedgerPage: View {
    let title: String
    let symbol: String

    var body: some View {
        LoginPrompt(title: "登录后查看\(title)", systemImage: symbol)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                AccountManageUIProof.record(["state": "login", "rows": 0, "title": title, "error": ""])
            }
    }
}

struct DevicePage: View {
    var body: some View {
        LoginPrompt(title: "登录后查看登录设备", systemImage: "desktopcomputer")
            .navigationTitle("登录设备")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                AccountManageUIProof.record(["state": "login", "rows": 0, "error": ""])
            }
    }
}

struct ProfileEditorPage: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var sign = ""
    @State private var sex = "保密"
    @State private var birthday = ""

    var body: some View {
        Form {
            if !model.loggedIn {
                Section {
                    Text("登录后才能保存资料")
                        .foregroundStyle(.secondary)
                    Button("登录") { model.open(.login) }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.bili)
                }
            }
            Section("资料") {
                TextField("昵称", text: $name)
                TextField("签名", text: $sign)
                Picker("性别", selection: $sex) {
                    Text("保密").tag("保密")
                    Text("男").tag("男")
                    Text("女").tag("女")
                }
                TextField("生日", text: $birthday)
            }
        }
        .navigationTitle("编辑资料")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("保存") {
                guard model.loggedIn else {
                    model.open(.login)
                    return
                }
            }
        }
        .onAppear {
            AccountManageUIProof.record([
                "state": model.loggedIn ? "editor" : "login",
                "editor": true,
                "name": name,
                "rows": 0,
                "error": ""
            ])
        }
    }
}

struct AccountSwitchPage: View {
    @Environment(AppModel.self) private var model
    private var saved: [SavedAccount] { AccountBook.accounts() }

    var body: some View {
        Group {
            if saved.isEmpty {
                ContentUnavailableView {
                    Label("当前未登录", systemImage: "person.crop.circle.badge.plus")
                } description: {
                    Text("添加账号后可以在这里切换")
                } actions: {
                    Button("添加账号") { model.open(.login) }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.bili)
                }
            } else {
                List(saved) { account in
                    Text(account.name).lineLimit(1)
                }
            }
        }
        .navigationTitle("切换账号")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            AccountManageUIProof.record([
                "state": saved.isEmpty ? "empty" : "rows",
                "rows": saved.count,
                "title": saved.isEmpty ? "当前未登录" : (saved.first?.name ?? ""),
                "error": ""
            ])
        }
    }
}

struct FanListPage: View {
    @Environment(AppModel.self) private var model
    @State private var people: [RelationPerson] = []
    @State private var failure = ""
    @State private var login = false
    @State private var note = ""
    @State private var followers = 0
    @State private var loading = true

    var body: some View {
        Group {
            if loading {
                ProgressView("正在加载粉丝")
            } else if login {
                VStack(spacing: 12) {
                    if followers > 0 {
                        Text(CountText.format(followers))
                            .font(.largeTitle.weight(.bold))
                        Text("公开粉丝")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ContentUnavailableView("登录后查看粉丝名单", systemImage: "person.2", description: Text(note))
                    Button("去登录") { model.open(.login) }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.bili)
                }
            } else if !failure.isEmpty {
                ContentUnavailableView("粉丝列表打不开", systemImage: "person.2.slash", description: Text(failure))
            } else {
                List(people) { person in
                    HStack(spacing: 12) {
                        RemoteImage(url: person.face, ratio: 1, maxPixel: 120)
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(person.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .layoutPriority(1)
                            if !person.sign.isEmpty {
                                Text(person.sign)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("粉丝")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        let result = await model.client.relationFans(mid: AccountMids.likes)
        people = result.people
        login = result.login
        note = result.note
        followers = result.followers
        loading = false
        if !result.people.isEmpty {
            await ImageStore.shared.prepare(urls: result.people.prefix(8).map(\.face), maxPixel: 120)
        }
        if result.login {
            AccountManageUIProof.record([
                "state": "login",
                "rows": 0,
                "names": [String](),
                "followers": result.followers,
                "note": result.note,
                "error": ""
            ])
        } else if result.people.isEmpty {
            failure = result.note
            AccountManageUIProof.record([
                "state": "error",
                "rows": 0,
                "names": [String](),
                "note": result.note,
                "error": result.note
            ])
        } else {
            AccountManageUIProof.record([
                "state": "rows",
                "rows": result.people.count,
                "names": result.people.prefix(8).map(\.name),
                "covers": ImageStore.preparedCount,
                "followers": result.followers,
                "note": "",
                "error": ""
            ])
        }
    }
}

struct RecentVideoPage: View {
    @Environment(AppModel.self) private var model
    let kind: String
    @State private var videos: [VideoItem] = []
    @State private var owner = ""
    @State private var failure = ""

    var body: some View {
        Group {
            if !failure.isEmpty {
                ContentUnavailableView(kind, systemImage: "play.rectangle", description: Text(failure))
            } else if videos.isEmpty {
                ProgressView("正在加载")
            } else {
                List(videos) { video in
                    AccountVideoRow(video: video)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(kind)
        .navigationSubtitle(owner)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        let mid = kind == "最近投币" ? AccountMids.coins : AccountMids.likes
        do {
            if let profile = try? await model.client.spaceProfile(mid: mid) {
                owner = profile.name
            }
            let rows = kind == "最近投币" ? try await model.client.recentCoins(mid: mid) : try await model.client.recentLikes(mid: mid)
            videos = rows
            await ImageStore.shared.prepare(urls: rows.prefix(8).map(\.cover), maxPixel: 320)
            let ready = !rows.isEmpty && rows.allSatisfy(AccountReads.realVideo)
            AccountManageUIProof.record([
                "state": ready ? "rows" : "empty",
                "rows": rows.count,
                "title": kind,
                "name": owner,
                "titles": rows.prefix(6).map(\.title),
                "bvids": rows.prefix(6).map(\.bvid),
                "covers": ImageStore.preparedCount,
                "error": ready ? "" : "没有公开的\(kind)"
            ])
        } catch {
            failure = error.localizedDescription
            AccountManageUIProof.record(["state": "error", "rows": 0, "name": owner, "error": failure])
        }
    }
}

struct ArticleListPage: View {
    @Environment(AppModel.self) private var model
    let mid: Int
    @State private var articles: [ArticleCard] = []
    @State private var failure = ""

    var body: some View {
        Group {
            if !failure.isEmpty {
                ContentUnavailableView("专栏打不开", systemImage: "doc.text", description: Text(failure))
            } else if articles.isEmpty {
                ProgressView("正在加载专栏")
            } else {
                List(articles) { article in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(article.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        if !article.author.isEmpty {
                            Text(article.author)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if !article.summary.isEmpty {
                            Text(article.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("专栏")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            let rows = try await model.client.spaceArticles(mid: mid)
            articles = rows
            await ImageStore.shared.prepare(urls: rows.prefix(6).map(\.cover), maxPixel: 320)
            AccountManageUIProof.record([
                "state": rows.isEmpty ? "empty" : "rows",
                "rows": rows.count,
                "titles": rows.prefix(4).map(\.title),
                "covers": ImageStore.preparedCount,
                "error": rows.isEmpty ? "没有专栏" : ""
            ])
        } catch {
            failure = error.localizedDescription
            AccountManageUIProof.record(["state": "error", "rows": 0, "error": failure])
        }
    }
}

struct RankListPage: View {
    @Environment(AppModel.self) private var model
    let title: String
    @State private var people: [RankPerson] = []
    @State private var headline = ""
    @State private var failure = ""

    var body: some View {
        Group {
            if !failure.isEmpty {
                ContentUnavailableView(title, systemImage: "list.number", description: Text(failure))
            } else if people.isEmpty {
                ProgressView("正在加载")
            } else {
                List(people) { person in
                    HStack(spacing: 12) {
                        Text("\(person.rank)")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 28, alignment: .leading)
                        RemoteImage(url: person.face, ratio: 1, maxPixel: 120)
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())
                        Text(person.name)
                            .font(.subheadline)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(headline.isEmpty ? title : headline)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            let rows: [RankPerson]
            if title == "大航海" {
                guard let found = await model.client.busiestGuards() else {
                    failure = "没有开着的大航海榜"
                    AccountManageUIProof.record(["state": "empty", "rows": 0, "error": failure])
                    return
                }
                headline = found.room.uname
                rows = found.people
            } else {
                rows = try await model.client.chargeRank(mid: AccountMids.charge)
            }
            people = rows
            await ImageStore.shared.prepare(urls: rows.prefix(8).map(\.face), maxPixel: 120)
            let names = rows.prefix(6).map(\.name)
            let ready = rows.count >= 1 && names.allSatisfy { !$0.isEmpty && !LocalLibrary.isFixture(VideoItem(bvid: "BV1real", aid: 1, cid: 0, title: $0, cover: "", duration: 0, ownerName: $0, ownerMid: 0, ownerFace: "", desc: "", pubdate: 0, view: 0, danmaku: 0, like: 0, coin: 0, favorite: 0, share: 0, reply: 0, pages: [], tname: "")) }
            AccountManageUIProof.record([
                "state": ready ? "rows" : "empty",
                "rows": rows.count,
                "name": headline,
                "names": names,
                "covers": ImageStore.preparedCount,
                "error": ready ? "" : "榜单是空的"
            ])
        } catch {
            failure = error.localizedDescription
            AccountManageUIProof.record(["state": "error", "rows": 0, "error": failure])
        }
    }
}

struct ShopTabNote: View {
    let message: String
    var body: some View {
        if message == "login" {
            LoginPrompt(title: "登录后查看小店", systemImage: "bag")
        } else {
            ContentUnavailableView("小店", systemImage: "bag", description: Text(message.isEmpty ? "没有公开小店" : message))
        }
    }
}

struct ComicTabNote: View {
    let message: String
    var body: some View {
        ContentUnavailableView("漫画", systemImage: "book", description: Text(message))
    }
}
