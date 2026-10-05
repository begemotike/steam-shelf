import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            LibrarySettingsTab()
                .tabItem { Label("Library", systemImage: "books.vertical") }
            ShelfKeeperSettingsTab()
                .tabItem { Label("Shelf-Keeper", systemImage: "text.book.closed") }
        }
        .frame(width: 640, height: 760)
        .tint(Theme.Palette.brass)
        .task { if model.mode != .tests { await TextureLibrary.shared.prepare() } }
    }
}

private struct LibrarySettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            SettingsHeader()
            if model.isDemo { DemoBanner() }
            AccountSection()
            Divider()
            LibraryChecklist()
        }
    }
}

private struct ShelfKeeperSettingsTab: View {
    @Environment(AppModel.self) private var model
    @State private var keyDraft = ""

    private var canSaveKey: Bool { !keyDraft.trimmingCharacters(in: .whitespaces).isEmpty && model.mode == .normal }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            SettingsHeader()
            Form {
                Section("Save file access") {
                    LabeledContent("Steam folder") {
                        if model.hasSaveAccess {
                            HStack {
                                Text("Granted ✓").foregroundStyle(.secondary)
                                Button("Revoke") { model.revokeSaveAccess() }
                            }
                        } else {
                            Button("Grant Access…") { model.requestSaveAccess() }
                                .disabled(model.mode != .normal)
                        }
                    }
                    Text("Saves live inside the Steam folder, which macOS keeps private until you choose it.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Picker("Saves were played in", selection: $model.saveTimeZoneID) {
                        Text("This Mac's time zone (\(TimeZone.current.identifier))").tag(String?.none)
                        Divider()
                        ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag(String?.some($0)) }
                    }
                    .disabled(model.mode != .normal)
                    Text("Save files don't record a time zone. If you play at home and travel with this Mac, pick your home zone so late-night saves stay late.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section("AI service") {
                    Picker("Service", selection: Binding(get: { model.aiConfig.providerID }, set: { model.selectAIProvider($0) })) {
                        ForEach(AIProviders.all) { Text($0.name).tag($0.id) }
                    }
                    .disabled(model.mode != .normal)
                    if model.aiConfig.preset.editableBaseURL {
                        LabeledContent("Address") {
                            TextField("", text: $model.aiConfig.baseURL, prompt: Text("https://example.com/v1"))
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.leading)
                                .onSubmit { Task { await model.loadModels() } }
                        }
                        if model.aiConfig.base == nil, !model.aiConfig.baseURL.isEmpty {
                            Text("Use an https address (plain http works only for this Mac).")
                                .font(.footnote).foregroundStyle(Theme.Palette.labelRed)
                        }
                    }
                    if model.hasAIKey {
                        LabeledContent("API Key") {
                            HStack {
                                Text("••••  Saved in Keychain").foregroundStyle(.secondary)
                                Button("Forget") { model.forgetAIKey() }
                            }
                        }
                    } else {
                        LabeledContent(model.aiConfig.preset.needsKey ? "API Key" : "API Key (optional)") {
                            HStack {
                                SecureField("", text: $keyDraft, prompt: Text("Paste a key from any service"))
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.leading)
                                    .frame(minWidth: 260)
                                    .onSubmit { saveKey() }
                                Button("Save") { saveKey() }
                                    .disabled(!canSaveKey)
                            }
                        }
                    }
                    LabeledContent("Model") {
                        HStack {
                            TextField("", text: $model.aiConfig.model, prompt: Text("model name"))
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.leading)
                            Menu("Choose…") {
                                ForEach(model.availableModels, id: \.self) { id in
                                    Button(id) { model.aiConfig.model = id }
                                }
                            }
                            .fixedSize()
                            .disabled(model.availableModels.isEmpty)
                            Button {
                                Task { await model.loadModels() }
                            } label: { Image(systemName: "arrow.clockwise") }
                            .help("Ask the service for its model list")
                            .disabled(model.mode != .normal || (model.aiConfig.preset.needsKey && !model.hasAIKey))
                        }
                    }
                    switch model.modelsState {
                    case .loading(let text): Text(text).font(.footnote).foregroundStyle(.secondary)
                    case .failed(let text): Text(text).font(.footnote).foregroundStyle(Theme.Palette.labelRed)
                    case .idle:
                        if !model.availableModels.isEmpty {
                            Text("\(model.availableModels.count) models available from \(model.aiConfig.preset.name).")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if let keyURL = model.aiConfig.preset.keyURL, let url = URL(string: keyURL) {
                        Link("Get a key for \(model.aiConfig.preset.name)", destination: url).font(.footnote)
                    }
                    Text("Paste a key and the service is recognised from it where possible. When you ask for notes on a game, a summary of that game's save files (save names, dates, party, quests and recent conversations) is sent to the service you chose, using your key. Nothing is sent until you press Write Notes.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section("Games with notes") {
                    ForEach(Personalizers.all.map(\.displayName), id: \.self) { Text($0) }
                }
            }
            .formStyle(.grouped)
        }
    }

    private func saveKey() {
        guard canSaveKey else { return }
        model.saveAIKey(keyDraft)
        keyDraft = ""
    }
}

private struct SettingsHeader: View {
    var body: some View {
        let textures = TextureLibrary.shared
        ZStack {
            if let wood = textures.caseWood {
                wood.resizable(resizingMode: .tile)
            } else {
                Theme.Palette.walnutDark
            }
            Text("Steam Shelf Settings")
                .font(Theme.Fonts.copperplateBold(16))
                .foregroundStyle(Theme.Palette.brassInk)
                .padding(.horizontal, 28).padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(LinearGradient(colors: [Theme.Palette.brassLight, Theme.Palette.brass, Theme.Palette.brassDark],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.Palette.brassDark, lineWidth: 1))
                )
                .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
        }
        .frame(height: 64)
        .clipped()
    }
}

private struct DemoBanner: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack {
            Text("Demo shelf — 40 imaginary games. Connect a Steam account to use your own.")
                .font(Theme.Fonts.baskerville(13))
                .foregroundStyle(Theme.Palette.ink)
            Spacer()
            Button("Leave Demo") { model.leaveDemo() }
                .disabled(model.mode == .tests)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Theme.Palette.cream)
    }
}

struct AccountSection: View {
    @Environment(AppModel.self) private var model
    @State private var keyDraft = ""

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Steam Account") {
                if model.hasAPIKey {
                    LabeledContent("Web API Key") {
                        HStack {
                            Text("••••••••  Saved in Keychain").foregroundStyle(.secondary)
                            Button("Forget") { model.forgetAPIKey() }
                        }
                    }
                } else {
                    LabeledContent("Web API Key") {
                        HStack {
                            SecureField("", text: $keyDraft, prompt: Text("32-character key"))
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.leading)
                                .frame(minWidth: 260)
                                .onSubmit { saveKey() }
                            Button("Save") { saveKey() }
                                .disabled(!canSaveKey)
                        }
                    }
                }
                Link("Get a key at steamcommunity.com/dev/apikey", destination: URL(string: "https://steamcommunity.com/dev/apikey")!)
                    .font(.footnote)
                TextField("SteamID or profile URL", text: $model.steamIDInput,
                          prompt: Text("76561198… or https://steamcommunity.com/id/yourname"))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .onSubmit { if canConnect { Task { await model.connect() } } }
                HStack {
                    Button("Connect") { Task { await model.connect() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canConnect)
                }
                if model.isDemo {
                    Text("Leave the demo shelf (above) to connect your own account.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if !model.hasAPIKey {
                    Text("Save your key first, then enter your profile and press Connect.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    StatusRow()
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(height: 250)
    }

    private var isBusy: Bool {
        if case .loading = model.libraryState { return true }
        return false
    }

    private var canSaveKey: Bool {
        !keyDraft.trimmingCharacters(in: .whitespaces).isEmpty && model.mode == .normal
    }

    private var canConnect: Bool {
        !isBusy && !model.isDemo && model.hasAPIKey && SteamIDInput.parse(model.steamIDInput) != nil
    }

    private func saveKey() {
        guard canSaveKey else { return }
        model.saveAPIKey(keyDraft)
        keyDraft = ""
    }
}

private struct StatusRow: View {
    @Environment(AppModel.self) private var model
    @State private var showHelp = false

    var body: some View {
        switch model.libraryState {
        case .loading(let message):
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(message).foregroundStyle(.secondary) }
        case .failed(let message):
            VStack(alignment: .trailing, spacing: 4) {
                Text(message).foregroundStyle(Theme.Palette.labelRed).multilineTextAlignment(.trailing)
                DisclosureGroup("Help", isExpanded: $showHelp) {
                    Text("Steam only shares your game list when Profile → Edit Profile → Privacy Settings → Game details is set to Public.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: 260)
            }
        case .idle:
            if let summary = model.playerSummary, !model.isDemo {
                HStack(spacing: 8) {
                    AsyncImage(url: summary.avatarfull.flatMap(URL.init(string:))) { $0.resizable() } placeholder: { Color.gray.opacity(0.3) }
                        .frame(width: 28, height: 28).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 0) {
                        Text(summary.personaname)
                        if let library = model.library {
                            Text("\(library.games.count) games · refreshed \(Self.relative(library.fetchedAt))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private static func relative(_ date: Date) -> String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: .now)
    }
}

private enum GameFilter: String, CaseIterable, Identifiable {
    case all = "All", played = "Played", onShelf = "On Shelf"
    var id: String { rawValue }
}

private enum GameSort: String, CaseIterable, Identifiable {
    case name = "Name", hours = "Hours Played", lastPlayed = "Last Played"
    var id: String { rawValue }
}

struct LibraryChecklist: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var filter: GameFilter = .all
    @State private var sort: GameSort = .name
    @State private var confirmSelectAll = false

    private var shown: [OwnedGame] {
        var games = model.library?.games ?? []
        if !search.isEmpty { games = games.filter { $0.displayName.localizedCaseInsensitiveContains(search) } }
        switch filter {
        case .all: break
        case .played: games = games.filter { $0.playtime_forever > 0 }
        case .onShelf: games = games.filter { model.isShelved($0.appid) }
        }
        switch sort {
        case .name: games.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        case .hours: games.sort { $0.playtime_forever > $1.playtime_forever }
        case .lastPlayed: games.sort { ($0.lastPlayedDate ?? .distantPast) > ($1.lastPlayedDate ?? .distantPast) }
        }
        return games
    }

    var body: some View {
        let games = shown
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search", text: $search).textFieldStyle(.plain)
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                Picker("", selection: $filter) {
                    ForEach(GameFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 220)
                Menu("Sort: \(sort.rawValue)") {
                    ForEach(GameSort.allCases) { s in Button(s.rawValue) { sort = s } }
                }
                .fixedSize()
            }
            .padding(12)

            if games.isEmpty {
                Spacer()
                Text(model.library == nil ? "Connect your Steam account to list your games." : "No games match.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(games) { game in GameRow(game: game) }
                    .listStyle(.inset)
            }

            Divider()
            HStack {
                Text("\(model.document.shelvedEntries.count) on shelf · \(model.library?.games.count ?? 0) owned")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Select None") { model.setAllShelved(false, appIDs: (model.library?.games ?? []).map(\.appid)) }
                    .disabled(model.library == nil)
                Button("Select All Shown") {
                    if games.count > 200 { confirmSelectAll = true }
                    else { model.setAllShelved(true, appIDs: games.map(\.appid)) }
                }
                .disabled(games.isEmpty)
            }
            .padding(.horizontal, 12).padding(.top, 8)
            HStack {
                Button("Refresh Library") { Task { await model.refreshLibrary() } }
                Button("Refresh Achievements") { Task { await model.refreshAllStats() } }
                Spacer()
            }
            .disabled(model.isDemo || model.mode != .normal || model.resolvedSteamID == nil)
            .padding(12)
        }
        .alert("Put \(games.count) games on the shelf?", isPresented: $confirmSelectAll) {
            Button("Cancel", role: .cancel) {}
            Button("Select All") { model.setAllShelved(true, appIDs: games.map(\.appid)) }
        }
    }
}

struct GameRow: View {
    let game: OwnedGame
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(get: { model.isShelved(game.appid) }, set: { model.setShelved(game.appid, $0) })) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
            CoverThumb(game: game)
            VStack(alignment: .leading, spacing: 1) {
                Text(game.displayName).font(.system(size: 13))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var detail: String {
        let hours = String(format: "%.1f hrs", Double(game.playtime_forever) / 60)
        if let last = game.lastPlayedDate {
            return "\(hours) · last played \(last.formatted(.dateTime.month(.abbreviated).day().year()))"
        }
        return "\(hours) · never played"
    }
}

private struct CoverThumb: View {
    let game: OwnedGame
    @Environment(AppModel.self) private var model
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
            } else {
                CoverPalette.forApp(game.appid).top
            }
        }
        .frame(width: 24, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .task(id: game.appid) {
            guard model.mode == .normal, !model.isDemo else { return }
            let assets = model.library?.assets[game.appid]
            let request = CoverRequest(appID: game.appid, title: game.displayName,
                                       portraitURLs: CoverURLs.portraitCandidates(appID: game.appid, assets: assets),
                                       headerURL: nil)
            if case .portrait(let img) = await model.images.cover(for: request) { image = img.cgImage }
        }
    }
}
