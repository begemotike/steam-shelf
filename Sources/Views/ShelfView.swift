import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CoreTransferable

/// Drag payload for reordering boxes on the shelf (private to this app).
struct DraggedBox: Codable, Transferable {
    let appID: Int
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .steamShelfBox)
    }
}

extension UTType {
    static let steamShelfBox = UTType(exportedAs: "net.outofajam.steamshelf.box")
}

// MARK: - Root

struct ShelfView: View {
    @Environment(AppModel.self) private var model
    @State private var textures = TextureLibrary.shared
    @State private var swipes = SwipeMonitor()
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model
        ZStack {
            CaseFrameView()
            OpenBoxView()
        }
        .coordinateSpace(.named("shelfSpace"))
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onChange(of: model.openedAppID) { _, id in if id == nil { focused = true } }
        .onKeyPress(keys: [.leftArrow, .rightArrow, .home, .end]) { press in
            guard model.openedAppID == nil, press.modifiers.isEmpty else { return .ignored }
            switch press.key {
            case .leftArrow: model.go(to: model.pageIndex - 1)
            case .rightArrow: model.go(to: model.pageIndex + 1)
            case .home: model.go(to: 0, animation: Theme.Motion.pageJump)
            default: model.go(to: model.pagination.pageCount - 1, animation: Theme.Motion.pageJump)
            }
            return .handled
        }
        .frame(minWidth: Theme.Metrics.windowMinW, minHeight: Theme.Metrics.windowMinH)
        .ignoresSafeArea()
        .fileExporter(isPresented: $model.isExporting, document: model.exportFile ?? ShelfFile(data: Data()),
                      contentType: .steamShelf, defaultFilename: model.document.title) { result in
            if case .failure = result { model.fileAlert = "Couldn't write the shelf file." }
            model.exportFile = nil
        }
        .fileImporter(isPresented: $model.isImporting, allowedContentTypes: [.steamShelf, .json]) { result in
            switch result {
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) { model.stageImport(data) }
                else { model.fileAlert = "Couldn't read that file." }
            case .failure:
                model.fileAlert = "Couldn't read that file."
            }
        }
        .alert("Replace this shelf?", isPresented: Binding(get: { model.pendingImport != nil },
                                                           set: { if !$0 { model.pendingImport = nil } })) {
            Button("Replace", role: .destructive) { model.confirmImport() }
            Button("Cancel", role: .cancel) { model.pendingImport = nil }
        } message: {
            Text("Importing replaces the shelf you have now with the one in the file.")
        }
        .alert("Steam Shelf", isPresented: Binding(get: { model.fileAlert != nil },
                                                   set: { if !$0 { model.fileAlert = nil } }),
               presenting: model.fileAlert) { _ in
            Button("OK", role: .cancel) {}
        } message: { text in
            Text(text)
        }
        .onAppear {
            guard model.mode != .tests else { return }
            let model = model
            swipes.start(in: { NSApp.windows.first { $0.title == "Steam Shelf" } ?? NSApp.keyWindow },
                         enabled: { model.openedAppID == nil },
                         handler: { step in model.go(to: model.pageIndex + step) })
        }
        .onDisappear { swipes.stop() }
        .task {
            guard model.mode != .tests else { return }
            focused = true
            await textures.prepare()
            await model.onLaunch()
        }
    }
}

// MARK: - Case frame

/// The window *is* the bookcase: crown rail, two stiles, base rail and the flexible bay (DESIGN / PHASE_C).
struct CaseFrameView: View {
    @State private var textures = TextureLibrary.shared

    var body: some View {
        let M = Theme.Metrics.self
        VStack(spacing: 0) {
            CrownRail()
            HStack(spacing: 0) {
                StileView(side: .left)
                BayView()
                StileView(side: .right)
            }
            BaseRail()
        }
        // One continuous wood texture behind every frame member, so there are no seams.
        .background(TiledFill(image: textures.caseWood, fallback: Theme.Palette.walnutDark))
        .clipped()
        .frame(minWidth: M.stileW * 2 + 100)
    }
}

struct CrownRail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var spin = 0.0

    private var isLoading: Bool { if case .loading = model.libraryState { true } else { false } }

    var body: some View {
        let M = Theme.Metrics.self
        ZStack {
            // Edges of the rail.
            VStack(spacing: 0) {
                Theme.Palette.walnutHighlight.opacity(0.8).frame(height: 1)
                Spacer(minLength: 0)
                Color.black.opacity(0.55).frame(height: 2)
                Color.white.opacity(0.06).frame(height: 1)
            }
            nameplate
            HStack(spacing: 0) {
                Color.clear.frame(width: M.trafficLightClearance)
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    pagePlate
                    knob("arrow.clockwise", help: "Refresh Library (⌘R)") { Task { await model.refreshLibrary() } }
                        .rotationEffect(.degrees(spin))
                        .disabled(isLoading)
                        .padding(2)
                    knob(model.lightsOn ? "lightbulb.fill" : "lightbulb", help: model.lightsOn ? "Shelf lights off (⌘L)" : "Shelf lights on (⌘L)") { model.toggleLights() }
                    knob("gearshape.fill", help: "Settings (⌘,)") { openSettings() }
                }
                .padding(.trailing, 16)
            }
            .padding(.top, 1)
        }
        .frame(height: M.crownH)
        .onChange(of: isLoading) { _, loading in
            if loading {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { spin = 360 }
            } else {
                withAnimation(.default) { spin = 0 }
            }
        }
    }

    /// Inlaid brass nameplate: no drop shadow, a dark rim top/left, a light rim bottom/right, two screws.
    private var nameplate: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return ZStack {
            BrassPlate(cornerRadius: 6)
            EngravedText(text: model.document.title, font: Theme.Fonts.copperplateBold(16))
                .lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 24)
            HStack { screw; Spacer(minLength: 0); screw }.padding(.horizontal, 8)
        }
        .frame(width: 280, height: 34)
        .overlay(shape.inset(by: -0.5).stroke(.black.opacity(0.45), lineWidth: 1)
            .mask(LinearGradient(colors: [.white, .clear], startPoint: .topLeading, endPoint: .center)))
        .overlay(shape.inset(by: -0.5).stroke(.white.opacity(0.15), lineWidth: 1)
            .mask(LinearGradient(colors: [.clear, .white], startPoint: .center, endPoint: .bottomTrailing)))
    }

    private var screw: some View {
        Circle()
            .fill(RadialGradient(colors: [Theme.Palette.brassLight, Theme.Palette.brass, Theme.Palette.brassDark],
                                 center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 6))
            .overlay(Circle().stroke(Theme.Palette.brassDark, lineWidth: 0.5))
            .overlay(Rectangle().fill(Theme.Palette.brassInk.opacity(0.8)).frame(width: 4, height: 0.8).rotationEffect(.degrees(35)))
            .frame(width: 6, height: 6)
    }

    private var pagePlate: some View {
        ZStack {
            BrassPlate(cornerRadius: 4)
            EngravedText(text: "PAGE \(model.pageIndex + 1) OF \(model.pagination.pageCount)",
                         font: Theme.Fonts.copperplate(11).smallCaps().monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(width: 92, height: 26)
    }

    private func knob(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                // Dark recess the knob is set into.
                Circle().fill(.black.opacity(0.35)).frame(width: 34, height: 34)
                    .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1)
                        .mask(LinearGradient(colors: [.clear, .white], startPoint: .center, endPoint: .bottom)))
                Circle().fill(Theme.brassGradient)
                    .overlay(Circle().strokeBorder(Theme.Palette.brassDark, lineWidth: 1))
                    .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1).padding(1).mask(
                        LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center)))
                    .frame(width: 30, height: 30)
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.brassInk)
                    .shadow(color: .white.opacity(0.4), radius: 0, x: 0, y: 1)
            }
            .frame(width: 34, height: 34)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .pointerStyle(.link)
        .help(help)
    }
}

struct BaseRail: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Color.black.opacity(0.35).frame(height: 1)
                LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 10)
                Spacer(minLength: 0)
                Color.black.opacity(0.2).frame(height: Theme.Metrics.plinthH)
            }
            HStack {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    statusText(now: context.date)
                        .font(Theme.Fonts.baskerville(12))
                        .monospacedDigit()
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                EngravedText(text: "STEAM SHELF", font: Theme.Fonts.copperplate(11),
                             color: Theme.Palette.brass.opacity(0.7), highlight: .white.opacity(0.08))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, Theme.Metrics.plinthH)
            .frame(maxHeight: .infinity)
        }
        .frame(height: Theme.Metrics.baseH)
    }

    private func statusText(now: Date) -> Text {
        let cream = Theme.Palette.cream.opacity(0.85)
        if let transient = model.transientStatus {
            return Text(transient.uppercased()).foregroundStyle(Theme.Palette.brassLight)
        }
        switch model.libraryState {
        case .loading(let message):
            return Text(message.uppercased()).foregroundStyle(cream)
        case .failed(let message):
            return Text("⚠ " + message.uppercased()).foregroundStyle(Theme.Palette.brassLight)
        case .idle:
            let shelved = model.document.shelvedEntries.count
            if model.isDemo {
                let total = model.library?.games.count ?? model.document.entries.count
                return Text("DEMO SHELF · \(shelved) OF \(total) TITLES SHELVED").foregroundStyle(cream)
            }
            if let library = model.library {
                return Text("UPDATED \(Self.relative(library.fetchedAt, now: now)) · \(shelved) OF \(library.games.count) TITLES SHELVED")
                    .foregroundStyle(cream)
            }
            return Text("NOT CONNECTED — OPEN SETTINGS (⌘,)").foregroundStyle(cream)
        }
    }

    private static func relative(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 60 { return "JUST NOW" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: now).uppercased()
    }
}

struct StileView: View {
    let side: HandleSide
    @Environment(AppModel.self) private var model

    var body: some View {
        let M = Theme.Metrics.self
        let page = model.pageIndex
        let label = side == .left ? model.pagination.leftHandleLabel(currentPage: page)
                                  : model.pagination.rightHandleLabel(currentPage: page)
        ZStack {
            // Lit from the left.
            LinearGradient(colors: [.white.opacity(0.07), .clear, .black.opacity(0.22)],
                           startPoint: .leading, endPoint: .trailing)
            // Mortise the handle is set into.
            let mortise = RoundedRectangle(cornerRadius: 8, style: .continuous)
            mortise.fill(.black.opacity(0.4))
                .overlay(mortise.stroke(.black.opacity(0.6), lineWidth: 2)
                    .mask(LinearGradient(colors: [.white, .clear], startPoint: .topLeading, endPoint: .bottomTrailing)))
                .clipShape(mortise)
                .frame(width: M.mortiseW, height: M.mortiseH)
            HandleView(side: side, label: label) { model.handleTapped(side) }
                .dropDestination(for: DraggedBox.self) { _, _ in false } isTargeted: { model.dragHover(over: side, active: $0) }
        }
        .frame(width: M.stileW)
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Bay

/// Bay interior: back panel, shadows, planks and the current page, positioned from a `BayLayout`.
struct BayView: View {
    var body: some View {
        GeometryReader { geo in
            let layout = BayLayout(baySize: geo.size)
            BayContent(layout: layout)
                .environment(\.shelfScale, layout.scale)
        }
    }
}

private struct BayContent: View {
    let layout: BayLayout
    @Environment(AppModel.self) private var model
    @State private var textures = TextureLibrary.shared

    var body: some View {
        let size = layout.baySize
        ZStack(alignment: .topLeading) {
            TiledFill(image: textures.backPanel, fallback: Theme.Palette.backPanel)
            // Darken toward the bottom of each bay.
            LinearGradient(colors: [.clear, Theme.Palette.backPanelDark.opacity(0.35)], startPoint: .top, endPoint: .bottom)

            // Shadows cast by the plank/crown above each row (softened when the lights are on).
            ForEach(0..<BayLayout.rows, id: \.self) { r in
                LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(width: size.width, height: 26 * layout.scale)
                    .offset(y: CGFloat(r) * layout.rowH)
                    .opacity(model.lightsOn ? 0.25 : 1)
            }
            // Shelf lights: an LED strip under the crown and under each plank, washing the back panel.
            ForEach(0..<BayLayout.rows, id: \.self) { r in
                LightStrip(width: size.width, rowHeight: layout.rowH)
                    .offset(y: CGFloat(r) * layout.rowH)
            }
            .opacity(model.lightsOn ? 1 : 0)
            // Side shadows from the stiles.
            HStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 14)
                Spacer(minLength: 0)
                LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .trailing, endPoint: .leading)
                    .frame(width: 14)
            }

            PageContainerView(layout: layout)
                .frame(width: size.width, height: size.height)
                .clipped()

            // Planks (frame layer: they do not slide with the page) drawn in front of the boxes,
            // so each box's base disappears behind the shelf edge and reads as standing on it.
            ForEach(0..<BayLayout.rows, id: \.self) { r in
                let f = layout.plankFrame(row: r)
                PlankView()
                    .frame(width: f.width, height: f.height)
                    .offset(x: f.minX, y: f.minY)
                    .allowsHitTesting(false)
            }

            if model.document.shelvedEntries.isEmpty {
                EmptyShelfCard()
                    .frame(width: size.width, height: size.height)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

/// One LED strip: a bright core line at the underside of the plank above, a tight halo, and a warm
/// wash that falls down the back panel and fades out by about 60% of the row.
struct LightStrip: View {
    let width: CGFloat
    let rowHeight: CGFloat
    @Environment(\.shelfScale) private var s

    var body: some View {
        ZStack(alignment: .top) {
            // Wash on the back panel: hot right under the plank, long soft falloff.
            LinearGradient(stops: [
                .init(color: Theme.Palette.lampWash.opacity(0.68), location: 0),
                .init(color: Theme.Palette.lampWash.opacity(0.38), location: 0.08),
                .init(color: Theme.Palette.lampWash.opacity(0.15), location: 0.24),
                .init(color: Theme.Palette.lampWash.opacity(0.03), location: 0.50),
                .init(color: .clear, location: 0.72),
            ], startPoint: .top, endPoint: .bottom)
            .frame(width: width, height: rowHeight * 0.9)
            .blendMode(.screen)
            // Halo right under the strip.
            LinearGradient(stops: [
                .init(color: Theme.Palette.lampGlow.opacity(0.55), location: 0),
                .init(color: Theme.Palette.lampGlow.opacity(0.18), location: 0.45),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .frame(width: width, height: 26 * s)
            .blendMode(.plusLighter)
            // The strip itself, tucked under the plank's lip so mostly its glow shows.
            Theme.Palette.lampCore.opacity(0.55)
                .frame(width: max(0, width - 28 * s), height: 1.5 * s)
                .shadow(color: Theme.Palette.lampCore.opacity(0.7), radius: 2.5 * s)
                .shadow(color: Theme.Palette.lampGlow.opacity(0.6), radius: 7 * s, y: 2 * s)
        }
        // Real strips pool toward the middle and fall off before the stiles.
        .mask(
            LinearGradient(stops: [
                .init(color: .white.opacity(0.35), location: 0),
                .init(color: .white, location: 0.18),
                .init(color: .white, location: 0.82),
                .init(color: .white.opacity(0.35), location: 1),
            ], startPoint: .leading, endPoint: .trailing)
        )
        .frame(width: width, height: rowHeight, alignment: .top)
        .allowsHitTesting(false)
    }
}

struct PlankView: View {
    @Environment(\.shelfScale) private var s
    @Environment(AppModel.self) private var model
    @State private var textures = TextureLibrary.shared

    var body: some View {
        ZStack {
            TiledFill(image: textures.shelfWood, fallback: Theme.Palette.walnut)
            LinearGradient(colors: [Theme.Palette.walnutLight, Theme.Palette.walnutDark], startPoint: .top, endPoint: .bottom)
                .opacity(0.4)
                .blendMode(.multiply)
            // Light from the strip above spilling onto the plank's top surface and front edge.
            LinearGradient(colors: [Theme.Palette.lampGlow.opacity(0.45), Theme.Palette.lampGlow.opacity(0.08)], startPoint: .top, endPoint: .bottom)
                .blendMode(.screen)
                .opacity(model.lightsOn ? 1 : 0)
            VStack(spacing: 0) {
                // Top surface: lighter, catching the room light (and the strip above when lit).
                ZStack(alignment: .top) {
                    LinearGradient(colors: [Theme.Palette.walnutHighlight.opacity(model.lightsOn ? 0.75 : 0.55),
                                            Theme.Palette.walnutHighlight.opacity(0.25)],
                                   startPoint: .top, endPoint: .bottom)
                    Color.white.opacity(0.35).frame(height: 1)
                }
                .frame(height: 7 * s)
                // Front edge line where the surface turns down into the face.
                Color.black.opacity(0.35).frame(height: max(1, 1 * s))
                Spacer(minLength: 0)
                Color.black.opacity(0.4).frame(height: 2)
            }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(model.lightsOn ? 0.6 : 0.45), radius: 6 * s, x: 0, y: 4 * s)
    }
}

// MARK: - Page

struct PageContainerView: View {
    let layout: BayLayout
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let edge: Edge = model.slideDirection == .forward ? .trailing : .leading
        ZStack {
            ShelfPageView(pageIndex: model.pageIndex, layout: layout)
                .id(model.pageIndex)
                .transition(reduceMotion ? .opacity : .push(from: edge))
        }
    }
}

/// 4x4 grid of boxes for one page, plus their contact shadows (the planks live in the frame layer).
struct ShelfPageView: View {
    let pageIndex: Int
    let layout: BayLayout
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = layout.scale
        let entries = model.document.shelvedEntries
        let range = model.pagination.range(ofPage: pageIndex)
        let pageEntries = range.upperBound <= entries.count ? Array(entries[range]) : []
        ZStack(alignment: .topLeading) {
            ForEach(Array(pageEntries.enumerated()), id: \.element.appID) { index, entry in
                let f = layout.boxFrame(row: index / Pagination.columns, col: index % Pagination.columns)
                Ellipse()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: f.width * 1.04, height: 8 * s)
                    .blur(radius: 3 * s)
                    .offset(x: f.minX - f.width * 0.02, y: f.maxY - layout.boxRestInset - 4 * s)
                BoxTile(entry: entry)
                    .frame(width: f.width, height: f.height)
                    .offset(x: f.minX, y: f.minY)
            }
        }
        .frame(width: layout.baySize.width, height: layout.baySize.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .dropDestination(for: DraggedBox.self) { items, _ in
            guard let dragged = items.first else { return false }
            model.moveEntry(dragged.appID, before: nil)
            return true
        }
        // Window resizes must never animate tile positions (page push uses its own transition).
        .animation(nil, value: layout)
    }
}

// MARK: - Cover loading

struct ReadyCover {
    let image: CGImage
    let spine: Color
}

@MainActor @Observable final class CoverLoader {
    enum State { case loading, ready(CGImage, spine: Color) }

    private(set) var state: State = .loading

    /// Recently resolved covers, shared with the open-box overlay so it can start instantly.
    static var recent: [Int: ReadyCover] = [:]
    private static let recentCap = 48

    var readyImage: CGImage? { if case .ready(let image, _) = state { image } else { nil } }
    var spine: Color? { if case .ready(_, let spine) = state { spine } else { nil } }

    func load(entry: ShelfEntry, model: AppModel) async {
        if let hit = Self.recent[entry.appID] { state = .ready(hit.image, spine: hit.spine); return }
        await Task.yield()
        if Task.isCancelled { return }
        let resolved = await Self.resolve(entry: entry, model: model)
        if Task.isCancelled { return }
        Self.remember(resolved, appID: entry.appID)
        state = .ready(resolved.image, spine: resolved.spine)
    }

    static func resolve(entry: ShelfEntry, model: AppModel) async -> ReadyCover {
        let palette = CoverPalette.forApp(entry.appID)
        let hasArt = !entry.art.portraitURLs.isEmpty || entry.art.headerURL != nil
        if hasArt && !model.isDemo {
            let request = CoverRequest(appID: entry.appID, title: entry.title,
                                       portraitURLs: entry.art.portraitURLs, headerURL: entry.art.headerURL)
            switch await model.images.cover(for: request) {
            case .portrait(let img):
                return ReadyCover(image: img.cgImage, spine: ArtGenerator.spineColor(from: ArtGenerator.averageColor(of: img.cgImage)))
            case .header(let img):
                return ReadyCover(image: ArtGenerator.headerCover(title: entry.title, appID: entry.appID, header: img.cgImage), spine: palette.bottom)
            case .none:
                break
            }
        }
        return ReadyCover(image: ArtGenerator.placeholderCover(title: entry.title, appID: entry.appID), spine: palette.bottom)
    }

    static func remember(_ cover: ReadyCover, appID: Int) {
        if recent.count >= recentCap, let victim = recent.keys.first(where: { $0 != appID }) { recent[victim] = nil }
        recent[appID] = cover
    }
}

// MARK: - Box tile

/// Holds a frame without triggering view updates; read only at click time.
@MainActor private final class FrameBox { var frame: CGRect = .zero }

private struct TilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct SpineSliverShape: Shape {
    func path(in r: CGRect) -> Path {
        let rise = r.width * 0.375
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + rise))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - rise))
        p.closeSubpath()
        return p
    }
}

private struct TopSliverShape: Shape {
    let skew: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - skew, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + skew, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct BoxTile: View {
    let entry: ShelfEntry
    @Environment(AppModel.self) private var model
    @Environment(\.shelfScale) private var s
    @State private var loader = CoverLoader()
    @State private var hovering = false
    @State private var dropTargeted = false
    @State private var frameBox = FrameBox()

    private var isOpened: Bool { model.openedAppID == entry.appID }

    private var dragPreview: some View {
        Group {
            if let image = loader.readyImage {
                Image(decorative: image, scale: 2).resizable().aspectRatio(2.0 / 3.0, contentMode: .fit)
            } else {
                placeholder
            }
        }
        .frame(width: Theme.Metrics.boxW * s, height: Theme.Metrics.boxH * s)
        .clipShape(RoundedRectangle(cornerRadius: 2 * s))
    }

    var body: some View {
        let M = Theme.Metrics.self
        Button {
            model.open(entry.appID, from: frameBox.frame)
        } label: {
            ZStack {
                boxBody
                    .opacity(isOpened ? 0 : 1)
                if isOpened {
                    RoundedRectangle(cornerRadius: 2 * s)
                        .fill(Color.black.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 2 * s).stroke(Color.black.opacity(0.25), lineWidth: max(1, s)))
                }
            }
            .frame(width: M.boxW * s, height: M.boxH * s)
            .contentShape(Rectangle())
        }
        .buttonStyle(TilePressStyle())
        .pointerStyle(.link)
        .onHover { hovering = $0 }
        .draggable(DraggedBox(appID: entry.appID)) { dragPreview }
        .dropDestination(for: DraggedBox.self) { items, _ in
            guard let dragged = items.first else { return false }
            model.moveEntry(dragged.appID, before: entry.appID)
            return true
        } isTargeted: { dropTargeted = $0 }
        .overlay(alignment: .leading) {
            // Insertion mark: a brass line just left of the box while a drag hovers over it.
            if dropTargeted {
                RoundedRectangle(cornerRadius: 1.5 * s)
                    .fill(Theme.Palette.brassLight)
                    .frame(width: 3 * s, height: (M.boxH + 12) * s)
                    .shadow(color: Theme.Palette.brassLight.opacity(0.8), radius: 4 * s)
                    .offset(x: -(M.spineSliverW + 14) * s)
                    .allowsHitTesting(false)
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("shelfSpace")) } action: { frame in
            frameBox.frame = frame
            if model.openedAppID == entry.appID { model.openedFromFrame = frame }
        }
        .accessibilityLabel(entry.title)
        .accessibilityAddTraits(.isButton)
        .task(id: entry.appID) { await loader.load(entry: entry, model: model) }
    }

    private var boxBody: some View {
        let M = Theme.Metrics.self
        let lifted = hovering && !isOpened
        let spine = loader.spine ?? Theme.Palette.creamShade
        return ZStack(alignment: .topLeading) {
            // Top edge sliver (subtle) and spine sliver, drawn behind the cover.
            TopSliverShape(skew: 8 * s)
                .fill(spine.mix(with: .black, by: 0.15))
                .frame(width: (M.boxW + 8) * s, height: M.topSliverH * s)
                .offset(y: -M.topSliverH * s)
            SpineSliverShape()
                .fill(spine)
                .overlay(SpineSliverShape().fill(LinearGradient(colors: [.white.opacity(0.12), .black.opacity(0.25)], startPoint: .leading, endPoint: .trailing)))
                .frame(width: M.spineSliverW * s, height: (M.boxH + 3) * s)
                .offset(x: -M.spineSliverW * s, y: -3 * s)

            cover
                .frame(width: M.boxW * s, height: M.boxH * s)
                .clipShape(RoundedRectangle(cornerRadius: 2 * s))
                .overlay(gloss)
                .overlay(litOverlay)
                .overlay(
                    RoundedRectangle(cornerRadius: 2 * s)
                        .stroke(Theme.Palette.hoverGlow, lineWidth: 1.5 * s)
                        .opacity(lifted ? 1 : 0)
                )
        }
        .frame(width: M.boxW * s, height: M.boxH * s, alignment: .topLeading)
        .shadow(color: .black.opacity(0.55), radius: (lifted ? 12 : 8) * s, x: 3 * s, y: (lifted ? 9 : 6) * s)
        .scaleEffect(lifted ? 1.03 : 1)
        .offset(y: lifted ? -3 * s : 0)
        .animation(Theme.Motion.hover, value: lifted)
    }

    /// Shelf lights on: warm light lands on the top of the cover and fades down; a bright top edge.
    private var litOverlay: some View {
        ZStack(alignment: .top) {
            LinearGradient(stops: [
                .init(color: Theme.Palette.lampGlow.opacity(0.24), location: 0),
                .init(color: Theme.Palette.lampGlow.opacity(0.07), location: 0.3),
                .init(color: .clear, location: 0.55),
            ], startPoint: .top, endPoint: .bottom)
            .blendMode(.screen)
            Theme.Palette.lampCore.opacity(0.75).frame(height: max(1, 1.5 * s))
        }
        .clipShape(RoundedRectangle(cornerRadius: 2 * s))
        .opacity(model.lightsOn ? 1 : 0)
        .allowsHitTesting(false)
    }

    private var cover: some View {
        ZStack {
            placeholder
            if let image = loader.readyImage {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .aspectRatio(2.0 / 3.0, contentMode: .fill)
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.artFade, value: loader.readyImage != nil)
    }

    private var placeholder: some View {
        ZStack {
            Theme.Palette.creamShade
            Text(entry.title)
                .font(Theme.Fonts.baskerville(13 * s))
                .foregroundStyle(Theme.Palette.inkSoft)
                .multilineTextAlignment(.center)
                .padding(8 * s)
        }
    }

    private var gloss: some View {
        ZStack(alignment: .topLeading) {
            Theme.gloss
            Color.white.opacity(0.18).frame(height: max(1, s)).frame(maxHeight: .infinity, alignment: .top)
            Color.white.opacity(0.18).frame(width: max(1, s)).frame(maxWidth: .infinity, alignment: .leading)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Empty state

struct EmptyShelfCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    private var ownedCount: Int? {
        if let count = model.library?.games.count, count > 0 { count } else { nil }
    }

    var body: some View {
        ZStack {
            LinedPaper(spacing: 26, marginX: 44)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .shadow(color: .black.opacity(0.55), radius: 10, x: 0, y: 6)
            VStack(spacing: 10) {
                Text("This shelf is bare.")
                    .font(Theme.Fonts.baskervilleBold(26))
                    .foregroundStyle(Theme.Palette.ink)
                Text(body_)
                    .font(Theme.Fonts.noteworthy(17))
                    .foregroundStyle(Theme.Palette.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 30)
                HStack(spacing: 10) {
                    Button("Open Settings") { openSettings() }
                        .buttonStyle(BrassPillButtonStyle())
                    if ownedCount == nil {
                        Button("Try the Demo Shelf") { model.startDemo() }
                            .buttonStyle(BrassPillButtonStyle())
                    }
                }
                .padding(.top, 6)
            }
            .padding(.top, 14)
            Thumbtack().offset(y: -(260 / 2) + 14)
        }
        .frame(width: 420, height: 260)
        .rotationEffect(.degrees(-2))
        .accessibilityElement(children: .contain)
    }

    private var body_: String {
        if let count = ownedCount {
            return "You own \(count) games. Tick a few in Settings to put them on display."
        }
        return "Add your Steam Web API key and SteamID in Settings, then tick the games worth displaying."
    }
}
