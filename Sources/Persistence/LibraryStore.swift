import Foundation

struct OwnedLibraryCache: Codable, Sendable, Equatable {
    var steamID64: String
    var fetchedAt: Date
    var games: [OwnedGame]
    var firstSeen: [Int: Date]
    var assets: [Int: StoreAssets]

    func isStale(now: Date = .now) -> Bool {
        now.timeIntervalSince(fetchedAt) > 6 * 3600
    }
}

enum LibraryStore {
    static func url(for steamID: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appending(path: "SteamShelf", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // steamID is digits only (validated upstream), but never let it escape the directory.
        let safe = steamID.filter { $0.isASCII && $0.isNumber }
        return dir.appending(path: "library-\(safe).json")
    }

    static func load(steamID: String) -> OwnedLibraryCache? {
        guard let data = try? Data(contentsOf: url(for: steamID)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(OwnedLibraryCache.self, from: data)
    }

    static func save(_ cache: OwnedLibraryCache) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(cache)
        try data.write(to: url(for: cache.steamID64), options: .atomic)
    }
}
