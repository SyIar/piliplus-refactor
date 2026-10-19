import SwiftUI

private struct MineToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button("搜索", systemImage: "magnifyingglass") { model.open(.search) }
            Button("我的评论", systemImage: "text.bubble") { model.open(.feature("我的评论")) }
        }
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button(model.anonymity ? "退出无痕" : "无痕模式", systemImage: model.anonymity ? "eyeglasses" : "eyeglasses.slash") {
                guard model.loggedIn else { model.open(.login); return }
                model.anonymity.toggle()
                model.save()
                model.show(model.anonymity ? "已进入无痕模式\n搜索不携带身份\n不产生播放记录" : "已退出无痕模式")
            }
            Button("主题", systemImage: "circle.lefthalf.filled") {
                let order: [ThemeChoice] = [.system, .light, .dark, .black]
                let index = order.firstIndex(of: model.theme) ?? 0
                model.theme = order[(index + 1) % order.count]
                model.values["主题模式"] = model.theme.label
                model.save()
                model.show("切换至\(model.theme.label)主题")
            }
            Button("设置", systemImage: "gearshape") { model.open(.settings) }
        }
    }
}

struct MineSpace: View {
    @Environment(AppModel.self) private var model
    @State private var card = "我的收藏"

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                stats
                shortcuts
                cardTabs
                cardBody
            }
            .padding(16)
            .padding(.bottom, 12)
        }
        .scrollEdgeSoft()
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { MineToolbar() }
    }

    private var stats: some View {
        Button {
            model.loggedIn ? model.open(.feature("编辑资料")) : model.open(.login)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    ProfileMark(name: model.userName, face: model.userFace, size: 62)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(model.userName).font(.title3.bold())
                            if model.loggedIn {
                                Text("Lv\(model.level)")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Palette.bili, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                        }
                        Text(model.loggedIn ? "硬币 \(model.coinCount)      经验 \(model.exp)/\(model.nextExp)" : "登录后同步硬币、等级与收藏")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ProgressView(value: model.loggedIn ? Double(model.exp) / Double(max(model.nextExp, 1)) : 0)
                            .tint(Palette.bili)
                    }
                }
                HStack {
                    stat(model.dynamicCount, "动态") { model.open(.feature("全部动态")) }
                    stat(model.following, "关注") { model.open(.feature("关注")) }
                    stat(model.followers, "粉丝") { model.open(.feature("粉丝")) }
                }
            }
            .padding(16)
            .contentPlate(radius: 28)
        }
        .buttonStyle(.plain)
    }

    private func stat(_ value: Int, _ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(model.loggedIn ? "\(value)" : "-").font(.headline.monospacedDigit())
                Text(name).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var shortcuts: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            shortcut("arrow.down.circle", "离线缓存") { model.open(.feature("离线缓存")) }
            shortcut("clock.arrow.circlepath", "观看记录") { model.open(.feature("观看记录")) }
            shortcut("rectangle.stack", "我的订阅") { model.open(.feature("我的订阅")) }
            shortcut("clock", "稍后再看") { model.open(.feature("稍后再看")) }
            shortcut("square.grid.2x2", "全部功能") { model.open(.feature("全部页面")) }
            shortcut("person.2", "关注") { model.open(.feature("关注")) }
            shortcut("hand.raised", "黑名单") { model.open(.feature("黑名单")) }
            shortcut("person.crop.circle", "编辑资料") { model.open(.feature("编辑资料")) }
            shortcut("desktopcomputer", "登录设备") { model.open(.feature("登录设备")) }
            shortcut("person.crop.circle.badge.plus", "切换账号") { model.open(.feature("切换账号")) }
        }
    }

    private func shortcut(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.caption2.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .contentPlate(radius: 20)
        }
        .buttonStyle(.plain)
    }

    private var cardTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(["我的收藏", "观看记录", "稍后再看", "我的订阅"], id: \.self) { item in
                    Button(item) { card = item }
                        .font(.subheadline.weight(card == item ? .bold : .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(card == item ? Palette.bili : .secondary)
                }
            }
        }
    }

    private var needsLogin: Bool { !model.loggedIn && !LaunchMode.accountPreview }

    @ViewBuilder
    private var cardBody: some View {
        switch card {
        case "我的收藏":
            if needsLogin {
                LoginPrompt(title: "登录后查看收藏夹", systemImage: "star")
            } else if model.favFolders.isEmpty {
                ContentUnavailableView("没有收藏夹", systemImage: "star", description: Text("登录后同步收藏夹"))
            } else {
                VStack(spacing: 10) {
                    ForEach(model.favFolders) { folder in
                        Button { model.open(.folder(folder.id)) } label: {
                            HStack {
                                Image(systemName: "folder.fill").foregroundStyle(Palette.bili)
                                Text(folder.title).lineLimit(1)
                                Spacer(minLength: 0)
                                Text("\(folder.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .contentPlate(radius: 18)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        case "稍后再看":
            accountSlice(model.laterVideos, title: "登录后查看稍后再看", symbol: "clock", feature: "稍后再看")
        case "观看记录":
            accountSlice(model.history, title: "登录后查看观看记录", symbol: "clock.arrow.circlepath", feature: "观看记录")
        default:
            LoginPrompt(title: "登录后查看\(card)", systemImage: "rectangle.stack")
        }
    }

    @ViewBuilder
    private func accountSlice(_ videos: [VideoItem], title: String, symbol: String, feature: String) -> some View {
        if needsLogin {
            LoginPrompt(title: title, systemImage: symbol)
        } else if videos.isEmpty {
            ContentUnavailableView(title, systemImage: symbol, description: Text("这里还是空的"))
        } else {
            VStack(spacing: 12) {
                ForEach(videos.prefix(6)) { video in
                    VideoCard(video: video)
                }
                Button("查看全部") { model.open(.feature(feature)) }
                    .font(.subheadline.weight(.semibold))
            }
        }
    }
}
