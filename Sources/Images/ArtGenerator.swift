import SwiftUI
import CoreGraphics
import OSLog

/// The single documented `@unchecked Sendable` exception: `CGImage` is immutable and thread-safe.
struct SendableImage: @unchecked Sendable { let cgImage: CGImage }

struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform Double in [0, 1).
    mutating func nextUnit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func double(in range: ClosedRange<Double>) -> Double { range.lowerBound + nextUnit() * (range.upperBound - range.lowerBound) }
    mutating func int(in range: ClosedRange<Int>) -> Int { range.lowerBound + Int(next() % UInt64(range.upperBound - range.lowerBound + 1)) }
}

typealias RGB = SIMD3<Double>

enum WoodGrain: Sendable { case horizontal, vertical }

struct WoodPalette: Sendable {
    let base: RGB
    let dark: RGB
    let light: RGB

    static func rgb(hex: UInt32) -> RGB {
        RGB(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    static let plank = WoodPalette(base: rgb(hex: 0x5C3A21), dark: rgb(hex: 0x2A170C), light: rgb(hex: 0x7A4E2D))
    static let caseWood = WoodPalette(base: rgb(hex: 0x3B2415), dark: rgb(hex: 0x1E1109), light: rgb(hex: 0x5C3A21))
    static let back = WoodPalette(base: rgb(hex: 0x2E1B10), dark: rgb(hex: 0x140B06), light: rgb(hex: 0x452A18))
}

enum ArtGenerator {
    private static func makeContext(width: Int, height: Int) -> CGContext {
        // A failure here means the process is out of memory; there is no meaningful recovery.
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            fatalError("CGContext allocation failed (\(width)x\(height))")
        }
        ctx.interpolationQuality = .high
        return ctx
    }

    private static func cg(_ c: RGB, _ a: Double) -> CGColor {
        CGColor(srgbRed: c.x, green: c.y, blue: c.z, alpha: a)
    }

    // MARK: Wood

    static func woodTexture(size: Int, seed: UInt64, grain: WoodGrain, palette: WoodPalette) -> CGImage {
        let ctx = makeContext(width: size, height: size)
        var rng = SplitMix64(seed: seed)
        let s = Double(size)
        let k = s / 1024   // all constants below are specified at 1024 px

        if grain == .vertical {
            // Rotate the drawing space 90° about the center so "horizontal" strokes run vertically.
            ctx.translateBy(x: s / 2, y: s / 2)
            ctx.rotate(by: .pi / 2)
            ctx.translateBy(x: -s / 2, y: -s / 2)
        }

        // 1. Base
        ctx.setFillColor(cg(palette.base, 1))
        ctx.fill(CGRect(x: -s, y: -s, width: s * 3, height: s * 3))

        // 2. Tone bands with softened edges
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        for _ in 0..<7 {
            let y = rng.double(in: 0...s)
            let h = rng.double(in: 60...200) * k
            let useLight = rng.nextUnit() < 0.5
            let a = rng.double(in: 0.04...0.10)
            let color = useLight ? palette.light : palette.dark
            let comps: [CGFloat] = [
                color.x, color.y, color.z, 0,
                color.x, color.y, color.z, a,
                color.x, color.y, color.z, a,
                color.x, color.y, color.z, 0,
            ]
            if let gradient = CGGradient(colorSpace: space, colorComponents: comps, locations: [0, 0.3, 0.7, 1], count: 4) {
                ctx.saveGState()
                ctx.clip(to: CGRect(x: 0, y: y, width: s, height: h))
                ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: y), end: CGPoint(x: 0, y: y + h), options: [])
                ctx.restoreGState()
            }
        }

        // 3. Grain lines (integer k -> horizontally seamless; drawn at ±s for vertical seamlessness)
        for _ in 0..<260 {
            let y0 = rng.double(in: 0...s)
            let amp = rng.double(in: 2...14) * k
            let k1 = Double(rng.int(in: 1...4))
            let k2 = Double(rng.int(in: 5...9))
            let p1 = rng.double(in: 0...(2 * .pi))
            let p2 = rng.double(in: 0...(2 * .pi))
            let width = rng.double(in: 0.5...2.4) * k
            let isDark = rng.nextUnit() < 0.8
            let alpha = isDark ? rng.double(in: 0.06...0.24) : rng.double(in: 0.04...0.12)
            ctx.setStrokeColor(cg(isDark ? palette.dark : palette.light, alpha))
            ctx.setLineWidth(width)
            for offset in [-s, 0, s] {
                ctx.beginPath()
                var first = true
                for x in stride(from: 0.0, through: s, by: 8 * k) {
                    let y = y0 + offset
                        + amp * sin(2 * .pi * k1 * x / s + p1)
                        + 0.35 * amp * sin(2 * .pi * k2 * x / s + p2)
                    if first { ctx.move(to: CGPoint(x: x, y: y)); first = false }
                    else { ctx.addLine(to: CGPoint(x: x, y: y)) }
                }
                ctx.strokePath()
            }
        }

        // 4. Knots
        for _ in 0..<2 {
            let margin = 100 * k
            let cx = rng.double(in: margin...(s - margin))
            let cy = rng.double(in: margin...(s - margin))
            ctx.setStrokeColor(cg(palette.dark, 0.10))
            ctx.setLineWidth(1.2 * k)
            for i in 0..<9 {
                let rx = (6 + Double(i) * (34.0 / 8)) * k
                ctx.strokeEllipse(in: CGRect(x: cx - rx, y: cy - rx * 0.45, width: rx * 2, height: rx * 0.9))
            }
            ctx.setFillColor(cg(palette.dark, 0.35))
            let r = 5 * k
            ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r * 0.45, width: r * 2, height: r * 0.9))
        }

        // 5. Pores
        let poreSize = max(1, k)
        for _ in 0..<30_000 {
            let x = rng.double(in: 0...s)
            let y = rng.double(in: 0...s)
            let dark = rng.nextUnit() < 0.7
            ctx.setFillColor(cg(dark ? palette.dark : palette.light, dark ? 0.05 : 0.04))
            ctx.fill(CGRect(x: x, y: y, width: poreSize, height: poreSize))
        }

        return ctx.makeImage()!
    }

    // MARK: Linen

    static func linenTexture(size: Int, seed: UInt64) -> CGImage {
        let ctx = makeContext(width: size, height: size)
        var rng = SplitMix64(seed: seed)
        let s = CGFloat(size)
        ctx.setFillColor(cg(WoodPalette.rgb(hex: Theme.Palette.backdropHex), 1))
        ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.025))
        for y in stride(from: 0, to: size, by: 2) { ctx.fill(CGRect(x: 0, y: CGFloat(y), width: s, height: 1)) }
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.06))
        for x in stride(from: 0, to: size, by: 2) { ctx.fill(CGRect(x: CGFloat(x), y: 0, width: 1, height: s)) }
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.03))
        for _ in 0..<20_000 {
            ctx.fill(CGRect(x: CGFloat(rng.int(in: 0...(size - 1))), y: CGFloat(rng.int(in: 0...(size - 1))), width: 1, height: 1))
        }
        return ctx.makeImage()!
    }

    // MARK: Color helpers

    static func averageColor(of image: CGImage) -> (r: Double, g: Double, b: Double) {
        let ctx = makeContext(width: 1, height: 1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let data = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return (0.2, 0.2, 0.2) }
        let a = Double(data[3]) / 255
        guard a > 0 else { return (0.2, 0.2, 0.2) }
        return (Double(data[0]) / 255 / a, Double(data[1]) / 255 / a, Double(data[2]) / 255 / a)
    }

    static func spineColor(from avg: (r: Double, g: Double, b: Double)) -> Color {
        let (h, s, v) = hsb(avg)
        let brightness = min(max(v * 0.45, 0.10), 0.35)
        return Color(hue: h, saturation: s * 0.8, brightness: brightness)
    }

    private static func hsb(_ c: (r: Double, g: Double, b: Double)) -> (h: Double, s: Double, v: Double) {
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b)
        let d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == c.r { h = ((c.g - c.b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == c.g { h = (c.b - c.r) / d + 2 }
            else { h = (c.r - c.g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }

    // MARK: SwiftUI -> image

    @MainActor static func render<V: View>(_ view: V, size: CGSize, scale: CGFloat = 2) -> CGImage? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = scale
        return renderer.cgImage
    }

    @MainActor static func placeholderCover(title: String, appID: Int) -> CGImage {
        let size = CGSize(width: Theme.Metrics.coverW, height: Theme.Metrics.coverH)
        return render(PlaceholderCoverView(title: title, appID: appID), size: size)
            ?? fallbackImage(width: 1200, height: 1800)
    }

    @MainActor static func headerCover(title: String, appID: Int, header: CGImage) -> CGImage {
        let size = CGSize(width: Theme.Metrics.coverW, height: Theme.Metrics.coverH)
        return render(HeaderCompositeCoverView(title: title, appID: appID, header: header), size: size)
            ?? placeholderCover(title: title, appID: appID)
    }

    private static func fallbackImage(width: Int, height: Int) -> CGImage {
        let ctx = makeContext(width: width, height: height)
        ctx.setFillColor(cg(WoodPalette.rgb(hex: 0x2F4858), 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }
}

// MARK: - Placeholder cover

struct CoverPalette {
    let top: Color
    let bottom: Color
    let accent: Color

    static let all: [CoverPalette] = [
        (0x2F4858, 0x1B2A35, 0xF6AE2D), (0x6B2E1F, 0x3A160E, 0xF3E9D2),
        (0x33658A, 0x1D3A50, 0xF6AE2D), (0x4B3F72, 0x2A2342, 0xFFC857),
        (0x3D5A3A, 0x22341F, 0xE9D8A6), (0x7A4E2D, 0x3B2415, 0xF0D48A),
        (0x1F2041, 0x0F1022, 0xE26D5C), (0x5E2B4E, 0x33172A, 0xF3E9D2),
    ].map { CoverPalette(top: Color(hex: $0.0), bottom: Color(hex: $0.1), accent: Color(hex: $0.2)) }

    static func forApp(_ appID: Int) -> CoverPalette { all[((appID % 8) + 8) % 8] }
}

private struct Sunburst: Shape {
    var rays = 12
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let radius = max(rect.width, rect.height) * 1.2
        let step = 2 * Double.pi / Double(rays)
        for i in 0..<rays {
            let a0 = step * Double(i)
            let a1 = a0 + step / 2
            p.move(to: c)
            p.addLine(to: CGPoint(x: c.x + radius * cos(a0), y: c.y + radius * sin(a0)))
            p.addLine(to: CGPoint(x: c.x + radius * cos(a1), y: c.y + radius * sin(a1)))
            p.closeSubpath()
        }
        return p
    }
}

struct PlaceholderCoverView: View {
    let title: String
    let appID: Int

    var body: some View {
        let pal = CoverPalette.forApp(appID)
        let w = Theme.Metrics.coverW, h = Theme.Metrics.coverH
        ZStack {
            LinearGradient(colors: [pal.top, pal.bottom], startPoint: .top, endPoint: .bottom)
            Sunburst()
                .fill(pal.accent.opacity(0.12))
                .frame(width: w, height: h * 0.9)
                .position(x: w / 2, y: h * 0.45)
                .clipped()
            ForEach([0.22, 0.24, 0.26], id: \.self) { f in
                Rectangle().fill(pal.accent).frame(width: w - 100, height: 2).position(x: w / 2, y: h * f)
            }
            Text(title)
                .font(Theme.Fonts.baskervilleBold(64))
                .foregroundStyle(pal.accent)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.4)
                .padding(.horizontal, 56)
                .frame(width: w, height: h * 0.3)
                .position(x: w / 2, y: h * 0.45)
            Text("A STEAM GAME")
                .font(Theme.Fonts.copperplate(20))
                .tracking(3)
                .foregroundStyle(pal.accent.opacity(0.7))
                .position(x: w / 2, y: h - 48)
        }
        .frame(width: w, height: h)
        .clipped()
    }
}

struct HeaderCompositeCoverView: View {
    let title: String
    let appID: Int
    let header: CGImage

    var body: some View {
        let pal = CoverPalette.forApp(appID)
        let w = Theme.Metrics.coverW, h = Theme.Metrics.coverH
        let imgW: CGFloat = 540
        let imgH = imgW * CGFloat(header.height) / CGFloat(max(header.width, 1))
        ZStack {
            LinearGradient(colors: [pal.top, pal.bottom], startPoint: .top, endPoint: .bottom)
            Image(decorative: header, scale: 1)
                .resizable()
                .frame(width: imgW, height: imgH)
                .padding(4)
                .background(Theme.Palette.cream)
                .shadow(color: .black.opacity(0.5), radius: 8, x: 3, y: 5)
                .position(x: w / 2, y: 40 + imgH / 2 + 4)
            Text(title)
                .font(Theme.Fonts.baskervilleBold(56))
                .foregroundStyle(pal.accent)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.4)
                .padding(.horizontal, 48)
                .frame(width: w, height: h - (imgH + 120) - 60)
                .position(x: w / 2, y: (imgH + 88) + (h - (imgH + 120) - 60) / 2 + 20)
            Text("A STEAM GAME")
                .font(Theme.Fonts.copperplate(20))
                .tracking(3)
                .foregroundStyle(pal.accent.opacity(0.7))
                .position(x: w / 2, y: h - 48)
        }
        .frame(width: w, height: h)
        .clipped()
    }
}

// MARK: - Texture library

@MainActor @Observable final class TextureLibrary {
    static let shared = TextureLibrary()
    private static let log = Logger(subsystem: "net.outofajam.SteamShelf", category: "Textures")

    var shelfWood: Image?
    var caseWood: Image?
    var backPanel: Image?
    var linen: Image?
    private var isPreparing = false

    private init() {}

    func prepare() async {
        guard shelfWood == nil, !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }
        #if DEBUG
        let start = ContinuousClock.now
        #endif
        let wood = Theme.Metrics.woodTextureSize
        let linenSize = Theme.Metrics.linenTextureSize
        let images = await Task.detached(priority: .userInitiated) { () -> [SendableImage] in
            [
                SendableImage(cgImage: ArtGenerator.woodTexture(size: wood, seed: 1, grain: .horizontal, palette: .plank)),
                SendableImage(cgImage: ArtGenerator.woodTexture(size: wood, seed: 2, grain: .vertical, palette: .caseWood)),
                SendableImage(cgImage: ArtGenerator.woodTexture(size: wood, seed: 3, grain: .vertical, palette: .back)),
                SendableImage(cgImage: ArtGenerator.linenTexture(size: linenSize, seed: 4)),
            ]
        }.value
        shelfWood = Image(decorative: images[0].cgImage, scale: 2)
        caseWood = Image(decorative: images[1].cgImage, scale: 2)
        backPanel = Image(decorative: images[2].cgImage, scale: 2)
        linen = Image(decorative: images[3].cgImage, scale: 2)
        #if DEBUG
        let elapsed = start.duration(to: .now)
        Self.log.debug("TextureLibrary.prepare completed in \(elapsed.formatted(), privacy: .public)")
        #endif
    }
}
