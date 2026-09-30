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
        static let headerHeight: CGFloat = 56
        static let bookcasePadding: CGFloat = 24

        // Bookcase design units
        static let bookcaseW: CGFloat = 1100
        static let bookcaseH: CGFloat = 1000
        static let crownH: CGFloat = 40
        static let baseH: CGFloat = 48
        static let plinthH: CGFloat = 6
        static let stileW: CGFloat = 36
        static let bayW: CGFloat = 700
        static let handleColumnW: CGFloat = 80
        static let rowH: CGFloat = 222
        static let rowHeadroom: CGFloat = 22
        static let plankFaceH: CGFloat = 20
        static let boxW: CGFloat = 120
        static let boxH: CGFloat = 180
        static let boxGap: CGFloat = 36
        static let spineSliverW: CGFloat = 8
        static let topSliverH: CGFloat = 4
        static let caseW: CGFloat = 36 + 700 + 36
        static let caseH: CGFloat = 40 + 888 + 48

        // Handles
        static let handleBodyW: CGFloat = 46
        static let handleBodyH: CGFloat = 150
        static let handleOffset: CGFloat = 20

        // Open box
        static let frontFaceFill: CGFloat = 0.676
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
