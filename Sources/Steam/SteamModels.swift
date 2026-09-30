import Foundation

struct ResolveVanityEnvelope: Decodable, Sendable {
    struct R: Decodable, Sendable { let success: Int; let steamid: String?; let message: String? }
    let response: R
}

struct PlayerSummariesEnvelope: Decodable, Sendable {
    struct R: Decodable, Sendable { let players: [PlayerSummary] }
    let response: R
}

struct PlayerSummary: Codable, Sendable, Equatable {
    let steamid: String
    let personaname: String
    let profileurl: String?
    let avatarfull: String?
    let communityvisibilitystate: Int?
}

struct OwnedGamesEnvelope: Decodable, Sendable {
    struct R: Decodable, Sendable { let game_count: Int?; let games: [OwnedGame]? }
    let response: R
}

struct OwnedGame: Codable, Sendable, Equatable, Identifiable {
    var id: Int { appid }
    let appid: Int
    let name: String?
    let playtime_forever: Int
    let img_icon_url: String?
    let has_community_visible_stats: Bool?
    let rtime_last_played: Int?
    let playtime_2weeks: Int?

    var displayName: String { name ?? "App \(appid)" }
    var lastPlayedDate: Date? {
        guard let t = rtime_last_played, t > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(t))
    }
}

struct PlayerStatsEnvelope: Decodable, Sendable {
    struct Stats: Decodable, Sendable {
        let success: Bool
        let error: String?
        let gameName: String?
        let achievements: [Achievement]?
    }
    struct Achievement: Decodable, Sendable {
        let apiname: String
        let achieved: Int
        let unlocktime: Int?
    }
    let playerstats: Stats
}

struct StoreItemsEnvelope: Decodable, Sendable {
    struct R: Decodable, Sendable { let store_items: [StoreItem]? }
    let response: R
}

struct StoreItem: Decodable, Sendable {
    let id: Int
    let success: Int
    let name: String?
    let assets: StoreAssets?
}

struct StoreAssets: Codable, Sendable, Equatable {
    let asset_url_format: String?
    let library_capsule: String?
    let library_capsule_2x: String?
    let header: String?
}

struct AchievementSummary: Sendable, Equatable {
    let earned: Int
    let total: Int
}
