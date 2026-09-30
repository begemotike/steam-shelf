import Foundation

struct StoreDetailsLite: Codable, Sendable, Equatable {
    let genres: [String]
    let developer: String?
    let releaseDate: String?
}

struct BackOfBoxContext: Codable, Sendable, Equatable {
    let appID: Int
    let title: String
    let playtimeMinutes: Int
    let lastPlayed: Date?
    let firstSeenAt: Date
    let purchaseDate: Date?
    let achievementsEarned: Int?
    let achievementsTotal: Int?
    let rating: Int?
    let note: String
    let storeDetails: StoreDetailsLite?

    init(entry: ShelfEntry) {
        appID = entry.appID
        title = entry.title
        playtimeMinutes = entry.stats.playtimeMinutes
        lastPlayed = entry.stats.lastPlayed
        firstSeenAt = entry.firstSeenAt
        purchaseDate = entry.purchaseDate
        achievementsEarned = entry.stats.achievementsEarned
        achievementsTotal = entry.stats.achievementsTotal
        rating = entry.rating
        note = entry.note
        storeDetails = nil
    }

    /// Playtime bucket index 0...5 (0 h, <2, 2-20, 20-100, 100-500, 500+).
    var playtimeBucket: Int {
        let hours = Double(playtimeMinutes) / 60
        if playtimeMinutes <= 0 { return 0 }
        if hours < 2 { return 1 }
        if hours < 20 { return 2 }
        if hours < 100 { return 3 }
        if hours < 500 { return 4 }
        return 5
    }

    /// Stable fingerprint of the inputs the local provider cares about
    /// (playtime bucket, achievements, rating) — so typing a note never reshuffles the joke.
    var fingerprint: String {
        "b\(playtimeBucket)|a\(achievementsEarned.map(String.init) ?? "-")/\(achievementsTotal.map(String.init) ?? "-")|r\(rating.map(String.init) ?? "-")"
    }
}

struct BackOfBoxContent: Codable, Sendable, Equatable {
    var blurb: String
    var tagline: String?
    var providerID: String
    var inputFingerprint: String
    var generatedAt: Date
}

protocol BackOfBoxProvider: Sendable {
    var providerID: String { get }
    func content(for context: BackOfBoxContext) async throws -> BackOfBoxContent
}

struct LocalBackOfBoxProvider: BackOfBoxProvider {
    let providerID = "local.v1"

    private static let variants: [[(tagline: String, blurb: String)]] = [
        [("Still in the shrink-wrap.", "A pristine monument to good intentions. Mint condition. Never touched. Collectors weep."),
         ("Unopened, unbothered.", "Purchased with confidence, stored with dignity. The backlog salutes it.")],
        [("Tried it once.", "Launched, looked around, alt-tabbed. The relationship is complicated."),
         ("A brief encounter.", "A few minutes of polite curiosity. Neither party has called since.")],
        [("A pleasant fling.", "Enough hours to have opinions, not enough to defend them at a party."),
         ("Good while it lasted.", "A few evenings well spent. No regrets, no anniversary.")],
        [("A proper commitment.", "The save file has seen things. Weekends were sacrificed. Worth it, probably."),
         ("Serious business.", "Long sessions, strong opinions, and at least one snack-related incident.")],
        [("Load-bearing hobby.", "At this point the game plays you. Your chair has a permanent dent."),
         ("Part of the furniture.", "Hundreds of hours in, the loading screen feels like home.")],
        [("A second mortgage on free time.", "Legend says the owner once touched grass. Unconfirmed."),
         ("Time well beyond reason.", "The hours played now exceed several college degrees. No refunds.")],
    ]

    func content(for context: BackOfBoxContext) async throws -> BackOfBoxContent {
        let options = Self.variants[context.playtimeBucket]
        let pick = options[abs(context.appID) % options.count]
        var blurb = pick.blurb
        if let earned = context.achievementsEarned, let total = context.achievementsTotal, total > 0 {
            let extra: String
            if earned >= total { extra = "Every achievement. Every. Single. One." }
            else if earned * 2 >= total { extra = "Trophy case more than half full." }
            else if earned > 0 { extra = "A modest trophy shelf." }
            else { extra = "Zero achievements. Pure vibes." }
            blurb += " " + extra
        }
        return BackOfBoxContent(
            blurb: blurb,
            tagline: pick.tagline,
            providerID: providerID,
            inputFingerprint: context.fingerprint,
            generatedAt: Date()
        )
    }
}
