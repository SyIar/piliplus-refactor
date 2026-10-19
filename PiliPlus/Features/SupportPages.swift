import SwiftUI
import CoreImage

struct SettingsStudio: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        List {
            Section {
                Button { model.open(.login) } label: { Label(model.loggedIn ? "切换账号" : "登录", systemImage: "person.crop.circle") }
                if model.loggedIn {
                    Button(role: .destructive) { model.logout() } label: { Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right") }
                }
            }
            Section {
                ForEach(Menus.settingSections, id: \.title) { item in
                    Button { model.open(.setting(item.title)) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.system).frame(width: 28).foregroundStyle(Palette.bili)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).foregroundStyle(.primary)
                                if !item.subtitle.isEmpty {
                                    Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }
            Section {
                NavigationLink("搜索设置") { SettingsSearch() }
                Button { model.open(.feature("全部页面")) } label: { Label("全部页面与操作", systemImage: "square.grid.2x2") }
            }
        }
        .navigationTitle("设置")
    }
}

struct SettingsSearch: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    var body: some View {
        let rows = Menus.settings.values.flatMap { $0 }.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.subtitle.localizedCaseInsensitiveContains(query) }
        List(rows) { row in
            VStack(alignment: .leading) {
                Text(row.title)
                Text(row.subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("搜索设置")
        .searchable(text: $query, prompt: "搜索设置项")
    }
}

struct SettingDetail: View {
    @Environment(AppModel.self) private var model
    let name: String
    @State private var editor: SettingRow?
    @State private var draft = ""

    var body: some View {
        Group {
            if name == "关于" {
                about
            } else {
                List {
                    ForEach(Menus.settings[name] ?? []) { row in
                        rowView(row)
                    }
                }
            }
        }
        .navigationTitle(name)
        .sheet(item: $editor) { row in
            editorSheet(row)
        }
    }

    @ViewBuilder
    private func rowView(_ row: SettingRow) -> some View {
        switch row.kind {
        case .toggle:
            Toggle(isOn: Binding(get: { model.flag(row.title) }, set: { model.setFlag(row.title, $0); applySideEffect(row.title, bool: $0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                    Text(row.subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            .tint(Palette.bili)
        case .options, .text:
            Button { editor = row; draft = model.values[row.title] ?? "" } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title).foregroundStyle(.primary)
                        Text(model.values[row.title] ?? row.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func editorSheet(_ row: SettingRow) -> some View {
        NavigationStack {
            Group {
                if case .options(let options) = row.kind {
                    List(options, id: \.self) { option in
                        Button {
                            model.values[row.title] = option
                            applySideEffect(row.title, text: option)
                            model.save()
                            editor = nil
                        } label: {
                            HStack {
                                Text(option).foregroundStyle(.primary)
                                Spacer()
                                if model.values[row.title] == option { Image(systemName: "checkmark").foregroundStyle(Palette.bili) }
                            }
                        }
                    }
                } else {
                    Form {
                        TextField(row.subtitle, text: $draft, axis: .vertical)
                        Button("完成") {
                            model.values[row.title] = draft
                            model.save()
                            model.show("已保存\(row.title)")
                            editor = nil
                        }
                    }
                }
            }
            .navigationTitle(row.title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    private func applySideEffect(_ title: String, bool: Bool? = nil, text: String? = nil) {
        if title == "主题模式", let text, let choice = ThemeChoice.allCases.first(where: { $0.label == text }) {
            model.theme = choice
        }
        if title == "纯黑主题", bool == true { model.theme = .black }
        if title == "弹幕开关", let bool { model.danmakuOn = bool }
        if title == "首页标签页" { model.show("可在下方调整首页标签顺序") }
    }

    private var about: some View {
        List {
            Section {
                LabeledContent("名称", value: "PiliPlus")
                LabeledContent("版本", value: "2.0.0")
                LabeledContent("界面", value: "iOS 27 Liquid Glass")
                LabeledContent("上游", value: "bggRGjQaUbCoE/PiliPlus")
            }
            Section {
                Button("日志") { model.open(.feature("日志")) }
                Button("检查更新") { model.show(model.flag("检查更新") ? "已是最新的 Swift 重构版" : "已关闭启动检查") }
                Button("复制 buvid") {
                    UIPasteboard.general.string = DeviceIdentity.buvid
                    model.show("已复制 buvid")
                }
            }
            Section("说明") {
                Text("这是把 PiliPlus 的页面、菜单和操作项按原版信息架构重写成的原生 SwiftUI 客户端。系统底栏、搜索条、卡片和弹层使用 iOS 26 / 27 的 Liquid Glass。播放走公开接口，登录态操作在接入 Cookie 后与原版同一套入口。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct FeaturePageView: View {
    @Environment(AppModel.self) private var model
    let title: String
    @State private var query = ""

    var body: some View {
        let page = Menus.pages.first { $0.title == title }
        Group {
            if title == "全部页面" {
                allPages
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(page?.hint ?? "与 PiliPlus「\(title)」相同的入口")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let actions = page?.actions {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(actions, id: \.self) { action in
                                    Button(action) { perform(action) }
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .contentPlate(radius: 18)
                                }
                            }
                        }
                        if !model.feed.isEmpty {
                            Text("内容").font(.headline)
                            ForEach(model.feed.prefix(8)) { video in
                                VideoCard(video: video)
                            }
                        }
                    }
                    .padding(16)
                }
                .scrollEdgeSoft()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var allPages: some View {
        let groups = Dictionary(grouping: Menus.pages, by: \.group)
        return List {
            ForEach(groups.keys.sorted(), id: \.self) { key in
                Section(key) {
                    ForEach(groups[key] ?? [], id: \.title) { page in
                        Button {
                            model.open(.feature(page.title))
                        } label: {
                            VStack(alignment: .leading) {
                                Text(page.title).foregroundStyle(.primary)
                                Text(page.actions.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    private func perform(_ action: String) {
        switch action {
        case "查看详情", "播放", "继续播放":
            if let video = model.feed.first { model.open(.video(video.bvid)) }
        case "刷新":
            Task { await model.refreshHome() }
        case "发布", "话题", "投票", "预约", "表情", "提及":
            model.show("已打开\(action)")
        default:
            model.show(action)
        }
    }
}

struct LiveStage: View {
    @Environment(AppModel.self) private var model
    let roomID: Int
    @State private var text = ""
    @State private var messages: [String] = ["欢迎来到直播间", "主播来了", "这画质可以", "SC 走一个"]
    @State private var showRank = false
    @State private var showEmote = false
    @State private var showSC = false

    private var room: LiveRoom? { model.lives.first { $0.id == roomID } }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    RemoteImage(url: room?.cover ?? "", ratio: 16 / 9)
                    LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading) {
                        Text(room?.title ?? "直播间 \(roomID)").font(.headline).foregroundStyle(.white)
                        Text("\(room?.uname ?? "主播") · \(room?.area ?? "直播") · \(CountText.format(room?.online ?? 0)) 在看")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    .padding(12)
                }
                .frame(height: 230)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(messages.indices, id: \.self) { index in
                            Text(messages[index])
                                .font(.subheadline)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.primary.opacity(0.08), in: Capsule())
                        }
                    }
                    .padding(16)
                }
                HStack(spacing: 8) {
                    TextField("发个弹幕…", text: $text)
                        .textFieldStyle(.roundedBorder)
                    Button { showEmote = true } label: {
                        Image(systemName: "face.smiling")
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("表情")
                    Button("发送") { send() }
                        .font(.subheadline.weight(.bold))
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.bili)
                }
                .padding(.horizontal, 12)
                HStack {
                    liveAction("关注") { model.show(model.requireLogin("关注") ? "已关注主播" : "") }
                    liveAction("表情") { showEmote = true }
                    liveAction("醒目留言") { showSC = true }
                    liveAction("贡献榜") { showRank = true }
                    liveAction("分享") { model.show("已打开分享") }
                    liveAction("屏蔽") { model.open(.feature("直播弹幕屏蔽")) }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .navigationTitle("直播")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showRank) {
            GlassMenuSheet(title: "贡献榜", rows: ["日榜", "周榜", "月榜", "大航海"].map { ("trophy", $0) }) { model.show($0) }
        }
        .sheet(isPresented: $showEmote) {
            GlassMenuSheet(title: "直播表情", rows: ["(￣▽￣)", "doge", "笑哭", "妙啊", "哦呼"].map { ("face.smiling", $0) }) { text += $0 }
        }
        .sheet(isPresented: $showSC) {
            NavigationStack {
                Form {
                    TextField("留言", text: $text)
                    Button("发送醒目留言 ¥30") {
                        guard model.requireLogin("发送醒目留言") else { return }
                        messages.append("SC \(model.userName)：\(text.isEmpty ? "支持主播" : text)")
                        showSC = false
                    }
                }
                .navigationTitle("醒目留言")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium])
        }
    }

    private func liveAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .selectionCapsule(selected: false)
    }

    private func send() {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        guard model.requireLogin("发送弹幕") else { return }
        messages.append("\(model.userName)：\(body)")
        text = ""
    }
}

struct InboxView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = "回复我的"
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Menus.messageTabs.filter { !($0 == "收到的赞" && model.flag("消息页禁用\"收到的赞\"功能")) }, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(12)
            List {
                if tab == "回复我的" { rows(model.unreadReply, "回复了你的评论", "text.bubble") }
                if tab == "@我" { rows(model.unreadAt, "在动态里提到了你", "at") }
                if tab == "收到的赞" { rows(model.unreadLike, "赞了你的评论", "hand.thumbsup") }
                if tab == "系统通知" { rows(1, "欢迎使用 PiliPlus", "bell") }
                Section {
                    Button { model.open(.feature("私信")) } label: { Label("私信", systemImage: "envelope") }
                }
            }
        }
        .navigationTitle("消息")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("全部已读") {
                    model.unreadReply = 0
                    model.unreadAt = 0
                    model.unreadLike = 0
                    model.show("已全部标为已读")
                }
            }
        }
    }

    private func rows(_ count: Int, _ subtitle: String, _ icon: String) -> some View {
        ForEach(0..<max(count, 1), id: \.self) { index in
            Button { model.open(.feature(tab)) } label: {
                HStack {
                    Image(systemName: icon).foregroundStyle(Palette.bili).frame(width: 28)
                    VStack(alignment: .leading) {
                        Text(index == 0 ? subtitle : "更早的\(tab)").foregroundStyle(.primary)
                        Text("刚刚").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct LoginGate: View {
    @Environment(AppModel.self) private var model
    @State private var mode = "扫码"
    @State private var account = ""
    @State private var secret = ""
    @State private var cookie = ""
    @State private var qrImage: UIImage?
    @State private var qrStatus = "正在获取二维码"
    @State private var submitting = false

    var body: some View {
        VStack(spacing: 16) {
            Text("登录哔哩哔哩")
                .font(.largeTitle.bold())
            Text("扫码和 Cookie 会写入钥匙串，并带到之后的请求里。密码和短信需要极验，这一项还没有接通。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Picker("", selection: $mode) {
                ForEach(["扫码", "密码", "短信", "Cookie"], id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            Group {
                switch mode {
                case "密码":
                    TextField("账号 / 邮箱 / 手机", text: $account).textFieldStyle(.roundedBorder)
                    SecureField("密码", text: $secret).textFieldStyle(.roundedBorder)
                case "短信":
                    TextField("手机号", text: $account).textFieldStyle(.roundedBorder).keyboardType(.phonePad)
                    HStack {
                        TextField("验证码", text: $secret).textFieldStyle(.roundedBorder)
                        Button("获取验证码") { model.show("短信登录需要极验，请改用扫码或 Cookie") }
                    }
                case "Cookie":
                    TextField("粘贴浏览器 Cookie，需包含 SESSDATA 和 bili_jct", text: $cookie, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                default:
                    qrPane
                }
            }
            if mode == "密码" || mode == "短信" {
                Button("登录") { model.show("密码和短信登录需要极验，请改用扫码或 Cookie") }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.bili)
            } else if mode == "Cookie" {
                Button(submitting ? "正在校验" : "登录") { Task { await submitCookie() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.bili)
                    .disabled(submitting)
            }
            Spacer()
        }
        .padding(20)
        .background(Color(.systemBackground))
        .navigationTitle("登录")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: mode) { await watchQR() }
    }

    private var qrPane: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                if let qrImage {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(18)
                } else {
                    ProgressView()
                }
            }
            .frame(width: 220, height: 220)
            Text(qrStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("用哔哩哔哩 App 扫码")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("刷新二维码") { qrImage = nil }
                .font(.caption.weight(.semibold))
        }
    }

    private func watchQR() async {
        guard mode == "扫码" else { return }
        Task { await model.client.refreshMixinKey() }
        while !Task.isCancelled && mode == "扫码" {
            qrStatus = "正在获取二维码"
            do {
                let ticket = try await model.client.requestQRCode()
                if Task.isCancelled { return }
                qrImage = QRImage.make(ticket.url)
                if qrImage == nil {
                    qrStatus = "无法绘制二维码"
                    try? await Task.sleep(for: .seconds(3))
                    continue
                }
                qrStatus = "等待扫码"
                let deadline = Date().addingTimeInterval(170)
                var expired = false
                while !Task.isCancelled && Date() < deadline && qrImage != nil {
                    try? await Task.sleep(for: .seconds(2))
                    if Task.isCancelled { return }
                    if qrImage == nil { break }
                    switch try await model.client.pollQR(authCode: ticket.authCode) {
                    case .pending(let message):
                        qrStatus = message
                    case .expired(let message):
                        qrStatus = message
                        expired = true
                    case .confirmed(let session):
                        qrStatus = "扫码成功"
                        await model.adopt(session)
                        if model.loggedIn { model.pop() }
                        return
                    }
                    if expired { break }
                }
            } catch {
                if Task.isCancelled { return }
                qrStatus = error.localizedDescription
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func submitCookie() async {
        let cookies = BiliSession.parseCookieHeader(cookie)
        guard cookies["SESSDATA"] != nil else {
            model.show("请粘贴包含 SESSDATA 的 Cookie")
            return
        }
        guard cookies["bili_jct"] != nil else {
            model.show("Cookie 里还需要 bili_jct，否则无法完成需要 csrf 的操作")
            return
        }
        submitting = true
        defer { submitting = false }
        let session = BiliSession.make(
            cookies: cookies,
            mid: Int(cookies["DedeUserID"] ?? "") ?? 0
        )
        await model.adopt(session)
        if model.loggedIn { model.pop() }
    }
}

private enum QRImage {
    static func make(_ text: String) -> UIImage? {
        guard let data = text.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
