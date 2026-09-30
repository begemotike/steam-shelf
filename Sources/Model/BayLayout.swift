import CoreGraphics

/// Pure geometry of the bay (the flexible area inside the case frame): a 4x4 grid of 2:3 boxes,
/// each standing exactly on its plank. Everything is in the bay's own coordinate space.
struct BayLayout: Equatable, Sendable {
    static let rows = 4, columns = 4
    static let sidePadMin: CGFloat = 28, gapMin: CGFloat = 14
    /// Relative to boxH (design row: 22 headroom + 180 box + 20 plank).
    static let headroomRatio: CGFloat = 22.0 / 180.0, plankRatio: CGFloat = 20.0 / 180.0
    /// Preferred side padding (56 at boxH 180); the gap absorbs any width beyond it.
    static let sidePadRatio: CGFloat = 56.0 / 180.0
    /// The gap never exceeds this fraction of boxW; beyond that the row stays grouped and the side padding grows.
    static let gapMaxRatio: CGFloat = 0.75

    let baySize: CGSize
    let boxW, boxH, gap, sidePad, rowH, plankH, scale: CGFloat

    init(baySize: CGSize) {
        self.baySize = baySize
        let w = max(1, baySize.width), h = max(1, baySize.height)
        let rows = CGFloat(Self.rows), cols = CGFloat(Self.columns)
        rowH = h / rows
        let byHeight = rowH / (1 + Self.headroomRatio + Self.plankRatio)
        let byWidth = ((w - 2 * Self.sidePadMin - (cols - 1) * Self.gapMin) / cols) * 1.5
        boxH = max(1, min(byHeight, byWidth))
        boxW = boxH * 2 / 3
        let padTarget = max(Self.sidePadMin, boxH * Self.sidePadRatio)
        let natural = (w - 2 * padTarget - cols * boxW) / (cols - 1)
        gap = min(max(Self.gapMin, natural), max(Self.gapMin, boxW * Self.gapMaxRatio))
        sidePad = (w - cols * boxW - (cols - 1) * gap) / 2
        plankH = boxH * Self.plankRatio
        scale = boxH / Theme.Metrics.boxH
    }

    func boxFrame(row: Int, col: Int) -> CGRect {
        CGRect(x: sidePad + CGFloat(col) * (boxW + gap),
               y: CGFloat(row + 1) * rowH - plankH - boxH,
               width: boxW, height: boxH)
    }

    func plankFrame(row: Int) -> CGRect {
        CGRect(x: 0, y: CGFloat(row + 1) * rowH - plankH, width: max(1, baySize.width), height: plankH)
    }

    /// The slot whose box frame contains `point`, if any.
    func slot(containing point: CGPoint) -> (row: Int, col: Int)? {
        for row in 0..<Self.rows {
            for col in 0..<Self.columns where boxFrame(row: row, col: col).contains(point) { return (row, col) }
        }
        return nil
    }
}
