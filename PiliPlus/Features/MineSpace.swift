import SwiftUI

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
        .feedChrome { header }
        .background { AuroraBackdrop() }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                GlassIconButton(system: "magnifyingglass") { model.open(.search) }
                    .accessibilityLabel("搜索")
                GlassIconButton(system: "text.bubble") { model.open(.feature("我的评论")) }
                    .accessibilityLabel("我的评论")
                GlassIconButton(system: model.anonymity ? "eyeglasses" : "eyeglasses.slash") {
                guard model.loggedIn else { model.open(.login); return }
                model.anonymity.toggle()
                model.save()
                model.show(model.anonymity ? "已进入无痕模式\n搜索不携带身份\n不产生播放记录" : "已退出无痕模式")
            }
            GlassIconButton(system: "circle.lefthalf.filled") {
                let order: [ThemeChoice] = [.system, .light, .dark, .black]
                let index = order.firstIndex(of: model.theme) ?? 0
                model.theme = order[(index + 1) % order.count]
                model.values["主题模式"] = model.theme.label
                model.save()
                model.show("切换至\(model.theme.label)主题")
            }
            GlassIconButton(system: "gearshape") { model.open(.settings) }
                .accessibilityLabel("设置")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    private var stats: some View {
        Button {
            model.loggedIn ? model.open(.feature("编辑资料")) : model.open(.login)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Palette.bili.gradient)
                        Text(String(model.userName.prefix(1))).font(.title2.bold()).foregroundStyle(.white)
                    }
                    .frame(width: 62, height: 62)
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

    @ViewBuilder
    private var cardBody: some View {
        if card == "我的收藏" {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(Menus.favTabs, id: \.self) { tab in
                        Button(tab) { model.open(.feature("我的收藏")) }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .selectionCapsule(selected: false)
                    }
                }
            }
        }
        if model.history.isEmpty && model.feed.isEmpty {
            ContentUnavailableView("登录后查看\(card)", systemImage: "person.crop.circle", description: Text("这里会显示与原版相同的收藏、历史、稍后再看和订阅"))
        } else {
            LazyVStack(spacing: 12) {
                ForEach(model.history.isEmpty ? Array(model.feed.prefix(6)) : model.history) { video in
                    VideoCard(video: video)
                }
            }
        }
    }
}
