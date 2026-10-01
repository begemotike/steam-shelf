import Foundation

/// What the Shelf-Keeper writes for one game (docs/PERSONALIZER.md §5).
struct KeeperNotes: Codable, Sendable, Equatable {
    var tagline: String        // ≤ 6 words, for the back of the box under the title
    var blurb: String          // ≤ 160 characters, one line for the back of the box
    var observations: [String] // 4–6, each ≤ 35 words, from the whole history
    var playstyle: String      // 2–3 sentences about the most recent save
}

enum KeeperError: Error, Equatable {
    case refused, truncated, invalidKey, rateLimited, overloaded, network, malformed
    case http(Int, String?)

    var userMessage: String {
        switch self {
        case .refused: "The model declined to write about this one."
        case .truncated: "The notes ran too long and were cut off. Try again."
        case .invalidKey: "Anthropic rejected the API key. Check it in Settings."
        case .rateLimited: "Anthropic is rate-limiting this key. Try again in a minute."
        case .overloaded: "Anthropic is busy right now. Try again shortly."
        case .network: "Couldn't reach Anthropic. Check your connection."
        case .malformed: "The Shelf-Keeper's reply wasn't readable. Try again."
        case .http(let status, let message):
            if let message, !message.isEmpty { "Anthropic returned an error (\(status)): \(message)" } else { "Anthropic returned an error (\(status))." }
        }
    }
}

actor ShelfKeeperAI {
    static let model = "claude-opus-5-5"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    static let systemPrompt = "You are the Shelf-Keeper, the dry, fond curator of a collector's wooden game shelf. "
        + "You have been handed a log extracted from the owner's own save files for one game, and you write the little notes that go with the box. "
        + "Be funny the way a friend who has watched them play is funny: specific, observant, affectionate, never mean. "
        + "Every claim must come from the log; quote save names, dates, playtimes and counts exactly and do not invent events. "
        + "The log uses the game's internal quest and dialogue names; translate them into what a player would recognise, "
        + "and do not reveal story beyond what the log shows the player has already reached. "
        + "Plain text only: no markdown, no emoji, no lists inside a field."

    static func userPrompt(game: String, digest: GameDigest) -> String {
        """
        Game: \(game)

        == SAVE HISTORY ==
        \(digest.history)

        == MOST RECENT SAVE ==
        \(digest.latest)

        Write:
        - tagline: six words or fewer, for under the title on the back of the box.
        - blurb: one sentence, 160 characters or fewer, the single best observation, for the back of the box.
        - observations: four to six observations drawn from the whole save history. One or two sentences each. Look for
          patterns over time: long gaps, reloads (playtime going backwards), save names the player typed themselves,
          late-night sessions, who is always or never in the party.
        - playstyle: two or three sentences about how this person plays, based on the most recent save's quests,
          conversations and dice rolls.
        """
    }

    private let session: URLSession

    init() {
        session = URLSession(configuration: .ephemeral)
    }

    func notes(game: String, digest: GameDigest, key: String) async throws -> KeeperNotes {
        let request = try Self.makeRequest(game: game, digest: digest, key: key)
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch is URLError { throw KeeperError.network }
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw KeeperError.network }
        return try Self.parse(data, status: status)
    }

    // MARK: Pure helpers

    static func makeRequest(game: String, digest: GameDigest, key: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 180)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try requestBody(game: game, digest: digest)
        return request
    }

    static func requestBody(game: String, digest: GameDigest) throws -> Data {
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["tagline", "blurb", "observations", "playstyle"],
            "properties": [
                "tagline": ["type": "string"],
                "blurb": ["type": "string"],
                "observations": ["type": "array", "items": ["type": "string"]],
                "playstyle": ["type": "string"],
            ] as [String: Any],
        ]
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "fallbacks": "default",
            "output_config": [
                "effort": "medium",
                "format": ["type": "json_schema", "schema": schema] as [String: Any],
            ] as [String: Any],
            "system": systemPrompt,
            "messages": [["role": "user", "content": userPrompt(game: game, digest: digest)]],
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    static func parse(_ data: Data, status: Int) throws -> KeeperNotes {
        guard (200..<300).contains(status) else {
            switch status {
            case 401: throw KeeperError.invalidKey
            case 429: throw KeeperError.rateLimited
            case 529, 500...599: throw KeeperError.overloaded
            default:
                let message = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
                    .flatMap { $0["error"] as? [String: Any] }.flatMap { $0["message"] as? String }
                throw KeeperError.http(status, message)
            }
        }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw KeeperError.malformed }
        switch root["stop_reason"] as? String {
        case "refusal": throw KeeperError.refused
        case "max_tokens": throw KeeperError.truncated
        default: break
        }
        let blocks = root["content"] as? [[String: Any]] ?? []
        let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
        guard let json = text.data(using: .utf8), var notes = try? JSONDecoder().decode(KeeperNotes.self, from: json) else {
            throw KeeperError.malformed
        }
        notes.tagline = notes.tagline.trimmingCharacters(in: .whitespacesAndNewlines)
        notes.blurb = notes.blurb.trimmingCharacters(in: .whitespacesAndNewlines)
        notes.playstyle = notes.playstyle.trimmingCharacters(in: .whitespacesAndNewlines)
        notes.observations = notes.observations
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return notes
    }
}
