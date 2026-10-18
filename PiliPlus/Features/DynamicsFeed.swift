import SwiftUI

struct DynamicsFeed: View {
    @Environment(AppModel.self) private var model
    @State private var tab = "全部"
    @State private var menuItem: DynamicItem?

    private let tabs = ["全部", "投稿", "番剧", "专栏", "UP"]

    private var showPrompt: Bool { !model.loggedIn && !LaunchMode.usesFixtures }

    var body: some View {
        Group {
            if showPrompt {
                LoginPrompt(title: "登录后查看关注动态", systemImage: "dot.radiowaves.left.and.right")
            } else if model.dynamics.isEmpty {
                ContentUnavailableView("关注动态是空的", systemImage: "dot.radiowaves.left.and.right", description: Text("关注的人发布后会出现在这里"))
            } else {
                feed
            }
        }
        .refreshable { await model.loadDynamics(kind: tab, reset: true) }
        .navigationTitle("动态")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("发布动态", systemImage: "plus") {
                    model.open(.feature("发布动态"))
                }
            }
        }
        .sheet(item: $menuItem) { item in
            GlassMenuSheet(title: "动态", rows: Menus.dynamicMenu.map { ("circle", $0) }) { action in
                handle(action, item)
            }
        }
        .task { await model.loadDynamics(kind: tab, reset: true) }
        .onAppear {
            if LaunchMode.usesFixtures && model.dynamics.isEmpty { return }
            SocialUIProof.record([
                "prompt": showPrompt,
                "rows": showPrompt ? 0 : model.dynamics.count,
                "error": ""
            ])
        }
    }

    private var feed: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    LazyVStack(spacing: 14) {
                        if model.flag("动态页展开正在直播UP列表") && !model.lives.isEmpty && tab == "全部" {
                            liveRow
                        }
                        ForEach(filtered) { item in
                            dynamicCard(item)
                                .onAppear {
                                    guard item.id == filtered.last?.id else { return }
                                    Task { await model.loadDynamics(kind: tab, reset: false) }
                                }
                        }
                    }
                    .padding(.bottom, 12)
                } header: {
                    tabStrip
                        .background(Color(.systemBackground))
                }
            }
        }
        .scrollEdgeSoft()
    }

    private var liveRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(model.lives.prefix(8)) { room in
                    Button { model.open(.live(room.id)) } label: {
                        VStack(spacing: 6) {
                            RemoteImage(url: room.face.isEmpty ? room.cover : room.face, ratio: 1, maxPixel: 168)
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Palette.bili, lineWidth: 2))
                            Text(room.uname).font(.caption2).lineLimit(1).frame(width: 64)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tabs, id: \.self) { item in
                    Button(item) {
                        tab = item
                        Task { await model.loadDynamics(kind: item, reset: true) }
                    }
                        .font(.subheadline.weight(tab == item ? .bold : .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundStyle(tab == item ? .white : .primary)
                        .background { if tab == item { Capsule().fill(Palette.bili.gradient) } }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(height: 52)
    }

    private var filtered: [DynamicItem] {
        if !LaunchMode.usesFixtures { return model.dynamics }
        switch tab {
        case "投稿": return model.dynamics.filter { $0.kind == "投稿" }
        case "番剧": return model.dynamics.filter { $0.kind.contains("番") }
        case "专栏": return model.dynamics.filter { $0.kind == "专栏" }
        default: return model.dynamics
        }
    }

    private func dynamicCard(_ item: DynamicItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    guard item.mid > 0 else { return }
                    model.open(.user(item.mid, item.name))
                } label: {
                    HStack {
                        RemoteImage(url: item.face, ratio: 1, maxPixel: 120)
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                        VStack(alignment: .leading) {
                            Text(item.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                            Text("\(item.time) · \(item.kind)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Button { menuItem = item } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            Button {
                model.dynamicFocus = item
                model.open(.dynamic(item.id))
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.text).font(.subheadline).foregroundStyle(.primary).lineLimit(4).frame(maxWidth: .infinity, alignment: .leading)
                    if !item.images.isEmpty {
                        DynamicImageStrip(images: item.images)
                    }
                    if item.hasPoll {
                        DynamicPollBlock(title: item.pollTitle, options: item.pollOptions, counts: item.pollCounts, joined: item.pollJoined)
                    }
                }
            }
            .buttonStyle(.plain)
            if let video = item.video, model.flag("动态页启用瀑布流") || true {
                VideoCard(video: video)
            }
            if model.flag("显示动态互动内容") {
                Text("热评 · 关注的人觉得很有意思")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            HStack {
                ActionChip(system: "arrow.2.squarepath", title: CountText.format(item.repost)) {
                    model.dynamicFocus = item
                    model.open(.feature("转发动态"))
                }
                ActionChip(system: "text.bubble", title: CountText.format(item.comment)) { model.open(.feature("评论")) }
                ActionChip(system: item.liked ? "hand.thumbsup.fill" : "hand.thumbsup", title: CountText.format(item.like), selected: item.liked) {
                    Task { await model.likeDynamic(item) }
                }
            }
        }
        .padding(14)
        .contentPlate(radius: 26)
        .padding(.horizontal, 16)
    }

    private func handle(_ action: String, _ item: DynamicItem) {
        switch action {
        case "转发":
            model.dynamicFocus = item
            model.open(.feature("转发动态"))
        case "复制动态":
            UIPasteboard.general.string = item.text
            model.show("已复制")
        case "不感兴趣": model.show("将减少该内容")
        case "举报": model.show("已提交举报")
        case "删除": model.show(model.loggedIn ? "已删除" : "只能删除自己的动态")
        default: model.show(action)
        }
    }
}
