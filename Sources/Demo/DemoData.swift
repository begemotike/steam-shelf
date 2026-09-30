import Foundation

enum DemoData {
    static let steamID = "76561190000000000"

    static let titles: [String] = [
        "Moose Kart Deluxe", "Tundra Tactics", "The Last Ferry to Kodiak", "Spreadsheet Knights", "Goose of War",
        "Crab Rave Tycoon", "Midnight Sun Racing", "Permafrost Protocol", "Salmon Run 2: Upstream", "Northern Lights Out",
        "Server Room Survivor", "Ticket Queue Zero", "Password123: The Game", "Aurora Drift", "Big Rig Iditarod",
        "Bush Pilot Simulator", "Cabin Fever Chronicles", "Denali Dash", "Eagle Eye Accounting", "Fjord Focus",
        "Glacier Grand Prix", "Halibut Heist", "Igloo Architect", "Jigsaw Junction", "Kayak Kingdom",
        "Lumberjack Legends: Spruce Edition", "Mainframe Meltdown", "Ninety Below", "Outage Overlord", "Patch Tuesday Panic",
        "Quiet Fjord Mysteries", "Reindeer Rodeo", "Sled Dog Symphony", "Trapline Trader", "Ulu Unleashed",
        "Volcano Valet", "Wi-Fi Wilderness", "Xtreme Snowmachine Repair", "Yukon Yarns", "Zero Bars Zone",
        "Backup Battalion", "Cold Boot Chronicles", "DNS Dungeon", "Ferry Schedule Simulator", "Gold Pan Grandmaster",
        "Help Desk Hero", "Ice Road Trucker Tales", "Junction Box Jenga", "Kelp Forest Keeper", "Lost Packet Lagoon",
    ]

    private static let notes = [
        "Bought it during a sale at 2 a.m.",
        "Better than the reviews suggested.",
        "Keeps crashing on the boss. Send help.",
        "Played this on the ferry. Twice.",
        "Gifted by a friend who knows me too well.",
        "Great with headphones and a hot drink.",
        "The soundtrack alone was worth it.",
        "Started strong, lost the plot around hour ten.",
    ]

    private static func games(now: Date) -> (games: [OwnedGame], entries: [ShelfEntry]) {
        var rng = SplitMix64(seed: 42)
        var games: [OwnedGame] = []
        var entries: [ShelfEntry] = []
        let achievementTotals = [0, 12, 30, 50, 77]
        for (i, title) in titles.enumerated() {
            let appID = 900_001 + i
            let minutes = rng.nextUnit() < 0.3 ? 0 : Int(pow(rng.nextUnit(), 3) * 60_000)
            let total = achievementTotals[rng.int(in: 0...(achievementTotals.count - 1))]
            let earned = total == 0 ? 0 : (minutes == 0 ? 0 : rng.int(in: 0...total))
            let rated = rng.nextUnit() < 0.6
            let rating = rated ? rng.int(in: 1...5) : nil
            let hasNote = rng.nextUnit() < 0.4
            let note = hasNote ? notes[rng.int(in: 0...(notes.count - 1))] : ""
            let hasPurchase = rng.nextUnit() < 0.3
            let purchase = hasPurchase ? now.addingTimeInterval(-Double(rng.int(in: 30...1500)) * 86_400) : nil
            let lastPlayed: Date? = minutes > 0 ? now.addingTimeInterval(-Double(rng.int(in: 1...900)) * 86_400) : nil
            let firstSeen = now.addingTimeInterval(-Double(rng.int(in: 10...1200)) * 86_400)

            games.append(OwnedGame(
                appid: appID, name: title, playtime_forever: minutes, img_icon_url: nil,
                has_community_visible_stats: total > 0,
                rtime_last_played: lastPlayed.map { Int($0.timeIntervalSince1970) } ?? 0, playtime_2weeks: nil))

            entries.append(ShelfEntry(
                appID: appID, title: title, isShelved: i < 40, rating: rating, note: note, purchaseDate: purchase,
                firstSeenAt: firstSeen,
                stats: CachedSteamStats(
                    playtimeMinutes: minutes, lastPlayed: lastPlayed, hasCommunityStats: total > 0,
                    achievementsEarned: total > 0 ? earned : nil, achievementsTotal: total > 0 ? total : nil,
                    achievementsState: total > 0 ? .ok : .none, fetchedAt: now),
                art: ArtRefs(portraitURLs: [], headerURL: nil), blurb: nil))
        }
        return (games, entries)
    }

    static func library(now: Date = .now) -> OwnedLibraryCache {
        let g = games(now: now)
        let firstSeen = Dictionary(uniqueKeysWithValues: g.entries.map { ($0.appID, $0.firstSeenAt) })
        return OwnedLibraryCache(steamID64: steamID, fetchedAt: now, games: g.games, firstSeen: firstSeen, assets: [:])
    }

    static func document(now: Date = .now) -> ShelfDocument {
        let g = games(now: now)
        var doc = ShelfDocument(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000042")!,
            title: "Demo Shelf",
            owner: ShelfOwner(steamID64: steamID, displayName: "Demo", avatarURL: nil),
            createdAt: now, updatedAt: now, entries: [])
        for entry in g.entries where entry.isShelved { doc.insertSorted(entry) }
        return doc
    }
}
