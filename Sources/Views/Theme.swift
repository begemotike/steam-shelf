import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

enum Theme {
    enum Palette {
        static let walnutDark = Color(hex: 0x3B2415)
        static let walnut = Color(hex: 0x5C3A21)
        static let walnutLight = Color(hex: 0x7A4E2D)
        static let walnutHighlight = Color(hex: 0xA87444)
        static let grainLine = Color(hex: 0x2A170C)
        static let backPanel = Color(hex: 0x2E1B10)
        static let backPanelDark = Color(hex: 0x1C100A)
        static let mahogany = Color(hex: 0x6B2E1F)
        static let brass = Color(hex: 0xB8893B)
        static let brassLight = Color(hex: 0xF0D48A)
        static let brassDark = Color(hex: 0x6E4E1C)
        static let brassInk = Color(hex: 0x3A2A10)
        static let cream = Color(hex: 0xF3E9D2)
        static let creamShade = Color(hex: 0xE2D3B0)
        static let ink = Color(hex: 0x2B1D12)
        static let inkSoft = Color(hex: 0x6B5842)
        static let labelRed = Color(hex: 0x8C2F1E)
        static let starGold = Color(hex: 0xD9A531)
        static let starEmpty = Color(hex: 0xCDBB94)
        static let achieveGreen = Color(hex: 0x5F7F3A)
        static let backdrop = Color(hex: 0x15110E)
        static let backdropEdge = Color(hex: 0x070504)
        static let hoverGlow = Color(hex: 0xFFE6A8, alpha: 0.25)
        static let dimOverlay = Color(hex: 0x000000, alpha: 0.70)
        static let stageSpotlight = Color(hex: 0x2A1D14)

        // Raw hex for the texture generator.
        static let walnutHex: UInt32 = 0x5C3A21
        static let walnutDarkHex: UInt32 = 0x3B2415
        static let walnutLightHex: UInt32 = 0x7A4E2D
        static let grainLineHex: UInt32 = 0x2A170C
        static let backPanelHex: UInt32 = 0x2E1B10
        static let backdropHex: UInt32 = 0x15110E
    }

    enum Fonts {
        static func baskerville(_ size: CGFloat) -> Font { .custom("Baskerville", size: size) }
        static func baskervilleBold(_ size: CGFloat) -> Font { .custom("Baskerville-Bold", size: size) }
        static func baskervilleSemiBold(_ size: CGFloat) -> Font { .custom("Baskerville-SemiBold", size: size) }
        static func baskervilleItalic(_ size: CGFloat) -> Font { .custom("Baskerville-Italic", size: size) }
        static func copperplate(_ size: CGFloat) -> Font { .custom("Copperplate", size: size) }
        static func copperplateBold(_ size: CGFloat) -> Font { .custom("Copperplate-Bold", size: size) }
        static func noteworthy(_ size: CGFloat) -> Font { .custom("Noteworthy-Light", size: size) }
        static func noteworthyBold(_ size: CGFloat) -> Font { .custom("Noteworthy-Bold", size: size) }
    }

    enum Metrics {
        // Window
        static let windowDefaultW: CGFloat = 1180
        static let windowDefaultH: CGFloat = 960
        static let windowMinW: CGFloat = 820
        static let windowMinH: CGFloat = 700

        // Case frame (points; the bay flexes with the window, see BayLayout)
        static let crownH: CGFloat = 64
        static let baseH: CGFloat = 44
        static let stileW: CGFloat = 84
        static let plinthH: CGFloat = 6
        static let trafficLightClearance: CGFloat = 84

        // Box design units (1 unit = 1 pt at BayLayout.scale == 1)
        static let boxW: CGFloat = 120
        static let boxH: CGFloat = 180
        static let spineSliverW: CGFloat = 8
        static let topSliverH: CGFloat = 4

        // Handles
        static let handleBodyW: CGFloat = 46
        static let handleBodyH: CGFloat = 150
        static let mortiseW: CGFloat = 54
        static let mortiseH: CGFloat = 160

        // Open box
        static let frontFaceFill: CGFloat = 0.628
        static let editorPanelW: CGFloat = 340

        // Textures / canvases
        static let coverW: CGFloat = 600
        static let coverH: CGFloat = 900
        static let spineW: CGFloat = 200
        static let spineH: CGFloat = 1200
        static let woodTextureSize = 1024
        static let linenTextureSize = 512
    }

    enum Motion {
        static let hover = Animation.spring(response: 0.22, dampingFraction: 0.8)
        static let pageSlide = Animation.spring(response: 0.55, dampingFraction: 0.86)
        static let pageJump = Animation.spring(response: 0.42, dampingFraction: 0.9)
        static let lift = Animation.easeOut(duration: 0.16)
        static let fly = Animation.spring(response: 0.45, dampingFraction: 0.85)
        static let crossfade = Animation.easeInOut(duration: 0.15)
        static let panel = Animation.spring(response: 0.4, dampingFraction: 0.85)
        static let artFade = Animation.easeIn(duration: 0.25)
    }
}

// MARK: - Shared chrome helpers

private struct ShelfScaleKey: EnvironmentKey { static let defaultValue: CGFloat = 1 }

extension EnvironmentValues {
    /// Points per design unit (BayLayout.scale = boxH / 180) inside the bay.
    var shelfScale: CGFloat {
        get { self[ShelfScaleKey.self] }
        set { self[ShelfScaleKey.self] = newValue }
    }
}

extension Theme {
    static let brassGradient = LinearGradient(
        stops: [.init(color: Palette.brassLight, location: 0),
                .init(color: Palette.brass, location: 0.45),
                .init(color: Palette.brassDark, location: 1)],
        startPoint: .top, endPoint: .bottom)

    static let gloss = LinearGradient(
        stops: [.init(color: .white.opacity(0.22), location: 0),
                .init(color: .white.opacity(0), location: 0.45),
                .init(color: .white.opacity(0.06), location: 1)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// A wood (or linen) texture tiled over its frame; flat color until the texture is generated.
struct TiledFill: View {
    let image: Image?
    let fallback: Color

    var body: some View {
        if let image {
            image.resizable(resizingMode: .tile)
        } else {
            fallback
        }
    }
}

/// Brass rounded plate with bevel, used for the nameplate, handle plates and buttons.
struct BrassPlate: View {
    var cornerRadius: CGFloat = 4
    var bevel: CGFloat = 1

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape.fill(Theme.brassGradient)
            .overlay(shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.45), .clear, .black.opacity(0.35)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: bevel))
            .overlay(shape.strokeBorder(Theme.Palette.brassDark.opacity(0.6), lineWidth: 0.5))
    }
}

/// Engraved text: the same text 1 unit lower in white underneath.
struct EngravedText: View {
    let text: String
    let font: Font
    var color: Color = Theme.Palette.brassInk
    var highlight: Color = .white.opacity(0.4)
    var offset: CGFloat = 1

    var body: some View {
        ZStack {
            Text(text).font(font).foregroundStyle(highlight).offset(y: offset)
            Text(text).font(font).foregroundStyle(color)
        }
    }
}

/// Brass pill button (open-box toolbar, empty state, editor "Done").
struct BrassPillButtonStyle: ButtonStyle {
    var height: CGFloat = 30
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.baskervilleSemiBold(13))
            .foregroundStyle(Theme.Palette.brassInk)
            .padding(.horizontal, 14)
            .frame(height: height)
            .background(
                Capsule().fill(Theme.brassGradient)
                    .scaleEffect(y: configuration.isPressed ? -1 : 1)
                    .overlay(Capsule().stroke(Theme.Palette.brassDark, lineWidth: 1))
            )
            .brightness(hovering ? 0.06 : 0)
            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
            .onHover { hovering = $0 }
            .pointerStyle(.link)
    }
}

/// Cream index card with ruled lines and a red margin line (empty state, note card).
struct LinedPaper: View {
    var spacing: CGFloat = 26
    var marginX: CGFloat = 40
    var firstLine: CGFloat = 40

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Theme.Palette.cream
                ForEach(0..<max(0, Int((geo.size.height - firstLine) / spacing) + 1), id: \.self) { i in
                    Color(hex: 0x9CB8D8, alpha: 0.5)
                        .frame(height: 1)
                        .offset(y: firstLine + CGFloat(i) * spacing)
                }
                Color(hex: 0xD98080).frame(width: 1).offset(x: marginX)
            }
        }
    }
}

/// Mahogany thumbtack: a 14-pt circle with a radial highlight and a small drop shadow.
struct Thumbtack: View {
    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [Color(hex: 0xC26A54), Theme.Palette.mahogany, Color(hex: 0x3A160E)],
                                 center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 10))
            .frame(width: 14, height: 14)
            .shadow(color: .black.opacity(0.5), radius: 2, x: 1, y: 2)
    }
}
