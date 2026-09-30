// Renders the Steam Shelf app icon procedurally: a walnut bookcase with glossy game boxes,
// 2007-era Apple gloss, inside the macOS squircle. Usage: swift scripts/make-icon.swift out.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func gradient(_ stops: [(UInt32, CGFloat)], alpha: [CGFloat]? = nil) -> CGGradient {
    let colors = stops.enumerated().map { rgb($0.element.0, alpha?[$0.offset] ?? 1) } as CFArray
    return CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors, locations: stops.map { $0.1 })!
}
struct Rand { var s: UInt64; mutating func next() -> CGFloat { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return CGFloat((z ^ (z >> 31)) % 10000) / 10000 } }

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setAllowsAntialiasing(true); ctx.setShouldAntialias(true)
// Flip to top-left origin for sanity.
ctx.translateBy(x: 0, y: size); ctx.scaleBy(x: 1, y: -1)

// macOS icon grid: the artwork sits in an 824-pt squircle centred in the 1024 canvas.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 824 * 0.2237, cornerHeight: 824 * 0.2237, transform: nil)

// Drop shadow of the tile.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.55))
ctx.addPath(tilePath); ctx.setFillColor(rgb(0x3B2415)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()

// Wood body: walnut gradient + grain.
ctx.drawLinearGradient(gradient([(0x6B4426, 0), (0x4E301A, 0.5), (0x33200F, 1)]), start: CGPoint(x: 0, y: tile.minY), end: CGPoint(x: 0, y: tile.maxY), options: [])
var r = Rand(s: 7)
ctx.setLineWidth(2)
for i in 0..<140 {
    let x = tile.minX + CGFloat(i) * tile.width / 140 + r.next() * 6
    let amp = 4 + r.next() * 10, ph = r.next() * 6.28, alpha = 0.06 + r.next() * 0.16
    let p = CGMutablePath(); p.move(to: CGPoint(x: x, y: tile.minY))
    var y = tile.minY
    while y < tile.maxY { y += 24; p.addLine(to: CGPoint(x: x + sin(y / 90 + ph) * amp, y: y)) }
    ctx.addPath(p); ctx.setStrokeColor(rgb(0x2A170C, alpha)); ctx.strokePath()
}

// Bay (interior) with two shelves.
let stile: CGFloat = 62, crown: CGFloat = 118, base: CGFloat = 96
let bay = CGRect(x: tile.minX + stile, y: tile.minY + crown, width: tile.width - 2 * stile, height: tile.height - crown - base)
ctx.saveGState()
ctx.addRect(bay); ctx.clip()
ctx.drawLinearGradient(gradient([(0x2E1B10, 0), (0x1C100A, 1)]), start: CGPoint(x: 0, y: bay.minY), end: CGPoint(x: 0, y: bay.maxY), options: [])
// inner shadows from frame
ctx.drawLinearGradient(gradient([(0x000000, 0), (0x000000, 1)], alpha: [0.55, 0]), start: CGPoint(x: 0, y: bay.minY), end: CGPoint(x: 0, y: bay.minY + 46), options: [])
ctx.drawLinearGradient(gradient([(0x000000, 0), (0x000000, 1)], alpha: [0.45, 0]), start: CGPoint(x: bay.minX, y: 0), end: CGPoint(x: bay.minX + 30, y: 0), options: [])
ctx.drawLinearGradient(gradient([(0x000000, 0), (0x000000, 1)], alpha: [0.45, 0]), start: CGPoint(x: bay.maxX, y: 0), end: CGPoint(x: bay.maxX - 30, y: 0), options: [])
ctx.restoreGState()

// Boxes: 2 rows x 3, 2:3 portrait, palette from the app's placeholder covers.
let palettes: [(UInt32, UInt32, UInt32)] = [(0x33658A, 0x1D3A50, 0xF6AE2D), (0x6B2E1F, 0x3A160E, 0xF3E9D2), (0x3D5A3A, 0x22341F, 0xE9D8A6),
                                            (0x4B3F72, 0x2A2342, 0xFFC857), (0x1F2041, 0x0F1022, 0xE26D5C), (0x7A4E2D, 0x3B2415, 0xF0D48A)]
let rowH = bay.height / 2, plankH: CGFloat = 22
let boxH = rowH - plankH - 34, boxW = boxH * 2 / 3
let gap = (bay.width - 3 * boxW) / 4
func drawBox(_ rect: CGRect, _ pal: (UInt32, UInt32, UInt32), seed: UInt64) {
    // drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 6, height: -10), blur: 14, color: rgb(0x000000, 0.6))
    ctx.setFillColor(rgb(pal.1)); ctx.fill(rect)
    ctx.restoreGState()
    // spine sliver (left)
    let spine = CGRect(x: rect.minX - 9, y: rect.minY + 3, width: 9, height: rect.height - 3)
    ctx.setFillColor(rgb(pal.1)); ctx.fill(spine)
    ctx.saveGState(); ctx.addRect(spine); ctx.clip()
    ctx.drawLinearGradient(gradient([(0xFFFFFF, 0), (0x000000, 1)], alpha: [0.15, 0.35]), start: CGPoint(x: spine.minX, y: 0), end: CGPoint(x: spine.maxX, y: 0), options: [])
    ctx.restoreGState()
    // cover
    ctx.saveGState(); ctx.addRect(rect); ctx.clip()
    ctx.drawLinearGradient(gradient([(pal.0, 0), (pal.1, 1)]), start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
    // sunburst
    let c = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.45)
    ctx.setFillColor(rgb(pal.2, 0.10))
    for k in 0..<12 {
        let a0 = CGFloat(k) * .pi / 6, a1 = a0 + .pi / 12
        let p = CGMutablePath(); p.move(to: c)
        p.addLine(to: CGPoint(x: c.x + cos(a0) * 900, y: c.y + sin(a0) * 900))
        p.addLine(to: CGPoint(x: c.x + cos(a1) * 900, y: c.y + sin(a1) * 900)); p.closeSubpath()
        ctx.addPath(p); ctx.fillPath()
    }
    // accent rules + title block
    ctx.setStrokeColor(rgb(pal.2, 0.9)); ctx.setLineWidth(2)
    for i in 0..<3 { let y = rect.minY + rect.height * (0.22 + CGFloat(i) * 0.02); ctx.move(to: CGPoint(x: rect.minX + 14, y: y)); ctx.addLine(to: CGPoint(x: rect.maxX - 14, y: y)); ctx.strokePath() }
    ctx.setFillColor(rgb(pal.2, 0.85))
    var rr = Rand(s: seed)
    for i in 0..<2 { let w = rect.width * (0.35 + rr.next() * 0.3); ctx.fill(CGRect(x: rect.midX - w / 2, y: rect.minY + rect.height * 0.44 + CGFloat(i) * 14, width: w, height: 7)) }
    // gloss (shrink-wrap)
    ctx.drawLinearGradient(gradient([(0xFFFFFF, 0), (0xFFFFFF, 0.45), (0xFFFFFF, 1)], alpha: [0.28, 0.02, 0.08]), start: CGPoint(x: rect.minX, y: rect.minY), end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
    ctx.restoreGState()
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.22)); ctx.setLineWidth(1.5); ctx.stroke(rect.insetBy(dx: 0.75, dy: 0.75))
}
for row in 0..<2 {
    let plankY = bay.minY + CGFloat(row + 1) * rowH - plankH
    for col in 0..<3 {
        let x = bay.minX + gap + CGFloat(col) * (boxW + gap)
        let rect = CGRect(x: x, y: plankY - boxH, width: boxW, height: boxH)
        // contact shadow
        ctx.saveGState(); ctx.setFillColor(rgb(0x000000, 0.5))
        ctx.setShadow(offset: .zero, blur: 6, color: rgb(0x000000, 0.6))
        ctx.fillEllipse(in: CGRect(x: rect.minX + rect.width * 0.05, y: plankY - 5, width: rect.width * 0.9, height: 9)); ctx.restoreGState()
        drawBox(rect, palettes[(row * 3 + col) % palettes.count], seed: UInt64(row * 3 + col + 11))
    }
    // plank
    let plank = CGRect(x: bay.minX, y: plankY, width: bay.width, height: plankH)
    ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 10, color: rgb(0x000000, 0.55))
    ctx.setFillColor(rgb(0x5C3A21)); ctx.fill(plank); ctx.restoreGState()
    ctx.saveGState(); ctx.addRect(plank); ctx.clip()
    ctx.drawLinearGradient(gradient([(0x8C5A32, 0), (0x5C3A21, 0.6), (0x3B2415, 1)]), start: CGPoint(x: 0, y: plank.minY), end: CGPoint(x: 0, y: plank.maxY), options: [])
    ctx.restoreGState()
    ctx.setFillColor(rgb(0xA87444, 0.8)); ctx.fill(CGRect(x: plank.minX, y: plank.minY, width: plank.width, height: 2))
}

// Frame edges: crown highlight, base plinth line.
ctx.setFillColor(rgb(0xA87444, 0.6)); ctx.fill(CGRect(x: tile.minX, y: bay.minY - 3, width: tile.width, height: 3))
ctx.setFillColor(rgb(0x000000, 0.45)); ctx.fill(CGRect(x: tile.minX, y: bay.maxY, width: tile.width, height: 3))
ctx.setFillColor(rgb(0xA87444, 0.35)); ctx.fill(CGRect(x: tile.minX, y: bay.maxY + 3, width: tile.width, height: 2))

// Brass nameplate in the crown.
let plate = CGRect(x: tile.midX - 190, y: tile.minY + 34, width: 380, height: 54)
let platePath = CGPath(roundedRect: plate, cornerWidth: 8, cornerHeight: 8, transform: nil)
ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 5, color: rgb(0x000000, 0.6))
ctx.addPath(platePath); ctx.setFillColor(rgb(0xB8893B)); ctx.fillPath(); ctx.restoreGState()
ctx.saveGState(); ctx.addPath(platePath); ctx.clip()
ctx.drawLinearGradient(gradient([(0xF0D48A, 0), (0xB8893B, 0.55), (0x8A6224, 1)]), start: CGPoint(x: 0, y: plate.minY), end: CGPoint(x: 0, y: plate.maxY), options: [])
ctx.restoreGState()
ctx.addPath(platePath); ctx.setStrokeColor(rgb(0x6E4E1C)); ctx.setLineWidth(2); ctx.strokePath()
for sx in [plate.minX + 22, plate.maxX - 22] {
    ctx.setFillColor(rgb(0x6E4E1C)); ctx.fillEllipse(in: CGRect(x: sx - 6, y: plate.midY - 6, width: 12, height: 12))
    ctx.setFillColor(rgb(0xF0D48A, 0.7)); ctx.fillEllipse(in: CGRect(x: sx - 4, y: plate.midY - 5, width: 8, height: 4))
}
// Engraved text on the plate.
ctx.saveGState()
ctx.translateBy(x: 0, y: size); ctx.scaleBy(x: 1, y: -1)   // back to CG coordinates for CoreText
let font = CTFontCreateWithName("Copperplate-Bold" as CFString, 30, nil)
func drawText(_ s: String, color: CGColor, dy: CGFloat) {
    let attr = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: NSColor(cgColor: color)!, .kern: 3])
    let line = CTLineCreateWithAttributedString(attr)
    let w = CTLineGetTypographicBounds(line, nil, nil, nil)
    ctx.textPosition = CGPoint(x: plate.midX - w / 2, y: size - plate.midY - 11 + dy)
    CTLineDraw(line, ctx)
}
drawText("STEAM SHELF", color: rgb(0xF0D48A, 0.55), dy: -1.5)
drawText("STEAM SHELF", color: rgb(0x3A2A10), dy: 0)
ctx.restoreGState()

// 2007 gloss over the whole tile: bright top half fading to nothing at the middle, with a curved edge.
let gloss = CGMutablePath()
gloss.move(to: CGPoint(x: tile.minX, y: tile.minY))
gloss.addLine(to: CGPoint(x: tile.maxX, y: tile.minY))
gloss.addLine(to: CGPoint(x: tile.maxX, y: tile.minY + tile.height * 0.42))
gloss.addQuadCurve(to: CGPoint(x: tile.minX, y: tile.minY + tile.height * 0.42), control: CGPoint(x: tile.midX, y: tile.minY + tile.height * 0.56))
gloss.closeSubpath()
ctx.saveGState(); ctx.addPath(gloss); ctx.clip()
ctx.drawLinearGradient(gradient([(0xFFFFFF, 0), (0xFFFFFF, 1)], alpha: [0.17, 0.03]), start: CGPoint(x: 0, y: tile.minY), end: CGPoint(x: 0, y: tile.minY + tile.height * 0.56), options: [])
ctx.restoreGState()
// Edge highlight + dark rim.
ctx.restoreGState()
ctx.addPath(tilePath); ctx.setStrokeColor(rgb(0x000000, 0.5)); ctx.setLineWidth(3); ctx.strokePath()
ctx.saveGState(); ctx.addPath(tilePath); ctx.clip()
ctx.addPath(CGPath(roundedRect: tile.insetBy(dx: 2.5, dy: 2.5), cornerWidth: 820 * 0.2237, cornerHeight: 820 * 0.2237, transform: nil))
ctx.setStrokeColor(rgb(0xFFFFFF, 0.18)); ctx.setLineWidth(2); ctx.strokePath()
ctx.restoreGState()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
