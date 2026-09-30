import SwiftUI

/// Interim Phase A shelf: a plain 4-column grid of covers + Prev/Next. Replaced in B1–B3.
struct ShelfView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.document.shelvedEntries.isEmpty {
                emptyState
            } else {
                grid
                pager
            }
        }
        .frame(minWidth: Theme.Metrics.windowMinW, minHeight: Theme.Metrics.windowMinH)
        .background(Theme.Palette.backdrop)
        .task {
            guard model.mode != .tests else { return }
            await TextureLibrary.shared.prepare()
            await model.onLaunch()
        }
    }

    private var header: some View {
        HStack {
            Text(model.document.title)
                .font(Theme.Fonts.copperplateBold(16))
                .foregroundStyle(Theme.Palette.brassLight)
            Spacer()
            Button { openSettings() } label: { Image(systemName: "gearshape.fill") }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Palette.brassLight)
                .help("Settings")
        }
        .padding(.leading, 80)
        .padding(.trailing, 16)
        .frame(height: Theme.Metrics.headerHeight)
        .background(Theme.Palette.walnutDark)
    }

    private var grid: some View {
        let entries = model.document.shelvedEntries
        let range = model.pagination.range(ofPage: model.pageIndex)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: Pagination.columns)
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(entries[range]) { entry in
                    InterimCover(entry: entry)
                        .aspectRatio(2.0 / 3.0, contentMode: .fit)
                }
            }
            .padding(24)
        }
    }

    private var pager: some View {
        HStack(spacing: 16) {
            Button("Previous") { model.go(to: model.pageIndex - 1) }
                .disabled(model.pageIndex <= 0)
            Text("Page \(model.pageIndex + 1) of \(model.pagination.pageCount)")
                .font(Theme.Fonts.baskerville(13))
                .foregroundStyle(Theme.Palette.cream)
            Button("Next") { model.go(to: model.pageIndex + 1) }
                .disabled(model.pageIndex >= model.pagination.pageCount - 1)
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("This shelf is bare.")
                .font(Theme.Fonts.baskervilleBold(26))
            Text(emptyBody)
                .font(Theme.Fonts.noteworthy(17))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack {
                Button("Open Settings") { openSettings() }
                if model.library == nil {
                    Button("Try the Demo Shelf") { model.startDemo() }
                }
            }
            Spacer()
        }
        .foregroundStyle(Theme.Palette.cream)
        .frame(maxWidth: .infinity)
    }

    private var emptyBody: String {
        if let count = model.library?.games.count, count > 0 {
            return "You own \(count) games. Tick a few in Settings to put them on display."
        }
        return "Add your Steam Web API key and SteamID in Settings, then tick the games worth displaying."
    }
}

/// Interim cover: real art when cached/available, otherwise a generated placeholder.
private struct InterimCover: View {
    let entry: ShelfEntry
    @Environment(AppModel.self) private var model
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 2).resizable().aspectRatio(2.0 / 3.0, contentMode: .fill)
            } else {
                Theme.Palette.creamShade
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .shadow(color: .black.opacity(0.55), radius: 6, x: 3, y: 4)
        .accessibilityLabel(entry.title)
        .task(id: entry.appID) { image = await load() }
    }

    private func load() async -> CGImage {
        let hasArt = !entry.art.portraitURLs.isEmpty || entry.art.headerURL != nil
        if hasArt && !model.isDemo {
            let request = CoverRequest(appID: entry.appID, title: entry.title,
                                       portraitURLs: entry.art.portraitURLs, headerURL: entry.art.headerURL)
            switch await model.images.cover(for: request) {
            case .portrait(let img): return img.cgImage
            case .header(let img): return ArtGenerator.headerCover(title: entry.title, appID: entry.appID, header: img.cgImage)
            case .none: break
            }
        }
        return ArtGenerator.placeholderCover(title: entry.title, appID: entry.appID)
    }
}
