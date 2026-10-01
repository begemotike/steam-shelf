import SwiftUI

/// The Shelf-Keeper's notes: same slot and style as `LabelEditorPanel` (cream parchment, brass clip, trailing edge).
/// Which body shows depends on the model state (docs/PERSONALIZER.md §7).
struct KeeperNotesPanel: View {
    let appID: Int
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var confirmClear = false

    private var entry: ShelfEntry? { model.document.entries.first { $0.appID == appID } }
    private var stored: BackOfBoxContent? { entry?.blurb.flatMap { $0.isAIWritten && $0.detail != nil ? $0 : nil } }
    private var state: AppModel.KeeperState { model.keeperState(for: appID) }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 10).fill(Theme.Palette.cream)
                .shadow(color: .black.opacity(0.6), radius: 16, x: 0, y: 8)
            if let linen = TextureLibrary.shared.linen {
                linen.resizable(resizingMode: .tile).opacity(0.05).blendMode(.multiply)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            if let entry {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("The Shelf-Keeper's Notes")
                            .font(Theme.Fonts.baskervilleBold(20)).foregroundStyle(Theme.Palette.ink)
                        Text(entry.title)
                            .font(Theme.Fonts.baskervilleItalic(14)).foregroundStyle(Theme.Palette.inkSoft).lineLimit(2)
                    }
                    content
                    footer
                }
                .padding(24)
                .padding(.top, 10)
            }
            clip
        }
        .environment(\.colorScheme, .light)
        .confirmationDialog("Clear these notes?", isPresented: $confirmClear) {
            Button("Clear Notes", role: .destructive) { model.clearNotes(for: appID) }
        } message: {
            Text("The back of the box goes back to the usual blurb.")
        }
    }

    // MARK: Body by state

    @ViewBuilder private var content: some View {
        switch state {
        case .reading: working("Reading your saves…")
        case .writing: working("Composing…")
        case .failed(let message): failure(message)
        case .idle:
            if let stored { notes(stored) }
            else if !model.canWriteNotes { message("Notes can only be written on your own shelf.") }
            else if !model.hasSaveAccess {
                message("Steam Shelf needs to be shown your Steam folder before it can read your save files.")
                Button("Grant Access…") { model.requestSaveAccess() }.buttonStyle(BrassPillButtonStyle())
                Spacer(minLength: 0)
            } else if !model.aiReady {
                message("Choose an AI service in Settings so the Shelf-Keeper can write.")
                Button("Open Settings") { openSettings() }.buttonStyle(BrassPillButtonStyle())
                Spacer(minLength: 0)
            } else {
                message("The Shelf-Keeper has not looked at this one yet.")
                Button("Write Notes") { Task { await model.writeNotes(for: appID) } }.buttonStyle(BrassPillButtonStyle())
                Spacer(minLength: 0)
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text).font(Theme.Fonts.baskerville(15)).foregroundStyle(Theme.Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func working(_ text: String) -> some View {
        VStack {
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(text).font(Theme.Fonts.baskervilleItalic(15)).foregroundStyle(Theme.Palette.inkSoft)
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
    }

    private func failure(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text).font(Theme.Fonts.baskerville(15)).foregroundStyle(Theme.Palette.labelRed)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Try Again") { Task { await model.writeNotes(for: appID) } }.buttonStyle(BrassPillButtonStyle())
                if stored != nil {
                    Button("Keep Old Notes") { model.keeperState[appID] = .idle }.buttonStyle(BrassPillButtonStyle())
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func notes(_ c: BackOfBoxContent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let tagline = c.tagline {
                    Text(tagline).font(Theme.Fonts.baskervilleItalic(17)).foregroundStyle(Theme.Palette.inkSoft)
                }
                ForEach(Array((c.observations ?? []).enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("❦").font(.system(size: 14)).foregroundStyle(Theme.Palette.labelRed)
                        Text(line).font(Theme.Fonts.baskerville(15)).foregroundStyle(Theme.Palette.ink).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Rectangle().fill(Theme.Palette.creamShade).frame(height: 1).padding(.vertical, 4)
                Text("ON YOUR MOST RECENT SESSION")
                    .font(Theme.Fonts.copperplate(12)).tracking(1.2).foregroundStyle(Theme.Palette.labelRed)
                if let detail = c.detail {
                    Text(detail).font(Theme.Fonts.baskerville(15)).foregroundStyle(Theme.Palette.ink).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .padding(.trailing, 6)
        }
    }

    @ViewBuilder private var footer: some View {
        if case .idle = state, let stored {
            VStack(alignment: .leading, spacing: 8) {
                Text(footerText(stored)).font(.caption).foregroundStyle(Theme.Palette.inkSoft)
                HStack {
                    if model.canWriteNotes {
                        Button("Rewrite") { Task { await model.writeNotes(for: appID) } }.buttonStyle(BrassPillButtonStyle())
                        Button("Clear") { confirmClear = true }.buttonStyle(BrassPillButtonStyle())
                    }
                    Spacer()
                    Button("Done") { withAnimation(Theme.Motion.panel) { model.isShowingNotes = false } }
                        .buttonStyle(BrassPillButtonStyle())
                }
            }
        } else {
            HStack {
                Spacer()
                Button("Done") { withAnimation(Theme.Motion.panel) { model.isShowingNotes = false } }
                    .buttonStyle(BrassPillButtonStyle())
            }
        }
    }

    private func footerText(_ c: BackOfBoxContent) -> String {
        var text = "Written " + c.generatedAt.formatted(date: .abbreviated, time: .omitted)
        if let n = c.savesRead { text += " · \(n) save\(n == 1 ? "" : "s") read" }
        return text
    }

    private var clip: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(Theme.brassGradient)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.Palette.brassDark, lineWidth: 1))
            HStack(spacing: 30) {
                Circle().fill(Theme.Palette.brassDark).frame(width: 5, height: 5)
                Circle().fill(Theme.Palette.brassDark).frame(width: 5, height: 5)
            }
        }
        .frame(width: 60, height: 22)
        .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 2)
        .offset(y: -8)
    }
}
