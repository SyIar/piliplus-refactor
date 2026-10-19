import SwiftUI

struct LiveRoomLine: View {
    let room: LiveRoom

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteImage(url: room.cover, maxPixel: 320)
                .frame(width: 128, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(room.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                VideoListMeta(owner: room.uname, viewCount: room.online, danmaku: 0, viewSymbol: "person.fill")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}

struct LiveAreaDetailPage: View {
    @Environment(AppModel.self) private var model
    let parentName: String
    @State private var parentID = 0
    @State private var parentTitle = ""
    @State private var children: [LiveAreaTag] = []
    @State private var selected = 0
    @State private var rooms: [LiveRoom] = []
    @State private var failure = ""
    @State private var loading = true

    var body: some View {
        VStack(spacing: 0) {
            if !children.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(children.prefix(24)) { child in
                            Button(child.name) { Task { await loadRooms(child) } }
                                .font(.caption.weight(selected == child.id ? .bold : .regular))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .foregroundStyle(selected == child.id ? .white : .primary)
                                .selectionCapsule(selected: selected == child.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
            Group {
                if loading && rooms.isEmpty {
                    ProgressView("正在加载分区")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if rooms.isEmpty {
                    ContentUnavailableView("这个分区没有直播", systemImage: "dot.radiowaves.left.and.right", description: Text(failure.isEmpty ? parentTitle : failure))
                } else {
                    List(rooms) { room in
                        Button { model.open(.live(room.id)) } label: {
                            LiveRoomLine(room: room)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
        }
        .navigationTitle(parentTitle.isEmpty ? parentName : parentTitle)
        .navigationSubtitle(children.first(where: { $0.id == selected })?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            let tree = try await model.client.liveAreaTags(parent: parentName)
            parentID = tree.id
            parentTitle = tree.name
            children = tree.children
            let child = tree.children.first { $0.name == "英雄联盟" } ?? tree.children[0]
            await loadRooms(child)
        } catch {
            loading = false
            failure = error.localizedDescription
            LiveExtraProof.record([
                "state": "error",
                "parent": parentName,
                "child": "",
                "rows": 0,
                "room": 0,
                "titles": [String](),
                "error": failure
            ])
        }
    }

    private func loadRooms(_ child: LiveAreaTag) async {
        selected = child.id
        loading = true
        failure = ""
        do {
            let rows = try await model.client.liveChildRooms(parent: parentID, area: child.id)
            rooms = rows
            loading = false
            await ImageStore.shared.prepare(urls: rows.prefix(6).map(\.cover), maxPixel: 320)
            LiveExtraProof.record([
                "state": rows.isEmpty ? "empty" : "rows",
                "parent": parentTitle,
                "child": child.name,
                "rows": rows.count,
                "room": rows.first?.id ?? 0,
                "titles": rows.prefix(6).map(\.title),
                "covers": ImageStore.preparedCount,
                "error": rows.isEmpty ? "这个分区现在没有直播" : ""
            ])
        } catch {
            rooms = []
            loading = false
            failure = error.localizedDescription
            LiveExtraProof.record([
                "state": "error",
                "parent": parentTitle,
                "child": child.name,
                "rows": 0,
                "room": 0,
                "titles": [String](),
                "error": failure
            ])
        }
    }
}

struct FollowedLivePage: View {
    @Environment(AppModel.self) private var model
    @State private var rooms: [LiveRoom] = []
    @State private var login = false
    @State private var note = ""
    @State private var loading = true

    var body: some View {
        Group {
            if loading {
                ProgressView("正在查看关注")
            } else if login {
                VStack(spacing: 16) {
                    ContentUnavailableView("登录后查看关注的直播", systemImage: "heart", description: Text(note))
                    Button("去登录") { model.open(.login) }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.bili)
                }
            } else if rooms.isEmpty {
                ContentUnavailableView("没有正在直播", systemImage: "dot.radiowaves.left.and.right", description: Text(note))
            } else {
                List(rooms) { room in
                    Button { model.open(.live(room.id)) } label: {
                        LiveRoomLine(room: room)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("关注的直播")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        let result = await model.client.followedLiveRooms()
        rooms = result.rooms
        login = result.login
        note = result.note
        loading = false
        if !result.rooms.isEmpty {
            await ImageStore.shared.prepare(urls: result.rooms.prefix(6).map(\.cover), maxPixel: 320)
        }
        let state = result.login ? "login" : (result.rooms.isEmpty ? "empty" : "rows")
        LiveExtraProof.record([
            "state": state,
            "rows": result.rooms.count,
            "titles": result.rooms.prefix(6).map(\.title),
            "note": result.note,
            "error": state == "empty" && result.note.isEmpty ? "没有正在直播" : ""
        ])
    }
}

struct LiveSearchPage: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var rooms: [LiveRoom] = []
    @State private var failure = ""
    @State private var searching = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("搜索直播间", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit { Task { await run() } }
                Button("搜索") { Task { await run() } }
                    .font(.subheadline.weight(.bold))
            }
            .padding(16)
            Group {
                if searching && rooms.isEmpty {
                    ProgressView("正在搜索")
                } else if rooms.isEmpty {
                    ContentUnavailableView("没有直播间", systemImage: "magnifyingglass", description: Text(failure.isEmpty ? "换个关键词试试" : failure))
                } else {
                    List(rooms) { room in
                        Button { model.open(.live(room.id)) } label: {
                            LiveRoomLine(room: room)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
        }
        .navigationTitle("搜索直播")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard LaunchMode.screen == "live-search" else { return }
            query = "原神"
            await run()
        }
    }

    private func run() async {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        searching = true
        failure = ""
        do {
            let rows = try await model.client.searchLiveRooms(keyword: keyword)
            rooms = rows
            searching = false
            await ImageStore.shared.prepare(urls: rows.prefix(6).map(\.cover), maxPixel: 320)
            LiveExtraProof.record([
                "state": rows.isEmpty ? "empty" : "rows",
                "query": keyword,
                "rows": rows.count,
                "titles": rows.prefix(6).map(\.title),
                "names": rows.prefix(6).map(\.uname),
                "covers": ImageStore.preparedCount,
                "error": rows.isEmpty ? "没有直播间" : ""
            ])
        } catch {
            rooms = []
            searching = false
            failure = error.localizedDescription
            LiveExtraProof.record([
                "state": "error",
                "query": keyword,
                "rows": 0,
                "titles": [String](),
                "error": failure
            ])
        }
    }
}

struct LiveBlockPage: View {
    @State private var words = LiveBlockList.words()
    @State private var draft = ""
    private let samples = ["这是广告", "你好"]

    var body: some View {
        List {
            Section("屏蔽词") {
                if words.isEmpty {
                    Text("还没有屏蔽词").foregroundStyle(.secondary)
                }
                ForEach(words, id: \.self) { word in
                    Text(word)
                }
                .onDelete { index in
                    for offset in index {
                        LiveBlockList.remove(words[offset])
                    }
                    words = LiveBlockList.words()
                }
                HStack {
                    TextField("添加屏蔽词", text: $draft)
                    Button("添加") { add(draft) }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            Section("过滤结果") {
                ForEach(samples, id: \.self) { line in
                    if LiveBlockList.allows(line) {
                        Text(line)
                    } else {
                        Text("已隐藏 \(line)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("弹幕屏蔽")
        .navigationBarTitleDisplayMode(.inline)
        .task { prove() }
    }

    private func add(_ raw: String) {
        LiveBlockList.add(raw)
        draft = ""
        words = LiveBlockList.words()
        prove()
    }

    private func prove() {
        if LaunchMode.screen == "live-block", !words.contains("广告") {
            LiveBlockList.add("广告")
            words = LiveBlockList.words()
        }
        let hidden = samples.filter { !LiveBlockList.allows($0) }
        let kept = samples.filter { LiveBlockList.allows($0) }
        LiveExtraProof.record([
            "state": "rows",
            "words": words,
            "hidden": hidden.count,
            "kept": kept.count,
            "hiddenText": hidden,
            "keptText": kept
        ])
    }
}

struct LiveRankPage: View {
    @Environment(AppModel.self) private var model
    @State private var people: [RankPerson] = []
    @State private var roomID = 0
    @State private var roomTitle = ""
    @State private var uid = 0
    @State private var kind = "online"
    @State private var failure = ""
    @State private var loading = true
    private let kinds = [("在线", "online"), ("今日", "today"), ("本周", "week"), ("本月", "month")]

    var body: some View {
        VStack(spacing: 0) {
            Picker("榜单", selection: $kind) {
                ForEach(kinds, id: \.1) { item in
                    Text(item.0).tag(item.1)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Group {
                if loading && people.isEmpty {
                    ProgressView("正在加载高能榜")
                } else if people.isEmpty {
                    ContentUnavailableView("高能榜没有打开", systemImage: "chart.bar", description: Text(failure))
                } else {
                    List(people) { person in
                        HStack(spacing: 12) {
                            Text("\(person.rank)")
                                .font(.subheadline.weight(.bold))
                                .frame(width: 28)
                            ProfileMark(name: person.name, face: person.face, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(person.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                if let score = Int(person.detail), score > 0 {
                                    Text(CountText.format(score))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .navigationTitle("高能榜")
        .navigationSubtitle(roomTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await prepare() }
        .onChange(of: kind) { _, _ in Task { await reload() } }
    }

    private func prepare() async {
        if model.liveFocusRoom > 0 {
            roomID = model.liveFocusRoom
            uid = model.liveFocusUID
            roomTitle = model.liveFocusTitle
            if uid == 0, let info = try? await model.client.liveRoomInfo(room: roomID) {
                uid = info.mid
                if roomTitle.isEmpty { roomTitle = info.title }
            }
            await reload()
            return
        }
        let seeds = (try? await model.client.popularLiveRooms()) ?? []
        var last = "高能榜没有打开"
        for room in seeds.prefix(4) where room.mid > 0 && !room.title.isEmpty {
            roomID = room.id
            uid = room.mid
            roomTitle = room.title
            do {
                let rows = try await model.client.liveContribution(room: room.id, uid: room.mid, kind: kind)
                people = rows
                loading = false
                await ImageStore.shared.prepare(urls: rows.prefix(8).map(\.face), maxPixel: 120)
                LiveExtraProof.record([
                    "state": "rows",
                    "rows": rows.count,
                    "room": roomID,
                    "title": roomTitle,
                    "kind": kind,
                    "names": rows.prefix(8).map(\.name),
                    "covers": ImageStore.preparedCount,
                    "error": ""
                ])
                return
            } catch {
                last = error.localizedDescription
            }
        }
        loading = false
        failure = last
        LiveExtraProof.record(["state": "error", "rows": 0, "room": roomID, "title": roomTitle, "names": [String](), "error": failure])
    }

    private func reload() async {
        guard roomID > 0, uid > 0 else {
            loading = false
            failure = "没有可用的直播间"
            LiveExtraProof.record(["state": "error", "rows": 0, "room": roomID, "title": roomTitle, "names": [String](), "error": failure])
            return
        }
        loading = people.isEmpty
        do {
            let rows = try await model.client.liveContribution(room: roomID, uid: uid, kind: kind)
            people = rows
            loading = false
            await ImageStore.shared.prepare(urls: rows.prefix(8).map(\.face), maxPixel: 120)
            LiveExtraProof.record([
                "state": "rows",
                "rows": rows.count,
                "room": roomID,
                "title": roomTitle,
                "kind": kind,
                "names": rows.prefix(8).map(\.name),
                "covers": ImageStore.preparedCount,
                "error": ""
            ])
        } catch {
            people = []
            loading = false
            failure = error.localizedDescription
            LiveExtraProof.record([
                "state": "error",
                "rows": 0,
                "room": roomID,
                "title": roomTitle,
                "names": [String](),
                "error": failure
            ])
        }
    }
}

struct LiveSuperChatPage: View {
    @Environment(AppModel.self) private var model
    @State private var chats: [LiveSuperChat] = []
    @State private var roomID = 0
    @State private var roomTitle = ""
    @State private var note = ""
    @State private var loading = true

    var body: some View {
        Group {
            if loading {
                ProgressView("正在查看醒目留言")
            } else if chats.isEmpty {
                ContentUnavailableView("现在没有醒目留言", systemImage: "megaphone", description: Text(note.isEmpty ? roomTitle : note))
            } else {
                List(chats) { chat in
                    HStack(alignment: .top, spacing: 12) {
                        ProfileMark(name: chat.name.isEmpty ? "用户" : chat.name, face: chat.face, size: 36)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(chat.name.isEmpty ? "用户" : chat.name)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                if chat.price > 0 {
                                    Text("\(chat.price) 元")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(Palette.bili)
                                        .fixedSize()
                                }
                            }
                            Text(chat.message)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("醒目留言")
        .navigationSubtitle(roomTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        if model.liveFocusRoom > 0 {
            roomID = model.liveFocusRoom
            roomTitle = model.liveFocusTitle
            chats = (try? await model.client.liveSuperChats(room: roomID)) ?? []
            note = chats.isEmpty ? (roomTitle.isEmpty ? "这个直播间现在没有醒目留言" : "\(roomTitle) 现在没有醒目留言") : ""
            await finish()
            return
        }
        let seeds = (try? await model.client.popularLiveRooms()) ?? []
        var chosen = seeds.first
        var found: [LiveSuperChat] = []
        for room in seeds.prefix(10) {
            chosen = room
            let rows = (try? await model.client.liveSuperChats(room: room.id)) ?? []
            if !rows.isEmpty {
                found = rows
                break
            }
        }
        roomID = chosen?.id ?? 0
        roomTitle = chosen?.title ?? ""
        chats = found
        note = found.isEmpty ? (roomTitle.isEmpty ? "现在没有醒目留言" : "\(roomTitle) 现在没有醒目留言") : ""
        await finish()
    }

    private func finish() async {
        loading = false
        if !chats.isEmpty {
            await ImageStore.shared.prepare(urls: chats.prefix(6).map(\.face), maxPixel: 120)
        }
        LiveExtraProof.record([
            "state": chats.isEmpty ? "empty" : "rows",
            "rows": chats.count,
            "room": roomID,
            "title": roomTitle,
            "titles": chats.prefix(4).map(\.message),
            "names": chats.prefix(4).map(\.name),
            "note": note,
            "error": ""
        ])
    }
}

struct LiveEmotePage: View {
    @Environment(AppModel.self) private var model
    @State private var emotes: [LiveEmote] = []
    @State private var roomTitle = ""
    @State private var login = false
    @State private var note = ""
    @State private var loading = true

    var body: some View {
        Group {
            if loading {
                ProgressView("正在加载表情")
            } else if login {
                VStack(spacing: 16) {
                    ContentUnavailableView("登录后查看直播表情", systemImage: "face.smiling", description: Text(note))
                    Button("去登录") { model.open(.login) }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.bili)
                }
            } else if emotes.isEmpty {
                ContentUnavailableView("没有表情包", systemImage: "face.smiling", description: Text(note))
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 12)], spacing: 12) {
                        ForEach(emotes) { emote in
                            VStack(spacing: 4) {
                                RemoteImage(url: emote.url, ratio: 1, maxPixel: 160)
                                    .frame(width: 56, height: 56)
                                Text(emote.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("直播表情")
        .navigationSubtitle(roomTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        var room = model.liveFocusRoom
        roomTitle = model.liveFocusTitle
        if room == 0, let found = try? await model.client.popularLiveRooms(), let first = found.first {
            room = first.id
            roomTitle = first.title
        }
        guard room > 0 else {
            loading = false
            note = "没有可用的直播间"
            LiveExtraProof.record(["state": "error", "rows": 0, "title": "", "note": note, "names": [String](), "error": note])
            return
        }
        let result = await model.client.liveEmoteState(room: room)
        emotes = result.emotes
        login = result.login
        note = result.note
        loading = false
        if !result.emotes.isEmpty {
            await ImageStore.shared.prepare(urls: result.emotes.prefix(12).map(\.url), maxPixel: 160)
        }
        let state = result.login ? "login" : (result.emotes.isEmpty ? "empty" : "rows")
        LiveExtraProof.record([
            "state": state,
            "rows": result.emotes.count,
            "title": roomTitle,
            "note": result.note,
            "names": result.emotes.prefix(8).map(\.name),
            "error": ""
        ])
    }
}
