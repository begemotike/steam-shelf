import SwiftUI
import SwiftData
import AppKit
import OSLog

enum LaunchMode: Sendable { case normal, tests }

enum LoadState: Equatable, Sendable { case idle, loading(String), failed(String) }

enum SlideDirection: Sendable { case forward, backward }

@MainActor @Observable final class AppModel {
    private static let log = Logger(subsystem: "net.outofajam.SteamShelf", category: "AppModel")
    private enum DefaultsKey {
        static let steamIDInput = "steamIDInput"
        static let resolvedSteamID = "resolvedSteamID"
        static let hasAPIKey = "hasAPIKey"
        static let hasAIKey = "hasAIKey"
        static let aiKeyProviders = "aiKeyProviders"
        static let aiConfig = "aiConfig"
        static let playerSummary = "playerSummary"
        static let shelfLights = "shelfLights"
    }

    // Configuration
    let mode: LaunchMode
    var steamIDInput: String {
        didSet { if mode == .normal { UserDefaults.standard.set(steamIDInput, forKey: DefaultsKey.steamIDInput) } }
    }
    var resolvedSteamID: String? {
        didSet { if mode == .normal { UserDefaults.standard.set(resolvedSteamID, forKey: DefaultsKey.resolvedSteamID) } }
    }
    var hasAPIKey: Bool
    /// Services whose key is in the Keychain (mirrored here so launch never reads the Keychain).
    private(set) var aiKeyProviders: Set<String>
    /// The chosen AI service, endpoint and model for Shelf-Keeper notes.
    var aiConfig: AIConfig {
        didSet {
            guard aiConfig != oldValue else { return }
            if mode == .normal, let data = try? JSONEncoder().encode(aiConfig) { UserDefaults.standard.set(data, forKey: DefaultsKey.aiConfig) }
            if aiConfig.providerID != oldValue.providerID || aiConfig.baseURL != oldValue.baseURL { availableModels = []; modelsState = .idle }
        }
    }
    private(set) var availableModels: [String] = []
    private(set) var modelsState: LoadState = .idle
    var hasAIKey: Bool { aiKeyProviders.contains(aiConfig.providerID) }
    /// A service is chosen, it has a key if it needs one, and a model is picked.
    var aiReady: Bool { (hasAIKey || !aiConfig.preset.needsKey) && !aiConfig.model.isEmpty && aiConfig.base != nil }
    var hasSaveAccess: Bool
    var playerSummary: PlayerSummary?

    // Data
    private(set) var source: any ShelfSource
    private(set) var document: ShelfDocument
    private(set) var library: OwnedLibraryCache?
    var libraryState: LoadState = .idle

    // Shelf navigation
    var pageIndex: Int = 0
    var slideDirection: SlideDirection = .forward
    var pagination: Pagination { Pagination(itemCount: document.shelvedEntries.count) }

    // Open box
    var openedAppID: Int?
    var openedFromFrame: CGRect = .zero
    var isEditingLabel = false
    var isShowingNotes = false

    // Shelf-Keeper notes
    enum KeeperState: Equatable { case idle, reading, writing, failed(String) }
    var keeperState: [Int: KeeperState] = [:]
    private let keeperAI = ShelfKeeperAI()

    /// Warm LED strips under the crown and each plank (DESIGN addendum: shelf lights).
    var lightsOn: Bool {
        didSet { if mode == .normal { UserDefaults.standard.set(lightsOn, forKey: DefaultsKey.shelfLights) } }
    }

    func toggleLights() { withAnimation(Theme.Motion.lights) { lightsOn.toggle() } }

    // Local Steam client
    private(set) var installedAppIDs: Set<Int>?          // nil = unknown (no Steam, or unreadable)
    private(set) var steamAvailable = false
    /// Short-lived message for the base rail ("Handing off to Steam…"); cleared automatically.
    var transientStatus: String?
    private var transientTask: Task<Void, Never>?

    // File export / import (presented by ShelfView)
    var isExporting = false
    var exportFile: ShelfFile?
    var isImporting = false
    var pendingImport: Data?
    var fileAlert: String?

    // Services
    let steam: SteamClient
    let images: ImageCache
    let backOfBox: any BackOfBoxProvider

    private let container: ModelContainer
    private var saveTask: Task<Void, Never>?

    var isDemo: Bool { source.sourceID == "demo" }

    init(mode: LaunchMode, container: ModelContainer, startDemo: Bool = false) {
        self.mode = mode
        self.container = container
        self.steam = SteamClient()
        self.images = ImageCache()
        self.backOfBox = LocalBackOfBoxProvider()

        let defaults = UserDefaults.standard
        lightsOn = mode == .normal ? defaults.bool(forKey: DefaultsKey.shelfLights) : false
        if mode == .normal {
            steamIDInput = defaults.string(forKey: DefaultsKey.steamIDInput) ?? ""
            resolvedSteamID = defaults.string(forKey: DefaultsKey.resolvedSteamID)
            // Mirrored flag: reading the Keychain at launch would prompt after every ad-hoc rebuild.
            hasAPIKey = defaults.bool(forKey: DefaultsKey.hasAPIKey)
            var providers = Set(defaults.stringArray(forKey: DefaultsKey.aiKeyProviders) ?? [])
            if defaults.bool(forKey: DefaultsKey.hasAIKey) { providers.insert("anthropic") }   // key saved before multi-service support
            aiKeyProviders = providers
            aiConfig = defaults.data(forKey: DefaultsKey.aiConfig).flatMap { try? JSONDecoder().decode(AIConfig.self, from: $0) } ?? .default
            hasSaveAccess = SteamFolderAccess.isGranted
            playerSummary = defaults.data(forKey: DefaultsKey.playerSummary)
                .flatMap { try? JSONDecoder().decode(PlayerSummary.self, from: $0) }
            source = LocalShelfSource(container: container)
        } else {
            steamIDInput = ""
            resolvedSteamID = nil
            hasAPIKey = false
            aiKeyProviders = []
            aiConfig = .default
            hasSaveAccess = false
            playerSummary = nil
            source = DemoShelfSource()
        }
        document = ShelfDocument.empty(owner: ShelfOwner(steamID64: defaults.string(forKey: DefaultsKey.resolvedSteamID), displayName: "My Shelf", avatarURL: nil))
        if startDemo { self.startDemo() }
    }

    // MARK: Lifecycle

    func onLaunch() async {
        #if DEBUG
        await dumpDigestIfRequested()
        #endif
        guard mode == .normal, !isDemo else { return }
        if let doc = try? source.load() {
            document = doc
        } else {
            document = ShelfDocument.empty(owner: ownerFromState())
        }
        if let id = resolvedSteamID { library = LibraryStore.load(steamID: id) }
        pageIndex = pagination.clamp(pageIndex)
        if hasAPIKey, resolvedSteamID != nil, library?.isStale() ?? true {
            await refreshLibrary(manual: false)
        }
    }

    private func ownerFromState() -> ShelfOwner {
        ShelfOwner(steamID64: resolvedSteamID, displayName: playerSummary?.personaname ?? "My Shelf", avatarURL: playerSummary?.avatarfull)
    }

    // MARK: Account

    func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mode == .normal, !trimmed.isEmpty else { return }
        do {
            try Keychain.save(trimmed, account: Keychain.apiKeyAccount)
            hasAPIKey = true
            UserDefaults.standard.set(true, forKey: DefaultsKey.hasAPIKey)
            if case .failed = libraryState { libraryState = .idle }
        } catch {
            libraryState = .failed("Couldn't save the key in your Keychain.")
        }
    }

    func forgetAPIKey() {
        guard mode == .normal else { return }
        Keychain.delete(account: Keychain.apiKeyAccount)
        hasAPIKey = false
        UserDefaults.standard.set(false, forKey: DefaultsKey.hasAPIKey)
    }

    /// Saves a pasted key. When its prefix identifies a service (sk-ant-, sk-or-, gsk_, AIza, …) the
    /// service is switched to match, so pasting is all the user has to do.
    func saveAIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mode == .normal, !trimmed.isEmpty else { return }
        if let detected = AIProviders.detect(fromKey: trimmed), detected.id != aiConfig.providerID {
            aiConfig = AIConfig(preset: detected)
        }
        do {
            try Keychain.save(trimmed, account: Keychain.aiKeyAccount(for: aiConfig.providerID))
            aiKeyProviders.insert(aiConfig.providerID)
            persistAIKeyProviders()
            Task { await loadModels() }
        } catch {
            Self.log.error("Couldn't save the AI key in the Keychain")
        }
    }

    private func persistAIKeyProviders() {
        UserDefaults.standard.set(aiKeyProviders.sorted(), forKey: DefaultsKey.aiKeyProviders)
        UserDefaults.standard.set(aiKeyProviders.contains("anthropic"), forKey: DefaultsKey.hasAIKey)
    }

    func selectAIProvider(_ id: String) {
        guard id != aiConfig.providerID else { return }
        aiConfig = AIConfig(preset: AIProviders.preset(id))
        if aiReady || hasAIKey || !aiConfig.preset.needsKey { Task { await loadModels() } }
    }

    /// Asks the service which models it offers (fills the picker in Settings).
    func loadModels() async {
        guard mode == .normal, aiConfig.base != nil, hasAIKey || !aiConfig.preset.needsKey else { return }
        let config = aiConfig
        let key = Keychain.read(account: Keychain.aiKeyAccount(for: config.providerID)) ?? ""
        modelsState = .loading("Asking for the model list…")
        do {
            let models = try await keeperAI.models(key: key, config: config)
            guard config.providerID == aiConfig.providerID, config.baseURL == aiConfig.baseURL else { return }
            availableModels = models
            modelsState = .idle
        } catch is CancellationError {
            modelsState = .idle
        } catch {
            guard config.providerID == aiConfig.providerID else { return }
            modelsState = .failed((error as? KeeperError)?.userMessage ?? error.localizedDescription)
        }
    }

    func forgetAIKey() {
        guard mode == .normal else { return }
        Keychain.delete(account: Keychain.aiKeyAccount(for: aiConfig.providerID))
        aiKeyProviders.remove(aiConfig.providerID)
        persistAIKeyProviders()
        availableModels = []
    }

    func requestSaveAccess() {
        guard mode == .normal else { return }
        hasSaveAccess = SteamFolderAccess.requestAccess()
    }

    func revokeSaveAccess() {
        guard mode == .normal else { return }
        SteamFolderAccess.revoke()
        hasSaveAccess = false
    }

    private func requireKey() throws -> String {
        guard let key = Keychain.read(account: Keychain.apiKeyAccount), !key.isEmpty else { throw SteamError.missingKey }
        return key
    }

    private func fail(_ error: Error) {
        if error is CancellationError { libraryState = .idle; return }
        libraryState = .failed((error as? SteamError)?.userMessage ?? error.localizedDescription)
    }

    func connect() async {
        guard mode == .normal, !isDemo else { return }
        guard let input = SteamIDInput.parse(steamIDInput) else { libraryState = .failed(SteamError.badSteamIDInput.userMessage); return }
        do {
            let key = try requireKey()
            libraryState = .loading("Finding your profile…")
            let id = try await steam.resolveSteamID(input, key: key)
            let summary = try await steam.playerSummary(steamID: id, key: key)
            resolvedSteamID = id
            playerSummary = summary
            if let data = try? JSONEncoder().encode(summary) { UserDefaults.standard.set(data, forKey: DefaultsKey.playerSummary) }
            library = LibraryStore.load(steamID: id)
            document.owner = ShelfOwner(steamID64: id, displayName: summary.personaname, avatarURL: summary.avatarfull)
            if document.title == "My Shelf" || document.title.hasSuffix("'s Shelf") {
                document.title = "\(summary.personaname)'s Shelf"
            }
            scheduleSave()
            await refreshLibrary(manual: true)
        } catch {
            fail(error)
        }
    }

    func refreshLibrary(manual: Bool = true) async {
        guard mode == .normal, !isDemo, let steamID = resolvedSteamID else { return }
        do {
            let key = try requireKey()
            libraryState = .loading("Loading your library…")
            let games = try await steam.ownedGames(steamID: steamID, key: key)

            libraryState = .loading("Fetching cover art…")
            var assets = library?.assets ?? [:]
            let wanted = manual ? games.map(\.appid) : games.map(\.appid).filter { assets[$0] == nil }
            if !wanted.isEmpty, let fresh = try? await steam.storeAssets(appIDs: wanted) {
                assets.merge(fresh) { _, new in new }
            }

            let now = Date()
            var firstSeen = library?.firstSeen ?? [:]
            for game in games where firstSeen[game.appid] == nil { firstSeen[game.appid] = now }
            let cache = OwnedLibraryCache(steamID64: steamID, fetchedAt: now, games: games, firstSeen: firstSeen, assets: assets)
            library = cache
            try? LibraryStore.save(cache)

            mergeLibraryIntoEntries(cache)
            libraryState = .idle
        } catch {
            fail(error)
        }
    }

    private func mergeLibraryIntoEntries(_ cache: OwnedLibraryCache) {
        let byID = Dictionary(cache.games.map { ($0.appid, $0) }, uniquingKeysWith: { a, _ in a })
        var changed = false
        for i in document.entries.indices {
            let id = document.entries[i].appID
            guard let game = byID[id] else { continue }
            var entry = document.entries[i]
            entry.title = game.displayName
            entry.stats.playtimeMinutes = game.playtime_forever
            entry.stats.lastPlayed = game.lastPlayedDate
            entry.stats.hasCommunityStats = game.has_community_visible_stats ?? false
            entry.art = Self.artRefs(appID: id, assets: cache.assets[id])
            if entry != document.entries[i] { document.entries[i] = entry; changed = true }
        }
        if changed { document.updatedAt = Date(); scheduleSave() }
    }

    private static func artRefs(appID: Int, assets: StoreAssets?) -> ArtRefs {
        ArtRefs(portraitURLs: CoverURLs.portraitCandidates(appID: appID, assets: assets),
                headerURL: CoverURLs.header(appID: appID, assets: assets))
    }

    func refreshStats(for appID: Int, force: Bool = false) async {
        guard mode == .normal, !isDemo, let steamID = resolvedSteamID,
              let entry = document.entries.first(where: { $0.appID == appID }) else { return }
        guard entry.stats.hasCommunityStats else {
            if entry.stats.achievementsState != .none {
                update(appID) { $0.stats.achievementsState = .none; $0.stats.achievementsEarned = nil; $0.stats.achievementsTotal = nil }
            }
            return
        }
        if !force, let fetched = entry.stats.fetchedAt, Date().timeIntervalSince(fetched) < 6 * 3600 { return }
        do {
            let key = try requireKey()
            let summary = try await steam.achievements(appID: appID, steamID: steamID, key: key)
            update(appID) {
                $0.stats.fetchedAt = Date()
                if summary.total == 0 {
                    $0.stats.achievementsState = .none; $0.stats.achievementsEarned = nil; $0.stats.achievementsTotal = nil
                } else {
                    $0.stats.achievementsState = .ok
                    $0.stats.achievementsEarned = summary.earned
                    $0.stats.achievementsTotal = summary.total
                }
            }
        } catch SteamError.privateProfile {
            update(appID) { $0.stats.achievementsState = .privateProfile; $0.stats.fetchedAt = Date() }
        } catch SteamError.noStats {
            update(appID) { $0.stats.achievementsState = .none; $0.stats.fetchedAt = Date() }
        } catch {
            Self.log.debug("Achievements refresh failed for \(appID, privacy: .public)")
        }
    }

    func refreshAllStats() async {
        guard mode == .normal, !isDemo else { return }
        let ids = document.shelvedEntries.map(\.appID)
        libraryState = .loading("Refreshing achievements…")
        var start = 0
        while start < ids.count {
            let chunk = Array(ids[start..<min(start + 4, ids.count)])
            start += 4
            await withTaskGroup(of: Void.self) { group in
                for id in chunk { group.addTask { await self.refreshStats(for: id, force: true) } }
            }
        }
        if case .loading = libraryState { libraryState = .idle }
    }

    // MARK: Selection

    func isShelved(_ appID: Int) -> Bool {
        document.entries.first(where: { $0.appID == appID })?.isShelved ?? false
    }

    func setShelved(_ appID: Int, _ on: Bool) {
        applyShelved(appID, on)
        finishShelfMutation()
    }

    func setAllShelved(_ on: Bool, appIDs: [Int]) {
        for id in appIDs { applyShelved(id, on) }
        finishShelfMutation()
    }

    private func applyShelved(_ appID: Int, _ on: Bool) {
        if let i = document.entries.firstIndex(where: { $0.appID == appID }) {
            document.entries[i].isShelved = on
        } else if on, let game = library?.games.first(where: { $0.appid == appID }) {
            let entry = ShelfEntry(
                appID: appID, title: game.displayName, isShelved: true, rating: nil, note: "", purchaseDate: nil,
                firstSeenAt: library?.firstSeen[appID] ?? Date(),
                stats: CachedSteamStats(
                    playtimeMinutes: game.playtime_forever, lastPlayed: game.lastPlayedDate,
                    hasCommunityStats: game.has_community_visible_stats ?? false,
                    achievementsEarned: nil, achievementsTotal: nil, achievementsState: .unknown, fetchedAt: nil),
                art: isDemo ? ArtRefs(portraitURLs: [], headerURL: nil) : Self.artRefs(appID: appID, assets: library?.assets[appID]),
                blurb: nil)
            document.insert(entry)
        }
    }

    private func finishShelfMutation() {
        document.updatedAt = Date()
        pageIndex = pagination.clamp(pageIndex)
        scheduleSave()
    }

    // MARK: Local Steam client

    enum InstallState { case installed, notInstalled, unknown }

    func installState(for appID: Int) -> InstallState {
        guard let installed = installedAppIDs else { return .unknown }
        return installed.contains(appID) ? .installed : .notInstalled
    }

    /// Cheap (one small file); called when the app comes to the front and when a box opens.
    func refreshInstalls() {
        guard mode == .normal else { return }
        steamAvailable = SteamInstalls.isSteamAvailable
        installedAppIDs = SteamInstalls.scan()
        Self.log.info("Steam client available: \(self.steamAvailable, privacy: .public); installed games known: \(self.installedAppIDs?.count ?? -1, privacy: .public)")
        #if DEBUG
        if let sample = installedAppIDs?.sorted().first {
            let bundle = SteamInstalls.launchBundle(appID: sample)?.lastPathComponent ?? "none found"
            Self.log.info("Direct-launch probe for app \(sample, privacy: .public): \(bundle, privacy: .public)")
        }
        #endif
    }

    /// Whether the Play/Install button should show for the opened box.
    var canLaunchGames: Bool { mode == .normal && !isDemo && steamAvailable && source.sourceID == "local" }

    /// Opens the game's own app bundle from its install folder when we can find it; otherwise hands
    /// the game to the Steam client (which launches it, or offers to install it).
    func launch(_ appID: Int) {
        guard canLaunchGames else { return }
        let title = document.entries.first { $0.appID == appID }?.title ?? "game"
        if installState(for: appID) != .notInstalled, let bundle = SteamInstalls.launchBundle(appID: appID) {
            showTransient("Launching \(title)…")
            NSWorkspace.shared.openApplication(at: bundle, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                guard let error else { return }
                Task { @MainActor in
                    Self.log.error("Direct launch failed: \(String(describing: error), privacy: .public)")
                    self.launchViaSteam(appID, title: title)
                }
            }
        } else {
            launchViaSteam(appID, title: title)
        }
    }

    private func launchViaSteam(_ appID: Int, title: String) {
        guard let url = SteamInstalls.launchURL(appID: appID) else { return }
        NSWorkspace.shared.open(url)
        showTransient(installState(for: appID) == .notInstalled ? "Asking Steam to install \(title)…" : "Handing \(title) to Steam…")
    }

    func showTransient(_ message: String, seconds: Double = 5) {
        transientTask?.cancel()
        transientStatus = message
        transientTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.transientStatus = nil
        }
    }

    // MARK: Arrangement

    var isCustomArranged: Bool { document.arrangement == .custom }

    /// Drag-and-drop reorder: put `appID` before `targetAppID`, or at the end when nil.
    func moveEntry(_ appID: Int, before targetAppID: Int?) {
        guard document.move(appID: appID, before: targetAppID) else { return }
        finishShelfMutation()
    }

    func arrangeAlphabetically() {
        guard isCustomArranged else { return }
        document.arrangeAlphabetically()
        finishShelfMutation()
    }

    /// Drag hovering over a handle: flip to that page after a short dwell so boxes can cross pages.
    private var dwellTask: Task<Void, Never>?
    func dragHover(over side: HandleSide, active: Bool) {
        dwellTask?.cancel()
        guard active else { return }
        dwellTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, let self else { return }
            self.go(to: self.pagination.target(for: side, clickCount: 1, currentPage: self.pageIndex))
        }
    }

    // MARK: Entry edits

    func update(_ appID: Int, _ mutate: (inout ShelfEntry) -> Void) {
        guard let i = document.entries.firstIndex(where: { $0.appID == appID }) else { return }
        mutate(&document.entries[i])
        document.updatedAt = Date()
        scheduleSave()
    }

    // MARK: Paging

    func go(to page: Int, animation: Animation = Theme.Motion.pageSlide) {
        let target = pagination.clamp(page)
        guard target != pageIndex else { return }
        slideDirection = target > pageIndex ? .forward : .backward
        withAnimation(animation) { pageIndex = target }
    }

    func handleTapped(_ side: HandleSide) {
        let clicks = NSApp.currentEvent?.clickCount ?? 1
        go(to: pagination.target(for: side, clickCount: clicks, currentPage: pageIndex),
           animation: clicks >= 2 ? Theme.Motion.pageJump : Theme.Motion.pageSlide)
    }

    // MARK: Open / close

    func open(_ appID: Int, from frame: CGRect) {
        guard openedAppID == nil else { return }
        openedFromFrame = frame
        openedAppID = appID
    }

    func close() {
        openedAppID = nil
        isEditingLabel = false
        isShowingNotes = false
    }

    // MARK: Demo

    func startDemo() {
        saveTask?.cancel()
        var doc = DemoData.document()
        #if DEBUG
        // `--demo-notes`: give the first shelved entry stored Shelf-Keeper notes, to look at the panel without an API call.
        if CommandLine.arguments.contains("--demo-notes"), let id = doc.shelvedEntries.first?.appID,
           let i = doc.entries.firstIndex(where: { $0.appID == id }) {
            doc.entries[i].blurb = DebugNotes.sample
        }
        #endif
        source = DemoShelfSource(document: doc)
        document = doc
        library = DemoData.library()
        libraryState = .idle
        pageIndex = 0
        close()
    }

    func leaveDemo() {
        guard mode != .tests else { return }
        saveTask?.cancel()
        source = LocalShelfSource(container: container)
        if let doc = try? source.load() { document = doc }
        else { document = ShelfDocument.empty(owner: ownerFromState()) }
        library = resolvedSteamID.flatMap { LibraryStore.load(steamID: $0) }
        libraryState = .idle
        pageIndex = pagination.clamp(0)
        close()
    }

    // MARK: Export / import

    func exportData() throws -> Data {
        try ShelfDocumentCodec.encode(document.forSharing())
    }

    func beginExport() {
        do {
            exportFile = ShelfFile(data: try exportData())
            isExporting = true
        } catch {
            fileAlert = "Couldn't prepare the shelf for export."
        }
    }

    func beginImport() { isImporting = true }

    /// Validates a chosen file and asks for confirmation before it replaces the shelf.
    func stageImport(_ data: Data) {
        do {
            _ = try ShelfDocumentCodec.decode(data)
            pendingImport = data
        } catch DocumentError.unsupportedVersion(let v) {
            fileAlert = "That shelf was made by a newer version of Steam Shelf (format \(v))."
        } catch {
            fileAlert = "That file isn't a Steam Shelf document."
        }
    }

    func confirmImport() {
        guard let data = pendingImport else { return }
        pendingImport = nil
        do { try importDocument(data) } catch { fileAlert = "Couldn't import that shelf." }
    }

    func importDocument(_ data: Data) throws {
        document = try ShelfDocumentCodec.decode(data)
        pageIndex = pagination.clamp(pageIndex)
        scheduleSave()
    }

    // MARK: Private

    private func scheduleSave() {
        guard mode != .tests else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            do { try self.source.save(self.document) }
            catch { Self.log.error("Save failed: \(String(describing: error), privacy: .public)") }
        }
    }

    func blurbIfNeeded(for appID: Int) async {
        guard let entry = document.entries.first(where: { $0.appID == appID }) else { return }
        if entry.blurb?.isAIWritten == true { return }       // Shelf-Keeper notes are never replaced by the template
        let context = BackOfBoxContext(entry: entry)
        if let existing = entry.blurb, existing.inputFingerprint == context.fingerprint { return }
        guard let content = try? await backOfBox.content(for: context) else { return }
        update(appID) { $0.blurb = content }
    }

    // MARK: Shelf-Keeper notes

    /// Notes can be written only on the user's own local shelf (not the demo, not an imported one).
    var canWriteNotes: Bool { mode == .normal && !isDemo && source.sourceID == "local" }

    func keeperState(for appID: Int) -> KeeperState { keeperState[appID] ?? .idle }

    func writeNotes(for appID: Int) async {
        guard canWriteNotes, let personalizer = Personalizers.forApp(appID) else { return }
        switch keeperState(for: appID) {
        case .reading, .writing: return
        case .idle, .failed: break
        }
        guard hasSaveAccess else { keeperState[appID] = .failed(KeeperText.noAccess); return }
        guard aiReady else { keeperState[appID] = .failed(KeeperText.noKey); return }
        let config = aiConfig
        let key = Keychain.read(account: Keychain.aiKeyAccount(for: config.providerID)) ?? ""
        guard !key.isEmpty || !config.preset.needsKey else { keeperState[appID] = .failed(KeeperText.noKey); return }

        keeperState[appID] = .reading
        let digest: GameDigest
        do {
            let found = try await Task.detached(priority: .userInitiated) {
                try SteamFolderAccess.withAccess { try personalizer.digest(steamRoot: $0) }
            }.value
            guard let found else { throw PersonalizerError.noSaves }
            digest = found
        } catch {
            keeperState[appID] = .failed(KeeperText.message(for: error))
            return
        }

        keeperState[appID] = .writing
        do {
            let notes = try await keeperAI.notes(game: personalizer.displayName, digest: digest, key: key, config: config)
            update(appID) {
                $0.blurb = BackOfBoxContent(
                    blurb: notes.blurb, tagline: notes.tagline, providerID: config.contentProviderID,
                    inputFingerprint: digest.fingerprint, generatedAt: Date(), observations: notes.observations, detail: notes.playstyle)
            }
            keeperState[appID] = .idle
        } catch is CancellationError {
            keeperState[appID] = .idle
        } catch {
            keeperState[appID] = .failed(KeeperText.message(for: error))
        }
    }

    /// Returns the entry to the local template blurb.
    func clearNotes(for appID: Int) {
        guard canWriteNotes else { return }
        update(appID) { $0.blurb = nil }
        keeperState[appID] = .idle
        Task { await blurbIfNeeded(for: appID) }
    }
}

enum KeeperText {
    static let noAccess = "Steam Shelf doesn't have access to your Steam folder yet."
    static let noKey = "Choose an AI service, key and model in Settings first."

    static func message(for error: Error) -> String {
        if let e = error as? KeeperError { return e.userMessage }
        switch error as? PersonalizerError {
        case .noFolderAccess?: return noAccess
        case .noSaves?: return "No save files were found for this game."
        case .corrupt?, .unsupported?: return "The save files couldn't be read."
        case nil: return error.localizedDescription
        }
    }
}

#if DEBUG
enum DebugNotes {
    static let sample = BackOfBoxContent(
        blurb: "Eleven saves named after what you did to people, and one honest 'Goblin Camp CLEARED' with the caps lock firmly on.",
        tagline: "Chatty, thorough, vengeful.",
        providerID: "anthropic.claude-opus-5-5", inputFingerprint: "118:1780000000", generatedAt: Date(),
        observations: [
            "Your save names read like a rap sheet: 'killed ethel outside' is not a title most players volunteer.",
            "At 17h 17m you reloaded to 17h 5m and called it 'new attempt'. We both know it was a second attempt at the same bad idea.",
            "Gale is in the party for every save before 40 hours, then vanishes. Either he has finally learned something, or you have.",
            "Eleven consecutive autosaves on one Tuesday night, ending after midnight. Sleep is a side quest you keep declining.",
            "You typed 'CLEARED' in capitals exactly once, which tells us how that felt.",
        ],
        detail: "You talk first and swing later: Persuasion and Insight checks outnumber everything else, and the same dialogue with the dead keeps coming back. When talking fails you take the Strength route and do not seem sorry.")
}
#endif

#if DEBUG
extension AppModel {
    /// `--dump-digest <appid>`: writes the personalizer digest to <Caches>/SteamShelf/digest-<appid>.txt (no AI call),
    /// so the Swift port can be compared with the Python reference on real saves.
    func dumpDigestIfRequested() async {
        let args = CommandLine.arguments
        guard mode == .normal, let flag = args.firstIndex(of: "--dump-digest"), flag + 1 < args.count,
              let appID = Int(args[flag + 1]), let personalizer = Personalizers.forApp(appID) else { return }
        let log = Logger(subsystem: "net.outofajam.SteamShelf", category: "DumpDigest")
        guard hasSaveAccess else { log.error("--dump-digest: save access not granted"); return }
        do {
            let digest = try await Task.detached(priority: .userInitiated) {
                try SteamFolderAccess.withAccess { try personalizer.digest(steamRoot: $0) }
            }.value
            guard let digest else { log.error("--dump-digest: no saves found"); return }
            let dir = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appending(path: "SteamShelf", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appending(path: "digest-\(appID).txt")
            let text = "== SAVE HISTORY ==\n\(digest.history)\n\n== MOST RECENT SAVE ==\n\(digest.latest)\n\nfingerprint: \(digest.fingerprint)\nsaves: \(digest.saveCount)\n"
            try text.write(to: file, atomically: true, encoding: .utf8)
            log.info("Wrote digest to \(file.path, privacy: .public)")
        } catch {
            log.error("--dump-digest failed: \(String(describing: error), privacy: .public)")
        }
    }
}
#endif
