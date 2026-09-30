import SwiftUI

// MARK: - Stars

/// Non-interactive star row (used on the printed label).
struct StarRow: View {
    let rating: Int?
    var size: CGFloat = 30
    var spacing: CGFloat = 6

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(1...5, id: \.self) { i in
                let filled = i <= (rating ?? 0)
                ZStack {
                    Image(systemName: "star.fill")
                        .foregroundStyle(filled ? Theme.Palette.starGold : Theme.Palette.starEmpty)
                    if filled {
                        Image(systemName: "star")
                            .foregroundStyle(Theme.Palette.brassDark)
                    }
                }
                .font(.system(size: size))
            }
        }
    }
}

/// Interactive star control for the editor: click to set, click the same star again to clear, hover previews.
struct StarRatingControl: View {
    @Binding var rating: Int?
    var size: CGFloat = 26
    @State private var hover: Int?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { i in
                let shown = hover ?? rating ?? 0
                Image(systemName: "star.fill")
                    .font(.system(size: size))
                    .foregroundStyle(i <= shown ? Theme.Palette.starGold : Theme.Palette.starEmpty)
                    .onHover { hover = $0 ? i : nil }
                    .onTapGesture { rating = (rating == i) ? nil : i }
                    .pointerStyle(.link)
                    .accessibilityLabel("\(i) star\(i == 1 ? "" : "s")")
                    .accessibilityAddTraits(.isButton)
            }
        }
    }
}

// MARK: - Back of box

/// The printed back of the box: a pasted-on vintage paper label. Pure display; rendered to a texture.
struct BackOfBoxView: View {
    let entry: ShelfEntry
    let ownerName: String
    let spineColor: Color

    private var stats: CachedSteamStats { entry.stats }

    var body: some View {
        ZStack {
            spineColor
            Theme.gloss
            label
                .frame(width: 544, height: 844)
        }
        .frame(width: Theme.Metrics.coverW, height: Theme.Metrics.coverH)
        .clipped()
    }

    private var label: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Theme.Palette.cream)
            if let linen = TextureLibrary.shared.linen {
                linen.resizable(resizingMode: .tile).opacity(0.06).blendMode(.multiply)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.black.opacity(0.18), lineWidth: 3)
                .blur(radius: 1.5)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            // Double rule
            RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.Palette.labelRed, lineWidth: 2).padding(12)
            RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.Palette.labelRed, lineWidth: 0.75).padding(17.5)

            VStack(spacing: 0) {
                titleBlock
                Spacer(minLength: 6)
                ratingRow
                Spacer(minLength: 6)
                statsGrid
                Spacer(minLength: 6)
                achievements
                Spacer(minLength: 6)
                blurbBox
                Spacer(minLength: 8)
                noteCard
                Spacer(minLength: 8)
                footer
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 32)
        }
    }

    // MARK: Sections

    private var titleBlock: some View {
        VStack(spacing: 4) {
            Text(entry.title)
                .font(Theme.Fonts.baskervilleBold(40))
                .foregroundStyle(Theme.Palette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
            if let tagline = entry.blurb?.tagline {
                Text(tagline)
                    .font(Theme.Fonts.baskervilleItalic(18))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            HStack(spacing: 8) {
                Theme.Palette.labelRed.frame(height: 1)
                Text("❦").font(Theme.Fonts.baskerville(18)).foregroundStyle(Theme.Palette.labelRed)
                Theme.Palette.labelRed.frame(height: 1)
            }
            .padding(.horizontal, 24)
        }
    }

    private var ratingRow: some View {
        VStack(spacing: 4) {
            Text("YOUR VERDICT")
                .font(Theme.Fonts.copperplate(14)).tracking(2)
                .foregroundStyle(Theme.Palette.inkSoft)
            StarRow(rating: entry.rating)
            if entry.rating == nil {
                Text("Not yet rated").font(Theme.Fonts.baskervilleItalic(14)).foregroundStyle(Theme.Palette.inkSoft)
            }
        }
    }

    private var hoursText: String {
        let hours = Double(stats.playtimeMinutes) / 60
        return hours < 10 ? String(format: "%.1f", hours) : String(Int(hours.rounded()))
    }

    private static func date(_ d: Date) -> String {
        d.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private var statsGrid: some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                cell("PURCHASED", value: entry.purchaseDate.map(Self.date) ?? "—",
                     note: entry.purchaseDate == nil ? "(add it in Edit Label)" : nil)
                cell("HOURS PLAYED", value: "\(hoursText) hrs", valueColor: Theme.Palette.labelRed)
            }
            GridRow {
                cell("LAST PLAYED", value: stats.lastPlayed.map(Self.date) ?? "Never")
                cell("ON SHELF SINCE", value: Self.date(entry.firstSeenAt))
            }
        }
    }

    private func cell(_ caption: String, value: String, note: String? = nil, valueColor: Color = Theme.Palette.ink) -> some View {
        VStack(spacing: 1) {
            Text(caption).font(Theme.Fonts.copperplate(13)).tracking(1).foregroundStyle(Theme.Palette.inkSoft)
            Text(value).font(Theme.Fonts.baskervilleSemiBold(24)).foregroundStyle(valueColor)
                .lineLimit(1).minimumScaleFactor(0.7)
            if let note {
                Text(note).font(Theme.Fonts.baskervilleItalic(11)).foregroundStyle(Theme.Palette.inkSoft)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var achievements: some View {
        VStack(spacing: 4) {
            switch stats.achievementsState {
            case .ok:
                let earned = stats.achievementsEarned ?? 0, total = max(1, stats.achievementsTotal ?? 1)
                HStack {
                    Text("ACHIEVEMENTS").font(Theme.Fonts.copperplate(13)).tracking(1).foregroundStyle(Theme.Palette.inkSoft)
                    Spacer()
                    Text("\(earned) / \(total)").font(Theme.Fonts.baskervilleSemiBold(15)).foregroundStyle(Theme.Palette.ink)
                }
                .frame(width: 480)
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.creamShade)
                        .overlay(Capsule().strokeBorder(Color.black.opacity(0.2), lineWidth: 1.5).blur(radius: 1).clipShape(Capsule()))
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.Palette.achieveGreen.mix(with: .white, by: 0.25), Theme.Palette.achieveGreen],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: max(16, 480 * CGFloat(earned) / CGFloat(total)))
                }
                .frame(width: 480, height: 16)
            case .none:
                note("This game keeps no trophies.")
            case .privateProfile:
                note("Achievements are private on Steam.")
            case .unknown:
                note("Checking the trophy case…")
            }
        }
        .frame(height: 46)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(Theme.Fonts.baskervilleItalic(15)).foregroundStyle(Theme.Palette.inkSoft)
    }

    private var blurbBox: some View {
        VStack(spacing: 3) {
            Text("FROM THE SHELF-KEEPER").font(Theme.Fonts.copperplate(13)).tracking(1.5).foregroundStyle(Theme.Palette.labelRed)
            Text(entry.blurb?.blurb ?? "The shelf-keeper is thinking it over…")
                .font(Theme.Fonts.baskerville(18))
                .foregroundStyle(Theme.Palette.ink)
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .lineLimit(5)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
    }

    private var noteCard: some View {
        ZStack(alignment: .topLeading) {
            LinedPaper(spacing: 26, marginX: 38, firstLine: 30)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .shadow(color: .black.opacity(0.3), radius: 3, x: 1, y: 2)
            Group {
                if entry.note.isEmpty {
                    Text("Scribble a note in Edit Label…")
                        .font(Theme.Fonts.noteworthy(20)).foregroundStyle(Theme.Palette.inkSoft.opacity(0.6))
                } else {
                    Text(entry.note)
                        .font(Theme.Fonts.noteworthy(20)).foregroundStyle(Theme.Palette.ink)
                        .lineLimit(6).truncationMode(.tail)
                }
            }
            .lineSpacing(0)
            .padding(.leading, 48).padding(.trailing, 14).padding(.top, 16)
            .frame(width: 460, height: 170, alignment: .topLeading)
            Thumbtack().frame(width: 460).offset(y: 6)
        }
        .frame(width: 460, height: 170)
        .rotationEffect(.degrees(-1.2))
    }

    private var footer: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Barcode(seed: UInt64(bitPattern: Int64(entry.appID)))
                    .frame(width: 140, height: 36)
                Text("APP #" + String(entry.appID)).font(Theme.Fonts.copperplate(12)).foregroundStyle(Theme.Palette.ink)
            }
            Spacer()
            Text("A STEAM SHELF EXHIBIT · \(ownerName.uppercased())")
                .font(Theme.Fonts.copperplate(11))
                .foregroundStyle(Theme.Palette.inkSoft)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .frame(width: 200, alignment: .trailing)
        }
    }
}

private struct Barcode: View {
    let seed: UInt64

    var body: some View {
        var rng = SplitMix64(seed: seed)
        let widths = (0..<40).map { _ in CGFloat(rng.int(in: 1...4)) }
        return HStack(spacing: 0) {
            ForEach(Array(widths.enumerated()), id: \.offset) { index, w in
                Rectangle()
                    .fill(index % 2 == 0 ? Theme.Palette.ink : Color.clear)
                    .frame(width: w * 0.9)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }
}

// MARK: - Spine

/// Side texture (200 x 1200): spine color, rotated title reading top-to-bottom, small brand badge.
struct SpineView: View {
    let title: String
    let color: Color

    var body: some View {
        let length: CGFloat = 900
        ZStack {
            color
            LinearGradient(colors: [.white.opacity(0.10), .clear, .black.opacity(0.20)], startPoint: .leading, endPoint: .trailing)
            Text(title)
                .font(Theme.Fonts.baskervilleBold(64))
                .foregroundStyle(Theme.Palette.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(width: length, height: 200)
                .rotationEffect(.degrees(90))
                .frame(width: 200, height: length)
                .position(x: 100, y: 60 + length / 2)
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Theme.Palette.cream)
                Text("STEAM SHELF")
                    .font(Theme.Fonts.copperplate(22)).tracking(1)
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .frame(width: 104, height: 40)
                    .rotationEffect(.degrees(90))
            }
            .frame(width: 64, height: 120)
            .position(x: 100, y: 1200 - 60 - 60)
            Rectangle().strokeBorder(Color.black.opacity(0.25), lineWidth: 2)
        }
        .frame(width: Theme.Metrics.spineW, height: Theme.Metrics.spineH)
        .clipped()
    }
}

// MARK: - Label editor (2D, interactive)

/// Clipboard-style editing panel: rating, purchase date, note. Every change goes through `AppModel.update`.
struct LabelEditorPanel: View {
    let appID: Int
    @Environment(AppModel.self) private var model

    private var entry: ShelfEntry? { model.document.entries.first { $0.appID == appID } }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 10).fill(Theme.Palette.cream)
                .shadow(color: .black.opacity(0.6), radius: 16, x: 0, y: 8)
            if let linen = TextureLibrary.shared.linen {
                linen.resizable(resizingMode: .tile).opacity(0.05).blendMode(.multiply)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            if let entry {
                VStack(alignment: .leading, spacing: 18) {
                    Text(entry.title)
                        .font(Theme.Fonts.baskervilleBold(20))
                        .foregroundStyle(Theme.Palette.ink)
                        .lineLimit(2)
                    field("Your Verdict") {
                        StarRatingControl(rating: Binding(
                            get: { entry.rating },
                            set: { new in model.update(appID) { $0.rating = new } }))
                    }
                    field("Purchased") { purchaseField(entry) }
                    field("Note") { noteField(entry) }
                    HStack {
                        Button("Refresh from Steam") { Task { await model.refreshStats(for: appID, force: true) } }
                            .controlSize(.small)
                            .disabled(model.isDemo || model.mode != .normal)
                        Text(updatedText(entry))
                            .font(.caption).foregroundStyle(Theme.Palette.inkSoft)
                    }
                    Spacer(minLength: 0)
                    HStack {
                        Spacer()
                        Button("Done") { withAnimation(Theme.Motion.panel) { model.isEditingLabel = false } }
                            .buttonStyle(BrassPillButtonStyle())
                    }
                }
                .padding(24)
                .padding(.top, 10)
            }
            // Brass clip
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
        .environment(\.colorScheme, .light)
    }

    private func field<Content: View>(_ caption: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption).font(Theme.Fonts.baskervilleSemiBold(13)).foregroundStyle(Theme.Palette.inkSoft)
            content()
        }
    }

    private func purchaseField(_ entry: ShelfEntry) -> some View {
        HStack {
            if let date = entry.purchaseDate {
                DatePicker("", selection: Binding(get: { date }, set: { new in model.update(appID) { $0.purchaseDate = new } }),
                           displayedComponents: .date)
                    .datePickerStyle(.field).labelsHidden()
                Button("Clear") { model.update(appID) { $0.purchaseDate = nil } }.controlSize(.small)
            } else {
                Button("Set date") { model.update(appID) { $0.purchaseDate = Date() } }.controlSize(.small)
            }
        }
    }

    private func noteField(_ entry: ShelfEntry) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            TextEditor(text: Binding(
                get: { entry.note },
                set: { new in model.update(appID) { $0.note = String(new.prefix(600)) } }))
                .font(Theme.Fonts.noteworthy(16))
                .foregroundStyle(Theme.Palette.ink)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 160)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.Palette.creamShade.opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.Palette.creamShade, lineWidth: 1))
            Text("\(entry.note.count) / 600").font(.caption2).foregroundStyle(Theme.Palette.inkSoft).monospacedDigit()
        }
    }

    private func updatedText(_ entry: ShelfEntry) -> String {
        guard let fetched = entry.stats.fetchedAt else { return "Not refreshed yet" }
        return "Updated " + fetched.formatted(.relative(presentation: .named))
    }
}
