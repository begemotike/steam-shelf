import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Root

struct ShelfView: View {
    @Environment(AppModel.self) private var model
    @State private var textures = TextureLibrary.shared
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model
        ZStack {
            BackdropView()
            VStack(spacing: 0) {
                HeaderBar()
                GeometryReader { geo in
                    let pad = Theme.Metrics.bookcasePadding
                    let scale = max(0.1, min((geo.size.width - 2 * pad) / Theme.Metrics.bookcaseW,
                                             (geo.size.height - 2 * pad) / Theme.Metrics.bookcaseH))
                    BookcaseView()
                        .environment(\.shelfScale, scale)
                        .frame(width: Theme.Metrics.bookcaseW * scale, height: Theme.Metrics.bookcaseH * scale)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
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
        .task {
            guard model.mode != .tests else { return }
            focused = true
            await textures.prepare()
            await model.onLaunch()
        }
    }
}

// MARK: - Backdrop

private struct BackdropView: View {
    @State private var textures = TextureLibrary.shared

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TiledFill(image: textures.linen, fallback: Theme.Palette.backdrop)
                RadialGradient(
                    colors: [.clear, Theme.Palette.backdropEdge.opacity(0.85)],
                    center: .center, startRadius: 0,
                    endRadius: 0.75 * max(geo.size.width, geo.size.height))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Header

struct HeaderBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var textures = TextureLibrary.shared
    @State private var spin = 0.0

    private var isLoading: Bool { if case .loading = model.libraryState { true } else { false } }

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 80)
            Spacer(minLength: 8)
            ZStack {
                BrassPlate(cornerRadius: 6)
                EngravedText(text: model.document.title, font: Theme.Fonts.copperplateBold(16))
                    .lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 14)
            }
            .frame(width: 280, height: 34)
            .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2)
            Spacer(minLength: 8)
            Text("Page \(model.pageIndex + 1) of \(model.pagination.pageCount)")
                .font(Theme.Fonts.baskerville(13).smallCaps())
                .foregroundStyle(Theme.Palette.cream)
                .monospacedDigit()
            HStack(spacing: 8) {
                roundButton("arrow.clockwise", help: "Refresh Library (⌘R)") {
                    Task { await model.refreshLibrary() }
                }
                .rotationEffect(.degrees(spin))
                .disabled(isLoading)
                roundButton("gearshape.fill", help: "Settings (⌘,)") { openSettings() }
            }
            .padding(.leading, 14)
            .padding(.trailing, 16)
        }
        .frame(height: Theme.Metrics.headerHeight)
        .background {
            ZStack(alignment: .bottom) {
                TiledFill(image: textures.caseWood, fallback: Theme.Palette.walnutDark)
                VStack(spacing: 0) {
                    Theme.Palette.walnutHighlight.opacity(0.4).frame(height: 1)
                    Color.black.opacity(0.5).frame(height: 2)
                }
            }
            .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 3)
        }
        .zIndex(1)
        .onChange(of: isLoading) { _, loading in
            if loading {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { spin = 360 }
            } else {
                withAnimation(.default) { spin = 0 }
            }
        }
    }

    private func roundButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Theme.brassGradient)
                    .overlay(Circle().strokeBorder(Theme.Palette.brassDark, lineWidth: 1))
                    .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1).padding(1).mask(
                        LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center)))
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.brassInk)
                    .shadow(color: .white.opacity(0.4), radius: 0, x: 0, y: 1)
            }
            .frame(width: 30, height: 30)
            .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .pointerStyle(.link)
        .help(help)
    }
}

// MARK: - Bookcase

struct BookcaseView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.shelfScale) private var s

    var body: some View {
        let M = Theme.Metrics.self
        HStack(spacing: 0) {
            handleColumn(.left)
            CaseView()
                .frame(width: M.caseW * s, height: M.caseH * s)
            handleColumn(.right)
        }
        .frame(width: 932 * s, height: M.caseH * s)
    }

    private func handleColumn(_ side: HandleSide) -> some View {
        let M = Theme.Metrics.self
        let page = model.pageIndex
        let label = side == .left ? model.pagination.leftHandleLabel(currentPage: page)
                                  : model.pagination.rightHandleLabel(currentPage: page)
        return HandleView(side: side, label: label) { model.handleTapped(side) }
            .frame(width: M.handleColumnW * s, height: M.caseH * s,
                   alignment: side == .left ? .trailing : .leading)
            .padding(side == .left ? .trailing : .leading, M.handleOffset * s)
            .frame(width: M.handleColumnW * s, height: M.caseH * s, alignment: side == .left ? .trailing : .leading)
    }
}

/// The case frame: crown, stiles, base and the bay (back panel, shadows, planks, page).
struct CaseView: View {
    @Environment(\.shelfScale) private var s
    @State private var textures = TextureLibrary.shared

    var body: some View {
        let M = Theme.Metrics.self
        ZStack(alignment: .topLeading) {
            TiledFill(image: textures.caseWood, fallback: Theme.Palette.walnutDark)

            // Stile shading (lit from the left).
            HStack(spacing: 0) {
                stile
                Spacer(minLength: 0)
                stile
            }
            .frame(height: 4 * M.rowH * s)
            .offset(y: M.crownH * s)

            BayView()
                .frame(width: M.bayW * s, height: 4 * M.rowH * s)
                .offset(x: M.stileW * s, y: M.crownH * s)

            crown
            base
        }
        .frame(width: M.caseW * s, height: M.caseH * s)
        .clipped()
        .shadow(color: .black.opacity(0.6), radius: 24 * s, x: 6 * s, y: 10 * s)
    }

    private var stile: some View {
        LinearGradient(colors: [.white.opacity(0.07), .clear, .black.opacity(0.22)],
                       startPoint: .leading, endPoint: .trailing)
            .frame(width: Theme.Metrics.stileW * s)
    }

    private var crown: some View {
        let M = Theme.Metrics.self
        return ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Theme.Palette.walnutHighlight.opacity(0.3), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 8 * s)
            Color.black.opacity(0.55).frame(height: 2 * s).offset(y: (M.crownH - 12 - 2) * s)
            Color.white.opacity(0.06).frame(height: 1 * s).offset(y: (M.crownH - 12) * s)
            Theme.Palette.walnutHighlight.opacity(0.8).frame(height: 1 * s)
        }
        .frame(width: M.caseW * s, height: M.crownH * s, alignment: .topLeading)
        .background(alignment: .bottom) { Color.black.opacity(0.0) }
    }

    private var base: some View {
        let M = Theme.Metrics.self
        return ZStack(alignment: .bottom) {
            LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 10 * s).frame(maxHeight: .infinity, alignment: .top)
            Color.black.opacity(0.2).frame(height: M.plinthH * s)
            Color.black.opacity(0.35).frame(height: 1 * s).frame(maxHeight: .infinity, alignment: .bottom).offset(y: -M.plinthH * s)
        }
        .frame(width: M.caseW * s, height: M.baseH * s)
        .offset(y: (M.caseH - M.baseH) * s)
    }
}

/// Bay interior: back panel, shadows, planks and the current page.
struct BayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.shelfScale) private var s
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textures = TextureLibrary.shared

    var body: some View {
        let M = Theme.Metrics.self
        ZStack(alignment: .topLeading) {
            TiledFill(image: textures.backPanel, fallback: Theme.Palette.backPanel)
            // Darken toward the bottom of each bay.
            LinearGradient(colors: [.clear, Theme.Palette.backPanelDark.opacity(0.35)], startPoint: .top, endPoint: .bottom)

            // Shadows cast by the plank/crown above each row.
            ForEach(0..<4, id: \.self) { r in
                LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(width: M.bayW * s, height: 26 * s)
                    .offset(y: CGFloat(r) * M.rowH * s)
            }
            // Side shadows from the stiles.
            HStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 14 * s)
                Spacer(minLength: 0)
                LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .trailing, endPoint: .leading)
                    .frame(width: 14 * s)
            }

            // Planks (frame layer: they do not slide with the page).
            ForEach(0..<4, id: \.self) { r in
                PlankView()
                    .frame(width: M.bayW * s, height: M.plankFaceH * s)
                    .offset(y: (CGFloat(r) * M.rowH + M.rowHeadroom + M.boxH) * s)
            }

            PageContainerView()
                .frame(width: M.bayW * s, height: 4 * M.rowH * s)
                .clipped()

            if model.document.shelvedEntries.isEmpty {
                EmptyShelfCard()
                    .frame(width: M.bayW * s, height: 4 * M.rowH * s)
            }
        }
        .frame(width: M.bayW * s, height: 4 * M.rowH * s)
        .clipped()
    }
}

struct PlankView: View {
    @Environment(\.shelfScale) private var s
    @State private var textures = TextureLibrary.shared

    var body: some View {
        ZStack {
            TiledFill(image: textures.shelfWood, fallback: Theme.Palette.walnut)
            LinearGradient(colors: [Theme.Palette.walnutLight, Theme.Palette.walnutDark], startPoint: .top, endPoint: .bottom)
                .opacity(0.4)
                .blendMode(.multiply)
            VStack(spacing: 0) {
                Theme.Palette.walnutHighlight.opacity(0.8).frame(height: 1 * s)
                Spacer(minLength: 0)
                Color.black.opacity(0.4).frame(height: 2 * s)
            }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.45), radius: 6 * s, x: 0, y: 4 * s)
    }
}

// MARK: - Page

struct PageContainerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let edge: Edge = model.slideDirection == .forward ? .trailing : .leading
        ZStack {
            ShelfPageView(pageIndex: model.pageIndex)
                .id(model.pageIndex)
                .transition(reduceMotion ? .opacity : .push(from: edge))
        }
    }
}

/// 4x4 grid of boxes for one page, plus their contact shadows (the planks live in the frame layer).
struct ShelfPageView: View {
    let pageIndex: Int
    @Environment(AppModel.self) private var model
    @Environment(\.shelfScale) private var s

    var body: some View {
        let M = Theme.Metrics.self
        let entries = model.document.shelvedEntries
        let range = model.pagination.range(ofPage: pageIndex)
        let pageEntries = range.upperBound <= entries.count ? Array(entries[range]) : []
        ZStack(alignment: .topLeading) {
            ForEach(Array(pageEntries.enumerated()), id: \.element.appID) { index, entry in
                let row = index / Pagination.columns, col = index % Pagination.columns
                let x = (56 + CGFloat(col) * (M.boxW + M.boxGap)) * s
                let y = (CGFloat(row) * M.rowH + M.rowHeadroom) * s
                Ellipse()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: M.boxW * 0.9 * s, height: 8 * s)
                    .blur(radius: 4 * s)
                    .offset(x: x + M.boxW * 0.05 * s, y: y + (M.boxH + 2 - 4) * s)
                BoxTile(entry: entry)
                    .frame(width: M.boxW * s, height: M.boxH * s)
                    .offset(x: x, y: y)
            }
        }
        .frame(width: M.bayW * s, height: 4 * M.rowH * s, alignment: .topLeading)
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
    @State private var frameBox = FrameBox()

    private var isOpened: Bool { model.openedAppID == entry.appID }

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
    @Environment(\.shelfScale) private var s

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
        .scaleEffect(s)
        .accessibilityElement(children: .contain)
    }

    private var body_: String {
        if let count = ownedCount {
            return "You own \(count) games. Tick a few in Settings to put them on display."
        }
        return "Add your Steam Web API key and SteamID in Settings, then tick the games worth displaying."
    }
}
