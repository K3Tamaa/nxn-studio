import SwiftUI

// MARK: - Brand

struct BrandMark: View {
    var size: CGFloat = 28

    var body: some View {
        Canvas { ctx, sz in
            let w = sz.width, h = sz.height
            let bodyRect = CGRect(x: w * 0.10, y: h * 0.08, width: w * 0.80, height: h * 0.84)
            let corner = w * 0.22
            var shell = Path(roundedRect: bodyRect, cornerRadius: corner, style: .continuous)

            // Cartridge notch cut out of the top edge.
            let notch = CGRect(x: bodyRect.midX - w * 0.17, y: bodyRect.minY - 1,
                               width: w * 0.34, height: h * 0.15)
            shell.addPath(Path(roundedRect: notch, cornerRadius: notch.height * 0.42, style: .continuous))

            ctx.fill(shell, with: .linearGradient(
                Gradient(colors: [Color(hex: 0xFFB067), Color(hex: 0xFF4D33)]),
                startPoint: CGPoint(x: w * 0.15, y: 0),
                endPoint: CGPoint(x: w * 0.85, y: h)
            ), style: FillStyle(eoFill: true))

            // Inner label window.
            let label = CGRect(x: w * 0.24, y: h * 0.40, width: w * 0.52, height: h * 0.34)
            ctx.fill(Path(roundedRect: label, cornerRadius: w * 0.06, style: .continuous),
                     with: .color(Color(hex: 0x1A0D0A, alpha: 0.78)))
            ctx.stroke(Path(roundedRect: label, cornerRadius: w * 0.06, style: .continuous),
                       with: .color(.white.opacity(0.22)), lineWidth: max(0.6, w * 0.012))

            // Two pin lights.
            for i in 0..<2 {
                let dot = CGRect(x: label.minX + w * 0.09 + CGFloat(i) * w * 0.11,
                                 y: label.midY - w * 0.018,
                                 width: w * 0.036, height: w * 0.036)
                ctx.fill(Path(ellipseIn: dot), with: .color(Color(hex: 0xFFB067, alpha: 0.95)))
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.ember.opacity(0.35), radius: size * 0.28, y: size * 0.08)
        .accessibilityLabel("NXN Studio")
    }
}

// MARK: - Cover art

struct CoverArt: View {
    let seed: String
    let monogram: String
    var height: CGFloat = 118
    var badge: String? = nil

    var body: some View {
        let colors = CoverTint.colors(for: seed)
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [colors.0, colors.1], startPoint: .topLeading, endPoint: .bottomTrailing)

            // Fine diagonal weave.
            Canvas { ctx, sz in
                var path = Path()
                let step: CGFloat = 9
                var x: CGFloat = -sz.height
                while x < sz.width + sz.height {
                    path.move(to: CGPoint(x: x, y: sz.height))
                    path.addLine(to: CGPoint(x: x + sz.height, y: 0))
                    x += step
                }
                ctx.stroke(path, with: .color(.white.opacity(0.10)), lineWidth: 0.7)
            }

            // Soft light.
            RadialGradient(colors: [.white.opacity(0.30), .clear],
                           center: UnitPoint(x: 0.18, y: 0.12),
                           startRadius: 0, endRadius: height * 1.5)
                .blendMode(.softLight)

            LinearGradient(colors: [.clear, .black.opacity(0.42)],
                           startPoint: .center, endPoint: .bottom)

            Text(monogram)
                .font(.numeral(height * 0.44, weight: .bold))
                .tracking(-2)
                .foregroundStyle(.white.opacity(0.92))
                .padding(.leading, 16)
                .padding(.bottom, 8)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)

            HStack {
                if let badge {
                    Text(badge)
                        .font(.label(9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.black.opacity(0.72))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.82), in: Capsule())
                }
                Spacer()
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(12)
        }
        .frame(height: height)
        .clipped()
    }
}

/// Cover art: IGDB artwork when available, the game's own extracted icon after
/// a build, otherwise a generative monogram tile derived from the title ID.
struct GameCover: View {
    let game: Game
    var iconURL: URL?
    var posterURL: URL?
    /// Wide 16:9 artwork, preferred for banners.
    var wideURL: URL?
    var height: CGFloat = 104
    var badge: String? = nil
    /// Banners crop the portrait cover with a blurred backdrop instead of
    /// cutting the art; compact tiles always fill.
    var bannerStyle: Bool = true

    private func image(at url: URL?) -> NSImage? {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    private var wideImage: NSImage? { bannerStyle ? image(at: wideURL) : nil }
    private var coverImage: NSImage? { image(at: posterURL) }
    private var iconImage: NSImage? { image(at: iconURL) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let image = wideImage {
                fill(image)
                scrim
                badgeView
            } else if let image = coverImage {
                if bannerStyle {
                    // Blurred backdrop keeps the banner full while the cover
                    // itself stays whole and centred.
                    ZStack {
                        fill(image).blur(radius: 28).opacity(0.45).clipped()
                        Color.black.opacity(0.30)
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
                    }
                    scrim
                    badgeView
                } else {
                    fill(image)
                    scrim
                    badgeView
                }
            } else if let image = iconImage {
                fill(image)
                scrim
                badgeView
            } else {
                CoverArt(seed: game.id, monogram: game.monogram, height: height, badge: badge)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
    }

    /// Aspect-fill, explicitly centred in the available box.
    private func fill(_ image: NSImage) -> some View {
        GeometryReader { geo in
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                .clipped()
        }
    }

    private var scrim: some View {
        LinearGradient(colors: [.clear, .black.opacity(0.34)],
                       startPoint: .center, endPoint: .bottom)
    }

    @ViewBuilder
    private var badgeView: some View {
        if let badge {
            Text(badge)
                .font(.label(9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.black.opacity(0.72))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.white.opacity(0.82), in: Capsule())
                .padding(12)
        }
    }
}

// MARK: - Surfaces

struct Panel<Content: View>: View {
    var padding: CGFloat = 18
    var radius: CGFloat = Theme.corner
    var fill: Color = Theme.panel
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.label(9.5, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(Theme.textTertiary)
    }
}

// MARK: - Buttons

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var enabled: Bool = true
    var loading: Bool = false
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if loading {
                    ProgressView().controlSize(.small).tint(.black)
                } else if let icon {
                    Image(systemName: icon).font(.system(size: 12, weight: .bold))
                }
                Text(title).font(.label(13, weight: .semibold))
            }
            .foregroundStyle(.black.opacity(enabled ? 0.92 : 0.4))
            .padding(.horizontal, 18)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.emberGradient)
                    .opacity(enabled ? 1 : 0.35)
                    .brightness(hover && enabled ? 0.06 : 0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(hover && enabled ? 0.28 : 0.14), lineWidth: 1)
            )
            .shadow(color: Theme.ember.opacity(enabled ? (hover ? 0.42 : 0.26) : 0), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.16), value: hover)
    }
}

struct GhostButton: View {
    let title: String
    var icon: String? = nil
    var tint: Color = Theme.textSecondary
    var compact: Bool = false
    let action: () -> Void

    @State private var hover = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: compact ? 10 : 11, weight: .semibold)) }
                if !title.isEmpty { Text(title).font(.label(compact ? 11 : 12, weight: .medium)) }
            }
            .foregroundStyle(hover && isEnabled ? Theme.text : tint)
            .padding(.horizontal, compact ? 9 : 12)
            .frame(height: compact ? 26 : 32)
            .background(
                RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous)
                    .fill(.white.opacity(hover && isEnabled ? 0.075 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.14), value: hover)
    }
}

struct IconButton: View {
    let icon: String
    var help: String = ""
    var tint: Color = Theme.textSecondary
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(hover ? Theme.text : tint)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(hover ? 0.08 : 0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hover = $0 }
    }
}

// MARK: - Chips & badges

struct StatusDot: View {
    let color: Color
    var size: CGFloat = 7
    var pulsing: Bool = false
    @State private var animate = false

    var body: some View {
        ZStack {
            if pulsing {
                Circle().fill(color.opacity(0.35))
                    .frame(width: size * 2.6, height: size * 2.6)
                    .scaleEffect(animate ? 1.0 : 0.6)
                    .opacity(animate ? 0 : 1)
                    .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: animate)
            }
            Circle().fill(color).frame(width: size, height: size)
        }
        .onAppear { if pulsing { animate = true } }
    }
}

struct Chip: View {
    let text: String
    var icon: String? = nil
    var color: Color = Theme.textSecondary
    var background: Color = Color.white.opacity(0.045)
    var bordered: Bool = true

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 8.5, weight: .bold)) }
            Text(text).font(.label(10, weight: .semibold)).tracking(0.2)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(background))
        .overlay(Capsule().strokeBorder(bordered ? Theme.hairline : .clear, lineWidth: 1))
    }
}

struct Kbd: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.mono(9.5, weight: .medium))
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

// MARK: - Progress ring

struct ProgressRing: View {
    var progress: Double        // 0...1
    var size: CGFloat = 132
    var lineWidth: CGFloat = 9
    var indeterminate: Bool = false
    var tint: LinearGradient = Theme.emberGradient
    var caption: String? = nil

    @State private var spin = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.white.opacity(0.06), lineWidth: lineWidth)

            if indeterminate {
                Circle()
                    .trim(from: 0.06, to: 0.30)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .onAppear {
                        withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { spin = true }
                    }
            } else {
                Circle()
                    .trim(from: 0, to: max(0.004, min(progress, 1)))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Theme.ember.opacity(0.35), radius: 5)
                    .animation(.easeOut(duration: 0.35), value: progress)
            }

            VStack(spacing: 1) {
                Text(indeterminate ? "…" : "\(Int((progress * 100).rounded()))%")
                    .font(.numeral(size * 0.235, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
                if let caption {
                    Text(caption)
                        .font(.label(9, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.textTertiary)
                        .textCase(.uppercase)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Rows

struct DataRow: View {
    let label: String
    let value: String
    var valueColor: Color = Theme.text
    var mono: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label)
                .font(.label(11.5))
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 8)
            Text(value)
                .font(mono ? .mono(11) : .label(11.5, weight: .medium))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

struct HoverScale: ViewModifier {
    @State private var hover = false
    var scale: CGFloat = 1.006
    var glow: Bool = true

    func body(content: Content) -> some View {
        content
            .scaleEffect(hover ? scale : 1)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(.white.opacity(hover && glow ? 0.14 : 0), lineWidth: 1)
            )
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.18), value: hover)
    }
}

extension View {
    func hoverLift(scale: CGFloat = 1.006, glow: Bool = true) -> some View {
        modifier(HoverScale(scale: scale, glow: glow))
    }
}
