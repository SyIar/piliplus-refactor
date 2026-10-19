import SwiftUI

struct VideoCard: View {
    @Environment(AppModel.self) private var model
    let video: VideoItem
    var compact = false
    /// Search rows stack the uploader above the counts. Home cards keep one line.
    var stackedMeta = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                model.store(video)
                model.open(.video(video.bvid))
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    RemoteImage(url: video.cover, ratio: 16.0 / 9.0)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
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
                        .lineLimit(2, reservesSpace: true)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            if stackedMeta {
                VideoListMeta(owner: video.ownerName, viewCount: video.view, danmaku: video.danmaku)
            } else {
                HStack(spacing: 8) {
                    Button {
                        guard video.ownerMid > 0 else { return }
                        model.open(.user(video.ownerMid, video.ownerName))
                    } label: {
                        Text(video.ownerName)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .layoutPriority(-1)
                    Spacer(minLength: 0)
                    if video.view > 0 { cardCount("play.fill", CountText.format(video.view)) }
                    if video.danmaku > 0 { cardCount("text.bubble.fill", CountText.format(video.danmaku)) }
                }
                .lineLimit(1)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contextMenu {
            Button("不感兴趣", systemImage: "hand.thumbsdown") { Task { await model.dislike(video) } }
            Button("稍后再看", systemImage: "clock") { model.watchLater(video.bvid) }
            Button("收藏", systemImage: "star") { model.favoriteQuick(video) }
            Button("分享", systemImage: "square.and.arrow.up") { model.show("已打开分享") }
            Divider()
            Button("查看 UP", systemImage: "person") { model.open(.user(video.ownerMid, video.ownerName)) }
        }
    }

    private func cardCount(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            Text(text).lineLimit(1).fixedSize(horizontal: true, vertical: false)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Uploader on the first line. Plays, danmaku, then progress share the second
/// line. A count that does not fit is omitted whole, never cut mid-number.
struct VideoListMeta: View {
    let owner: String
    let viewCount: Int
    let danmaku: Int
    var progress: String? = nil
    var viewSymbol = "play.fill"

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !owner.isEmpty {
                Text(owner)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if viewCount > 0 || danmaku > 0 || !(progress ?? "").isEmpty {
                IntactChipRow(spacing: 8) {
                    if viewCount > 0 { metaChip(viewSymbol, CountText.format(viewCount)) }
                    if danmaku > 0 { metaChip("text.bubble.fill", CountText.format(danmaku)) }
                    if let progress, !progress.isEmpty {
                        Text(progress)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metaChip(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            Text(text)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Keeps each child at its ideal width and drops trailing children that do not fit.
struct IntactChipRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let limit = proposal.width ?? .greatestFiniteMagnitude
        var width: CGFloat = 0
        var height: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let next = width == 0 ? size.width : width + spacing + size.width
            if width > 0, next > limit + 0.5 { break }
            width = next
            height = max(height, size.height)
        }
        let capped = limit.isFinite ? min(width, limit) : width
        return CGSize(width: max(capped, 0), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var dropped = false
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let next = x == bounds.minX ? size.width : (x - bounds.minX) + spacing + size.width
            if dropped || (x > bounds.minX && next > bounds.width + 0.5) {
                dropped = true
                subview.place(
                    at: CGPoint(x: bounds.minX, y: bounds.minY),
                    proposal: ProposedViewSize(width: 0, height: 0)
                )
                continue
            }
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + spacing
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
