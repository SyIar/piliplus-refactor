import SwiftUI

enum Palette {
    static let bili = Color(red: 0.984, green: 0.447, blue: 0.600)
    static let coin = Color(red: 0.98, green: 0.72, blue: 0.28)
    static let ink = Color(red: 0.07, green: 0.07, blue: 0.09)
}

extension View {
    /// Opaque plate for scrolling content. Liquid Glass stays on system bars and controls.
    func contentPlate(radius: CGFloat = 22) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color(.secondarySystemBackground))
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

    /// Soft edge under system bars. Axis is `.top` / `.bottom`; `.vertical` is not a scroll-edge set.
    func scrollEdgeSoft() -> some View {
        self
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
    }
}

struct CountText: View {
    let value: Int
    var body: some View {
        Text(Self.format(value))
    }

    static func format(_ value: Int) -> String {
        let sign = value < 0 ? "-" : ""
        let magnitude = Swift.abs(value)
        if magnitude >= 100_000_000 {
            let yi = Double(magnitude) / 100_000_000
            if yi < 10 {
                let tenths = (yi * 10).rounded() / 10
                if tenths >= 10 { return sign + "\(Int(tenths.rounded()))亿" }
                if Swift.abs(tenths - tenths.rounded()) < 0.001 { return sign + "\(Int(tenths.rounded()))亿" }
                return sign + String(format: "%.1f亿", tenths)
            }
            return sign + "\(Int(yi.rounded()))亿"
        }
        if magnitude >= 10_000 {
            let wan = (Double(magnitude) / 10_000).rounded()
            if wan >= 10_000 { return sign + "\(Int((wan / 10_000).rounded()))亿" }
            return sign + "\(Int(wan))万"
        }
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

struct ProfileMark: View {
    let name: String
    var face: String = ""
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle().fill(Palette.bili.gradient)
            if face.isEmpty {
                Text(String(name.prefix(1)))
                    .font(size > 40 ? .title2.bold() : .caption.weight(.bold))
                    .foregroundStyle(.white)
            } else {
                RemoteImage(url: face, ratio: 1, maxPixel: size * 3)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
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

    init(url: String, maxPixel: CGFloat) {
        self.url = url
        self.maxPixel = maxPixel
        let initial = URL(string: url).flatMap { ImageStore.cachedImage(url: $0, maxPixel: maxPixel) }
        _image = State(initialValue: initial)
    }

    var body: some View {
        ZStack {
            if image == nil {
                LinearGradient(colors: [Palette.bili.opacity(0.35), Color.blue.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            PreparedImage(image: image)
        }
        .task(id: url) {
            guard image == nil, let parsed = URL(string: url) else { return }
            let loaded = await ImageStore.shared.image(url: parsed, maxPixel: maxPixel)
            guard !Task.isCancelled, let loaded else { return }
            image = loaded
        }
    }
}

/// Assigns a prepared bitmap in place. Swapping `Image(uiImage:)` rebuilds
/// the SwiftUI node and was showing up as a long frame when several covers landed together.
private struct PreparedImage: UIViewRepresentable {
    var image: UIImage?

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        view.image = image
        return view
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        if uiView.image !== image {
            uiView.image = image
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
            .glassEffect(.regular, in: Capsule())
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
