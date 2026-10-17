import SwiftUI

enum Palette {
    static let bili = Color(red: 0.984, green: 0.447, blue: 0.600)
    static let coin = Color(red: 0.98, green: 0.72, blue: 0.28)
    static let ink = Color(red: 0.07, green: 0.07, blue: 0.09)
}

struct AuroraBackground: View, Equatable {
    var scheme: ColorScheme

    static func == (lhs: AuroraBackground, rhs: AuroraBackground) -> Bool {
        lhs.scheme == rhs.scheme
    }

    var body: some View {
        ZStack {
            (scheme == .dark ? Palette.ink : Color(red: 0.95, green: 0.95, blue: 0.97))
            RadialGradient(
                colors: [Palette.bili.opacity(scheme == .dark ? 0.38 : 0.24), .clear],
                center: .topTrailing,
                startRadius: 12,
                endRadius: 460
            )
            RadialGradient(
                colors: [Color(red: 0.36, green: 0.55, blue: 1).opacity(scheme == .dark ? 0.28 : 0.16), .clear],
                center: .bottomLeading,
                startRadius: 8,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
        .drawingGroup(opaque: false)
        .allowsHitTesting(false)
    }
}

struct AuroraBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        AuroraBackground(scheme: scheme).equatable()
    }
}

extension View {
    @ViewBuilder
    func liquidGlass<S: Shape>(
        _ glass: Glass = .regular,
        in shape: S,
        interactive: Bool = false
    ) -> some View {
        let styled: Glass = interactive ? glass.interactive() : glass
        self.glassEffect(styled, in: shape)
    }

    func glassCard(radius: CGFloat = 28, interactive: Bool = false) -> some View {
        liquidGlass(in: RoundedRectangle(cornerRadius: radius, style: .continuous), interactive: interactive)
    }

    func glassCapsule(interactive: Bool = true) -> some View {
        liquidGlass(in: Capsule(), interactive: interactive)
    }

    /// Opaque plate for scrolling content. Liquid Glass stays on bars and controls.
    func contentPlate(radius: CGFloat = 22) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color(.secondarySystemBackground).opacity(0.94))
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                }
        }
    }

    func selectionCapsule(selected: Bool) -> some View {
        background {
            if selected {
                Capsule().fill(Palette.bili.gradient)
            } else {
                Capsule().fill(Color.primary.opacity(0.06))
            }
        }
    }

    /// Registers a custom top bar so the feed can scroll under it with an edge effect.
    func feedChrome<Bar: View>(@ViewBuilder bar: () -> Bar) -> some View {
        safeAreaBar(edge: .top, spacing: 0, content: bar)
            .scrollEdgeEffectStyle(.soft, for: .vertical)
    }
}

struct GlassIconButton: View {
    let system: String
    var badge: Int = 0
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 40, height: 40)
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text(badge > 99 ? "99+" : "\(badge)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Palette.bili, in: Capsule())
                            .offset(x: 6, y: -4)
                    }
                }
        }
        .buttonStyle(.plain)
        .glassCapsule()
    }
}

struct CountText: View {
    let value: Int
    var body: some View {
        Text(Self.format(value))
    }

    static func format(_ value: Int) -> String {
        let abs = Swift.abs(value)
        if abs >= 100_000_000 { return String(format: "%.1f亿", Double(value) / 100_000_000).replacingOccurrences(of: ".0", with: "") }
        if abs >= 10_000 { return String(format: "%.1f万", Double(value) / 10_000).replacingOccurrences(of: ".0", with: "") }
        return "\(value)"
    }
}

struct DurationBadge: View {
    let seconds: Int
    var body: some View {
        Text(Self.clock(seconds))
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    static func clock(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

struct RemoteImage: View {
    let url: String
    var ratio: CGFloat = 16 / 9
    var maxPixel: CGFloat = 560

    var body: some View {
        Color.clear
            .aspectRatio(ratio, contentMode: .fit)
            .overlay { CachedImage(url: url, maxPixel: maxPixel) }
            .clipped()
    }
}

private struct CachedImage: View {
    let url: String
    var maxPixel: CGFloat
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Palette.bili.opacity(0.35), Color.blue.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .task(id: url) {
            guard let parsed = URL(string: url) else { return }
            let loaded = await ImageStore.shared.image(url: parsed, maxPixel: maxPixel)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}

struct ToastBanner: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassCapsule(interactive: false)
            .padding(.horizontal, 28)
    }
}

struct ShimmerCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.08))
                .aspectRatio(16 / 9, contentMode: .fit)
            RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.08)).frame(height: 12)
            RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.06)).frame(width: 90, height: 10)
        }
        .redacted(reason: .placeholder)
    }
}
