import Foundation

struct ShelfDocument: Codable, Sendable, Equatable {
    static let currentVersion = 1
    var version: Int = ShelfDocument.currentVersion
    var id: UUID
    var title: String
    var owner: ShelfOwner
    var createdAt: Date
    var updatedAt: Date
    var entries: [ShelfEntry]
    /// Alphabetical until the owner drags a box; then the stored order is the arrangement.
    var arrangement: Arrangement = .alphabetical

    enum Arrangement: String, Codable, Sendable { case alphabetical, custom }

    var shelvedEntries: [ShelfEntry] { entries.filter(\.isShelved) }

    private enum CodingKeys: String, CodingKey { case version, id, title, owner, createdAt, updatedAt, entries, arrangement }

    init(id: UUID, title: String, owner: ShelfOwner, createdAt: Date, updatedAt: Date, entries: [ShelfEntry],
         arrangement: Arrangement = .alphabetical) {
        self.id = id; self.title = title; self.owner = owner
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.entries = entries; self.arrangement = arrangement
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? ShelfDocument.currentVersion
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        owner = try c.decode(ShelfOwner.self, forKey: .owner)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        entries = try c.decode([ShelfEntry].self, forKey: .entries)
        // Older documents have no `arrangement`; they were always alphabetical.
        arrangement = try c.decodeIfPresent(Arrangement.self, forKey: .arrangement) ?? .alphabetical
    }

    func forSharing() -> ShelfDocument {
        var copy = self
        copy.entries = entries.filter(\.isShelved)
        return copy
    }

    static func empty(owner: ShelfOwner) -> ShelfDocument {
        let now = Date()
        let name = owner.displayName
        return ShelfDocument(
            id: UUID(),
            title: name == "My Shelf" || name.isEmpty ? "My Shelf" : "\(name)'s Shelf",
            owner: owner,
            createdAt: now,
            updatedAt: now,
            entries: []
        )
    }

    /// Alphabetical ordering: title, case-insensitive, `localizedStandardCompare`.
    mutating func insertSorted(_ entry: ShelfEntry) {
        let index = entries.firstIndex { existing in
            entry.title.localizedStandardCompare(existing.title) == .orderedAscending
        } ?? entries.count
        entries.insert(entry, at: index)
    }

    /// Inserts according to the current arrangement: sorted, or at the end of a custom shelf.
    mutating func insert(_ entry: ShelfEntry) {
        switch arrangement {
        case .alphabetical: insertSorted(entry)
        case .custom: entries.append(entry)
        }
    }

    /// Moves `appID` so it sits immediately before `targetAppID` (or at the end when nil).
    /// Any move makes the arrangement custom. Returns false when nothing changed.
    @discardableResult
    mutating func move(appID: Int, before targetAppID: Int?) -> Bool {
        guard appID != targetAppID, let from = entries.firstIndex(where: { $0.appID == appID }) else { return false }
        let moving = entries.remove(at: from)
        let to: Int
        if let targetAppID, let t = entries.firstIndex(where: { $0.appID == targetAppID }) { to = t }
        else { to = entries.count }
        entries.insert(moving, at: to)
        arrangement = .custom
        return true
    }

    /// Re-sorts every entry by title and returns to the alphabetical arrangement.
    mutating func arrangeAlphabetically() {
        entries.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        arrangement = .alphabetical
    }
}

struct ShelfOwner: Codable, Sendable, Equatable {
    var steamID64: String?
    var displayName: String
    var avatarURL: String?
}

struct ShelfEntry: Codable, Sendable, Equatable, Identifiable {
    var id: Int { appID }
    var appID: Int
    var title: String
    var isShelved: Bool
    var rating: Int?
    var note: String
    var purchaseDate: Date?
    var firstSeenAt: Date
    var stats: CachedSteamStats
    var art: ArtRefs
    var blurb: BackOfBoxContent?
}

struct CachedSteamStats: Codable, Sendable, Equatable {
    var playtimeMinutes: Int
    var lastPlayed: Date?
    var hasCommunityStats: Bool
    var achievementsEarned: Int?
    var achievementsTotal: Int?
    var achievementsState: AchievementsState
    var fetchedAt: Date?
}

enum AchievementsState: String, Codable, Sendable { case unknown, none, privateProfile, ok }

struct ArtRefs: Codable, Sendable, Equatable {
    var portraitURLs: [String]
    var headerURL: String?
}

enum DocumentError: Error, Equatable { case unsupportedVersion(Int) }

enum ShelfDocumentCodec {
    private struct VersionProbe: Decodable { let version: Int }

    static func encode(_ doc: ShelfDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(doc)
    }

    static func decode(_ data: Data) throws -> ShelfDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Probe the version first so a future document with a different shape reports
        // `unsupportedVersion` rather than a decoding error.
        if let probe = try? decoder.decode(VersionProbe.self, from: data), probe.version > ShelfDocument.currentVersion {
            throw DocumentError.unsupportedVersion(probe.version)
        }
        return try decoder.decode(ShelfDocument.self, from: data)
    }
}
