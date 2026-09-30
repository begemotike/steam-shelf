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
        static let playerSummary = "playerSummary"
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
        if mode == .normal {
            steamIDInput = defaults.string(forKey: DefaultsKey.steamIDInput) ?? ""
            resolvedSteamID = defaults.string(forKey: DefaultsKey.resolvedSteamID)
            // Mirrored flag: reading the Keychain at launch would prompt after every ad-hoc rebuild.
            hasAPIKey = defaults.bool(forKey: DefaultsKey.hasAPIKey)
            playerSummary = defaults.data(forKey: DefaultsKey.playerSummary)
                .flatMap { try? JSONDecoder().decode(PlayerSummary.self, from: $0) }
            source = LocalShelfSource(container: container)
        } else {
            steamIDInput = ""
            resolvedSteamID = nil
            hasAPIKey = false
            playerSummary = nil
            source = DemoShelfSource()
        }
        document = ShelfDocument.empty(owner: ShelfOwner(steamID64: defaults.string(forKey: DefaultsKey.resolvedSteamID), displayName: "My Shelf", avatarURL: nil))
        if startDemo { self.startDemo() }
    }

    // MARK: Lifecycle

    func onLaunch() async {
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
    }

    // MARK: Demo

    func startDemo() {
        saveTask?.cancel()
        let doc = DemoData.document()
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
        let context = BackOfBoxContext(entry: entry)
        if let existing = entry.blurb, existing.inputFingerprint == context.fingerprint { return }
        guard let content = try? await backOfBox.content(for: context) else { return }
        update(appID) { $0.blurb = content }
    }
}
