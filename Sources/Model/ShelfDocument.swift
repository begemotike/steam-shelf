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

    var shelvedEntries: [ShelfEntry] { entries.filter(\.isShelved) }

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

    /// v1 ordering: title, case-insensitive, `localizedStandardCompare`.
    mutating func insertSorted(_ entry: ShelfEntry) {
        let index = entries.firstIndex { existing in
            entry.title.localizedStandardCompare(existing.title) == .orderedAscending
        } ?? entries.count
        entries.insert(entry, at: index)
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
