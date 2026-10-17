import SwiftUI

struct DynamicsFeed: View {
    @Environment(AppModel.self) private var model
    @State private var tab = "全部"
    @State private var menuItem: DynamicItem?

    private let tabs = ["全部", "投稿", "番剧", "专栏", "UP"]

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 0) {
                HStack {
                    Text("动态").font(.largeTitle.bold())
                    Spacer()
                    GlassIconButton(system: "plus") { model.open(.feature("发布动态")) }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tabs, id: \.self) { item in
                            Button(item) { withAnimation(.spring(duration: 0.3)) { tab = item } }
                                .font(.subheadline.weight(tab == item ? .bold : .medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .foregroundStyle(tab == item ? .white : .primary)
                                .background { if tab == item { Capsule().fill(Palette.bili.gradient) } }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if model.flag("动态页展开正在直播UP列表") && !model.lives.isEmpty && tab == "全部" {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(model.lives.prefix(8)) { room in
                                        Button { model.open(.live(room.id)) } label: {
                                            VStack(spacing: 6) {
                                                RemoteImage(url: room.face.isEmpty ? room.cover : room.face, ratio: 1)
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
                        ForEach(filtered) { item in
                            dynamicCard(item)
                        }
                    }
                    .padding(.bottom, 24)
                }
                .refreshable { await model.refreshHome() }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $menuItem) { item in
            GlassMenuSheet(title: "动态", rows: Menus.dynamicMenu.map { ("circle", $0) }) { action in
                handle(action, item)
            }
        }
    }

    private var filtered: [DynamicItem] {
        switch tab {
        case "投稿": return model.dynamics.filter { $0.kind == "投稿" }
        case "番剧": return model.dynamics.filter { $0.kind.contains("番") }
        case "专栏": return []
        case "UP": return model.dynamics
        default: return model.dynamics
        }
    }

    private func dynamicCard(_ item: DynamicItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                RemoteImage(url: item.face, ratio: 1)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                VStack(alignment: .leading) {
                    Text(item.name).font(.subheadline.weight(.semibold))
                    Text("\(item.time) · \(item.kind)").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button { menuItem = item } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            Text(item.text).font(.subheadline).lineLimit(4)
            if let video = item.video, model.flag("动态页启用瀑布流") || true {
                VideoCard(video: video)
            }
            if model.flag("显示动态互动内容") {
                Text("热评 · 关注的人觉得很有意思")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            HStack {
                ActionChip(system: "arrow.2.squarepath", title: CountText.format(item.repost)) { model.show("已打开转发") }
                ActionChip(system: "text.bubble", title: CountText.format(item.comment)) { model.open(.feature("评论")) }
                ActionChip(system: "hand.thumbsup", title: CountText.format(item.like), selected: false) {
                    guard model.requireLogin("点赞") else { return }
                    model.show("已赞动态")
                }
            }
        }
        .padding(14)
        .glassCard(radius: 26)
        .padding(.horizontal, 16)
    }

    private func handle(_ action: String, _ item: DynamicItem) {
        switch action {
        case "转发": model.open(.feature("发布动态"))
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
