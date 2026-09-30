import Foundation
import OSLog

enum SteamError: Error, Equatable, Sendable {
    case missingKey, invalidKey, badSteamIDInput, vanityNotFound, profileNotFound
    case gameDetailsPrivate, privateProfile, noStats, rateLimited
    case http(Int), network(String), decoding(String), steam(String)

    var userMessage: String {
        switch self {
        case .missingKey: "Add your Steam Web API key first."
        case .invalidKey: "Steam rejected that API key. Double-check it at steamcommunity.com/dev/apikey."
        case .badSteamIDInput: "That doesn't look like a SteamID64 or a steamcommunity.com profile link."
        case .vanityNotFound: "No Steam profile uses that custom URL."
        case .profileNotFound: "Steam doesn't know that SteamID."
        case .gameDetailsPrivate: "Your game list is private. In Steam: Profile → Edit Profile → Privacy Settings → set Game details to Public."
        case .privateProfile: "Achievements are private for this profile."
        case .noStats: "This game has no achievements."
        case .rateLimited: "Steam asked us to slow down. Try again in a few minutes."
        case .http(let n): "Steam returned an error (HTTP \(n))."
        case .network(let msg): "Couldn't reach Steam: \(msg)"
        case .decoding(let msg), .steam(let msg): "Steam sent something unexpected. (\(msg))"
        }
    }
}

actor SteamClient {
    static let apiBase = URL(string: "https://api.steampowered.com")!
    private static let log = Logger(subsystem: "net.outofajam.SteamShelf", category: "SteamClient")

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: Public API

    func resolveSteamID(_ input: SteamIDInput, key: String) async throws -> String {
        switch input {
        case .steamID64(let id):
            return id
        case .vanity(let name):
            let (data, response) = try await get("ISteamUser/ResolveVanityURL/v1/", query: [
                URLQueryItem(name: "key", value: key),
                URLQueryItem(name: "vanityurl", value: name),
                URLQueryItem(name: "url_type", value: "1"),
            ])
            try Self.checkStatus(response.statusCode)
            return try Self.parseVanity(data)
        }
    }

    func playerSummary(steamID: String, key: String) async throws -> PlayerSummary {
        let (data, response) = try await get("ISteamUser/GetPlayerSummaries/v2/", query: [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "steamids", value: steamID),
        ])
        try Self.checkStatus(response.statusCode)
        return try Self.parseSummaries(data)
    }

    func ownedGames(steamID: String, key: String) async throws -> [OwnedGame] {
        let (data, response) = try await get("IPlayerService/GetOwnedGames/v1/", query: [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "steamid", value: steamID),
            URLQueryItem(name: "include_appinfo", value: "1"),
            URLQueryItem(name: "include_played_free_games", value: "1"),
        ])
        try Self.checkStatus(response.statusCode)
        return try Self.parseOwnedGames(data)
    }

    func achievements(appID: Int, steamID: String, key: String) async throws -> AchievementSummary {
        let (data, response) = try await get("ISteamUserStats/GetPlayerAchievements/v1/", query: [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "steamid", value: steamID),
            URLQueryItem(name: "appid", value: String(appID)),
            URLQueryItem(name: "l", value: "english"),
        ])
        // Parse before checking status: 400/403 bodies here are JSON (RESEARCH §1.4).
        return try Self.parseAchievements(data, status: response.statusCode)
    }

    func storeAssets(appIDs: [Int]) async throws -> [Int: StoreAssets] {
        var merged: [Int: StoreAssets] = [:]
        var lastError: Error?
        var succeeded = 0
        let unique = Array(Set(appIDs)).sorted()
        var start = 0
        while start < unique.count {
            let chunk = Array(unique[start..<min(start + 100, unique.count)])
            start += 100
            do {
                let json = try Self.storeItemsInputJSON(appIDs: chunk)
                let (data, response) = try await get("IStoreBrowseService/GetItems/v1/", query: [
                    URLQueryItem(name: "input_json", value: json),
                ])
                try Self.checkStatus(response.statusCode)
                merged.merge(try Self.parseStoreItems(data)) { _, new in new }
                succeeded += 1
            } catch {
                lastError = error
                Self.log.error("GetItems chunk failed: \(String(describing: error), privacy: .public)")
            }
        }
        if succeeded == 0, let lastError { throw (lastError as? SteamError) ?? SteamError.network(lastError.localizedDescription) }
        return merged
    }

    // MARK: Networking

    private func get(_ path: String, query: [URLQueryItem]) async throws -> (Data, HTTPURLResponse) {
        guard var components = URLComponents(url: Self.apiBase.appending(path: path), resolvingAgainstBaseURL: false) else {
            throw SteamError.network("Bad URL")
        }
        components.queryItems = query + [URLQueryItem(name: "format", value: "json")]
        guard let url = components.url else { throw SteamError.network("Bad URL") }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SteamError.network("Invalid response") }
            return (data, http)
        } catch let error as SteamError {
            throw error
        } catch let error as URLError {
            throw SteamError.network(error.localizedDescription)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SteamError.network(error.localizedDescription)
        }
    }

    private struct StoreItemsInput: Encodable {
        struct ID: Encodable { let appid: Int }
        struct Context: Encodable { let language = "english"; let country_code = "US" }
        struct DataRequest: Encodable { let include_assets = true }
        let ids: [ID]
        let context = Context()
        let data_request = DataRequest()
    }

    static func storeItemsInputJSON(appIDs: [Int]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(StoreItemsInput(ids: appIDs.map { .init(appid: $0) }))
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Pure parsers (unit-tested)

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw SteamError.decoding(String(describing: type)) }
    }

    static func parseVanity(_ data: Data) throws -> String {
        let env = try decode(ResolveVanityEnvelope.self, from: data)
        guard env.response.success == 1, let id = env.response.steamid else { throw SteamError.vanityNotFound }
        return id
    }

    static func parseSummaries(_ data: Data) throws -> PlayerSummary {
        let env = try decode(PlayerSummariesEnvelope.self, from: data)
        guard let first = env.response.players.first else { throw SteamError.profileNotFound }
        return first
    }

    static func parseOwnedGames(_ data: Data) throws -> [OwnedGame] {
        let env = try decode(OwnedGamesEnvelope.self, from: data)
        if env.response.games == nil && env.response.game_count == nil { throw SteamError.gameDetailsPrivate }
        return env.response.games ?? []
    }

    static func parseAchievements(_ data: Data, status: Int) throws -> AchievementSummary {
        guard let env = try? JSONDecoder().decode(PlayerStatsEnvelope.self, from: data) else {
            try checkStatus(status)
            throw SteamError.decoding("PlayerStatsEnvelope")
        }
        let stats = env.playerstats
        if !stats.success {
            let message = stats.error ?? "unknown error"
            let lower = message.lowercased()
            if lower.contains("not public") { throw SteamError.privateProfile }
            if lower.contains("no stats") { throw SteamError.noStats }
            throw SteamError.steam(message)
        }
        try checkStatus(status)
        let list = stats.achievements ?? []
        return AchievementSummary(earned: list.filter { $0.achieved == 1 }.count, total: list.count)
    }

    static func parseStoreItems(_ data: Data) throws -> [Int: StoreAssets] {
        let env = try decode(StoreItemsEnvelope.self, from: data)
        var result: [Int: StoreAssets] = [:]
        for item in env.response.store_items ?? [] where item.success == 1 {
            if let assets = item.assets { result[item.id] = assets }
        }
        return result
    }

    static func checkStatus(_ status: Int) throws {
        switch status {
        case 200..<300: return
        case 401, 403: throw SteamError.invalidKey
        case 429: throw SteamError.rateLimited
        default: throw SteamError.http(status)
        }
    }
}
