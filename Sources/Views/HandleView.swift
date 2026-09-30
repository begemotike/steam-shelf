import SwiftUI

/// Wooden drawer-pull with brass posts and an engraved page-number plate.
struct HandleView: View {
    let side: HandleSide
    let label: Int?
    let action: () -> Void

    @State private var hovering = false

    private var enabled: Bool { label != nil }

    var body: some View {
        Button(action: action) { HandleArt(side: side, label: label, hovering: hovering, pressed: false) }
            .buttonStyle(HandlePressStyle(side: side, label: label, hovering: hovering))
            .onHover { hovering = $0 }
            .pointerStyle(enabled ? .link : nil)
            .allowsHitTesting(enabled)
            .help(helpText)
            .accessibilityLabel(side == .left ? "Previous page" : "Next page")
    }

    private var helpText: String {
        guard let label else { return "" }
        return side == .left ? "Page \(label) — double-click for first page" : "Page \(label) — double-click for last page"
    }
}

private struct HandlePressStyle: ButtonStyle {
    let side: HandleSide
    let label: Int?
    let hovering: Bool
    func makeBody(configuration: Configuration) -> some View {
        HandleArt(side: side, label: label, hovering: hovering, pressed: configuration.isPressed)
    }
}

private struct HandleArt: View {
    let side: HandleSide
    let label: Int?
    let hovering: Bool
    let pressed: Bool

    @Environment(\.shelfScale) private var s
    @State private var textures = TextureLibrary.shared

    private var enabled: Bool { label != nil }
    private var chevron: String { side == .left ? "‹" : "›" }

    var body: some View {
        let M = Theme.Metrics.self
        let w = M.handleBodyW * s, h = M.handleBodyH * s
        ZStack {
            // Body
            ZStack {
                TiledFill(image: textures.shelfWood, fallback: Theme.Palette.walnutLight)
                Theme.Palette.walnutLight.opacity(0.35)
                LinearGradient(stops: [.init(color: .white.opacity(0.18), location: 0),
                                       .init(color: .clear, location: 0.4),
                                       .init(color: .black.opacity(0.35), location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            }
            .frame(width: w, height: h)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(.black.opacity(0.35), lineWidth: max(0.5, s)))
            .shadow(color: .black.opacity(0.55), radius: (pressed ? 3 : 6) * s, x: 3 * s, y: (pressed ? 2 : 5) * s)

            // Posts
            post.offset(y: -(h / 2 - 22 * s))
            post.offset(y: h / 2 - 22 * s)

            // Chevron engraved in the wood
            ZStack {
                Text(chevron).font(Theme.Fonts.copperplate(16 * s)).foregroundStyle(.white.opacity(0.15)).offset(y: s)
                Text(chevron).font(Theme.Fonts.copperplate(16 * s)).foregroundStyle(.black.opacity(0.45))
            }
            .offset(y: -34 * s)

            // Number plate
            ZStack {
                BrassPlate(cornerRadius: 4 * s, bevel: max(1, s))
                if let label {
                    EngravedText(text: "\(label)", font: Theme.Fonts.copperplateBold(18 * s), offset: max(1, s))
                }
            }
            .frame(width: 36 * s, height: 30 * s)
            .brightness(hovering && enabled ? 0.08 : 0)
            .offset(y: 6 * s)
        }
        .frame(width: w, height: h)
        .scaleEffect(pressed ? 0.97 : 1)
        .offset(x: hovering && enabled ? (side == .left ? -2 : 2) * s : 0)
        .animation(Theme.Motion.hover, value: hovering)
        .animation(.easeOut(duration: 0.08), value: pressed)
        .opacity(enabled ? 1 : 0.35)
        .contentShape(Capsule())
    }

    private var post: some View {
        let d = 12 * s
        return Circle()
            .fill(RadialGradient(colors: [Theme.Palette.brassLight, Theme.Palette.brass, Theme.Palette.brassDark],
                                 center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: d))
            .overlay(Circle().stroke(Theme.Palette.brassDark, lineWidth: max(0.5, s)))
            .overlay(Rectangle().fill(Theme.Palette.brassInk.opacity(0.8)).frame(width: 5 * s, height: max(0.8, s * 0.9)).rotationEffect(.degrees(-20)))
            .frame(width: d, height: d)
    }
}
