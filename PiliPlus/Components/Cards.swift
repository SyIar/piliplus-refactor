import SwiftUI

struct VideoCard: View {
    @Environment(AppModel.self) private var model
    let video: VideoItem
    var compact = false

    var body: some View {
        Button {
            model.store(video)
            model.open(.video(video.bvid))
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                RemoteImage(url: video.cover)
                    .clipShape(RoundedRectangle(cornerRadius: compact ? 16 : 22, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        DurationBadge(seconds: video.duration).padding(8)
                    }
                    .overlay(alignment: .topLeading) {
                        if video.pageCount > 1 {
                            Text("\(video.pageCount)P")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.45), in: Capsule())
                                .foregroundStyle(.white)
                                .padding(8)
                        }
                    }
                Text(video.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(video.ownerName)
                        .lineLimit(1)
                        .layoutPriority(-1)
                    Spacer(minLength: 0)
                    Label(CountText.format(video.view), systemImage: "play.fill")
                        .lineLimit(1)
                        .fixedSize()
                    Label(CountText.format(video.danmaku), systemImage: "text.bubble.fill")
                        .lineLimit(1)
                        .fixedSize()
                }
                .lineLimit(1)
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("不感兴趣", systemImage: "hand.thumbsdown") { Task { await model.dislike(video) } }
            Button("稍后再看", systemImage: "clock") { model.watchLater(video.bvid) }
            Button("收藏", systemImage: "star") { model.favorite(video.bvid, folder: model.favFolders[0]) }
            Button("分享", systemImage: "square.and.arrow.up") { model.show("已打开分享") }
            Divider()
            Button("查看 UP", systemImage: "person") { model.open(.user(video.ownerMid, video.ownerName)) }
        }
    }
}

struct ActionChip: View {
    let system: String
    let title: String
    var selected = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: system)
                    .font(.system(size: 18, weight: .semibold))
                    .symbolEffect(.bounce, value: selected)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .foregroundStyle(selected ? Palette.bili : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct GlassMenuSheet: View {
    let title: String
    let rows: [(String, String)]
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(rows, id: \.1) { row in
                    Button {
                        onPick(row.1)
                        dismiss()
                    } label: {
                        Label(row.1, systemImage: row.0)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }
}

struct OptionSheet: View {
    let title: String
    let options: [String]
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(options, id: \.self) { option in
                Button {
                    selection = option
                    dismiss()
                } label: {
                    HStack {
                        Text(option)
                        Spacer()
                        if selection == option { Image(systemName: "checkmark").foregroundStyle(Palette.bili) }
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }
}
