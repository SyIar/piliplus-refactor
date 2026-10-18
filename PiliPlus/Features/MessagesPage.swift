import SwiftUI

struct MessageHome: View {
    @Environment(AppModel.self) private var model
    @State private var sessions: [ChatSession] = []
    @State private var loading = false
    @State private var hasMore = false
    @State private var endTs = 0
    @State private var needsLogin = false
    @State private var error = ""

    private var showPrompt: Bool { !model.loggedIn || needsLogin }
    private var kinds: [String] {
        Menus.messageTabs.filter { !($0 == "收到的赞" && model.flag("消息页禁用\"收到的赞\"功能")) }
    }

    var body: some View {
        Group {
            if showPrompt {
                LoginPrompt(title: "登录后查看消息", systemImage: "bell")
            } else {
                list
            }
        }
        .navigationTitle("消息")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load(reset: true) }
    }

    private var list: some View {
        List {
            Section {
                ForEach(kinds, id: \.self) { kind in
                    Button {
                        model.open(.notices(kind))
                    } label: {
                        Label(kind, systemImage: symbol(kind))
                            .badge(count(kind))
                    }
                }
            }
            Section("私信") {
                if sessions.isEmpty && !loading {
                    Text(error.isEmpty ? "没有私信" : error)
                        .foregroundStyle(.secondary)
                }
                ForEach(sessions) { session in
                    Button {
                        model.open(.chat(session.id, session.name))
                    } label: {
                        sessionRow(session)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        guard session.id == sessions.last?.id, hasMore, !loading else { return }
                        Task { await load(reset: false) }
                    }
                }
            }
        }
        .refreshable { await load(reset: true) }
        .overlay {
            if loading && sessions.isEmpty { ProgressView() }
        }
    }

    private func sessionRow(_ session: ChatSession) -> some View {
        HStack(spacing: 12) {
            ProfileMark(name: session.name, face: session.face, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(session.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(MessageParser.clock(session.time))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(session.preview.isEmpty ? " " : session.preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .badge(session.unread)
    }

    private func load(reset: Bool) async {
        if showPrompt {
            model.unreadReply = 0
            model.unreadAt = 0
            model.unreadLike = 0
            model.unreadSystem = 0
            record(rows: 0, sessions: 0, error: "")
            return
        }
        if reset {
            endTs = 0
            hasMore = true
        }
        guard hasMore, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            if reset {
                let unread = try await model.client.messageUnread()
                model.unreadReply = unread.reply
                model.unreadAt = unread.at
                model.unreadLike = unread.like
                model.unreadSystem = unread.system
            }
            let page = try await model.client.chatSessions(endTs: endTs)
            if reset {
                sessions = page.items
            } else {
                let known = Set(sessions.map(\.id))
                sessions.append(contentsOf: page.items.filter { !known.contains($0.id) })
            }
            hasMore = page.hasMore && !page.items.isEmpty
            endTs = page.items.map(\.time).filter { $0 > 0 }.min() ?? endTs
            error = ""
            record(rows: kinds.count, sessions: sessions.count, error: "")
        } catch {
            if error.localizedDescription.contains("登录") { needsLogin = true }
            self.error = error.localizedDescription
            record(rows: 0, sessions: sessions.count, error: needsLogin ? "" : self.error)
        }
    }

    private func record(rows: Int, sessions: Int, error: String) {
        MessageUIProof.record([
            "prompt": showPrompt,
            "rows": rows,
            "sessions": sessions,
            "error": error
        ])
    }

    private func count(_ kind: String) -> Int {
        switch kind {
        case "回复我的": model.unreadReply
        case "@我": model.unreadAt
        case "收到的赞": model.unreadLike
        case "系统通知": model.unreadSystem
        default: 0
        }
    }

    private func symbol(_ kind: String) -> String {
        switch kind {
        case "@我": "at"
        case "收到的赞": "hand.thumbsup"
        case "系统通知": "bell"
        default: "text.bubble"
        }
    }
}

struct NoticeListView: View {
    @Environment(AppModel.self) private var model
    let kind: String
    @State private var items: [NoticeItem] = []
    @State private var loading = false
    @State private var ended = false
    @State private var cursor = 0
    @State private var cursorTime = 0
    @State private var needsLogin = false
    @State private var error = ""

    private var showPrompt: Bool { !model.loggedIn || needsLogin }

    var body: some View {
        Group {
            if showPrompt {
                LoginPrompt(title: "登录后查看\(kind)", systemImage: "bell")
            } else if items.isEmpty && !loading {
                ContentUnavailableView(error.isEmpty ? "没有\(kind)" : "没有加载到", systemImage: "tray", description: Text(error.isEmpty ? "新的通知会出现在这里" : error))
            } else {
                List(items) { item in
                    noticeRow(item)
                        .onAppear {
                            guard item.id == items.last?.id, !ended, !loading else { return }
                            Task { await load(reset: false) }
                        }
                }
            }
        }
        .navigationTitle(kind)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load(reset: true) }
        .task { await load(reset: true) }
        .overlay {
            if loading && items.isEmpty && !showPrompt { ProgressView() }
        }
    }

    private func noticeRow(_ item: NoticeItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ProfileMark(name: item.name, face: item.face, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(item.timeText).font(.caption2).foregroundStyle(.secondary)
                }
                Text(item.title).font(.subheadline).lineLimit(2)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func load(reset: Bool) async {
        guard !showPrompt else { return }
        if reset {
            cursor = 0
            cursorTime = 0
            ended = false
        }
        guard !ended, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await model.client.messageNotices(kind: kind, cursor: cursor, time: cursorTime)
            if reset { items = page.items } else {
                let known = Set(items.map(\.id))
                items.append(contentsOf: page.items.filter { !known.contains($0.id) })
            }
            cursor = page.cursor
            cursorTime = page.cursorTime
            ended = page.ended || page.items.isEmpty
            error = ""
        } catch {
            if error.localizedDescription.contains("登录") { needsLogin = true }
            self.error = error.localizedDescription
            ended = true
        }
    }
}

struct ChatView: View {
    @Environment(AppModel.self) private var model
    let talkerID: Int
    let name: String
    @State private var lines: [ChatLine] = []
    @State private var draft = ""
    @State private var loading = false
    @State private var sending = false
    @State private var hasMore = false
    @State private var needsLogin = false
    @State private var error = ""
    @State private var localID = -1

    private var showPrompt: Bool { !model.loggedIn || needsLogin }
    private var title: String { name.isEmpty ? "私信" : name }

    var body: some View {
        Group {
            if showPrompt {
                LoginPrompt(title: "登录后查看私信", systemImage: "bubble.left.and.bubble.right")
            } else if talkerID <= 0 {
                ContentUnavailableView("没有会话", systemImage: "bubble.left.and.bubble.right", description: Text("从私信列表打开一个会话"))
            } else {
                thread
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await appear() }
    }

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if lines.isEmpty && !loading {
                        ContentUnavailableView(error.isEmpty ? "没有消息" : "没有加载到", systemImage: "bubble.left", description: Text(error.isEmpty ? "发一条文字消息" : error))
                    }
                    ForEach(lines) { line in
                        bubble(line)
                            .id(line.id)
                            .onAppear {
                                guard line.id == lines.first?.id, hasMore, !loading else { return }
                                Task { await load(older: true) }
                            }
                    }
                }
                .padding(16)
            }
            .scrollEdgeSoft()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composer
            }
            .onChange(of: lines.last?.id) { _, last in
                guard let last else { return }
                proxy.scrollTo(last, anchor: .bottom)
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("发消息", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
            Button("发送") { Task { await send() } }
                .buttonStyle(.borderedProminent)
                .tint(Palette.bili)
                .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func bubble(_ line: ChatLine) -> some View {
        HStack {
            if line.mine { Spacer(minLength: 48) }
            VStack(alignment: line.mine ? .trailing : .leading, spacing: 4) {
                Text(line.text.isEmpty ? "[消息]" : line.text)
                    .font(.subheadline)
                    .foregroundStyle(line.system ? Color.secondary : (line.mine ? Color.white : Color.primary))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(bubbleColor(line), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                if line.time > 0 {
                    Text(MessageParser.clock(line.time))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            if !line.mine { Spacer(minLength: 48) }
        }
    }

    private func bubbleColor(_ line: ChatLine) -> Color {
        if line.system { return Color(.secondarySystemBackground) }
        return line.mine ? Palette.bili : Color(.secondarySystemBackground)
    }

    private func appear() async {
        if showPrompt || talkerID <= 0 {
            MessageUIProof.record(["prompt": showPrompt, "rows": 0, "error": ""])
            return
        }
        await load(older: false)
        MessageUIProof.record(["prompt": false, "rows": lines.count, "error": error])
    }

    private func load(older: Bool) async {
        guard !showPrompt, talkerID > 0, !loading else { return }
        loading = true
        defer { loading = false }
        let end = older ? (lines.map(\.id).filter { $0 > 0 }.min() ?? 0) : 0
        do {
            let page = try await model.client.chatLines(talker: talkerID, endSeqno: end)
            if older {
                let known = Set(lines.map(\.id))
                lines.insert(contentsOf: page.items.filter { !known.contains($0.id) }, at: 0)
            } else {
                lines = page.items
                if page.maxSeqno > 0 {
                    try? await model.client.ackChat(talker: talkerID, seqno: page.maxSeqno)
                }
            }
            hasMore = page.hasMore
            error = ""
        } catch {
            if error.localizedDescription.contains("登录") { needsLogin = true }
            self.error = error.localizedDescription
        }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending, talkerID > 0 else { return }
        sending = true
        defer { sending = false }
        do {
            try await model.client.sendChat(receiver: talkerID, text: text)
            draft = ""
            localID -= 1
            lines.append(ChatLine(id: localID, text: text, mine: true, time: Int(Date().timeIntervalSince1970), system: false))
            model.show("已发送")
        } catch {
            if error.localizedDescription.contains("登录") { needsLogin = true }
            model.show(error.localizedDescription)
        }
    }
}
