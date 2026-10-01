import Foundation

/// What the Shelf-Keeper writes for one game (docs/PERSONALIZER.md §5).
struct KeeperNotes: Codable, Sendable, Equatable {
    var tagline: String        // ≤ 6 words, for the back of the box under the title
    var blurb: String          // ≤ 160 characters, one line for the back of the box
    var observations: [String] // 4–6, each ≤ 35 words, from the whole history
    var playstyle: String      // 2–3 sentences about the most recent save
}

enum KeeperError: Error, Equatable {
    case refused, truncated, invalidKey, rateLimited, overloaded, network, malformed, notConfigured
    case http(Int, String?)

    var userMessage: String {
        switch self {
        case .refused: "The model declined to write about this one."
        case .truncated: "The notes ran too long and were cut off. Try again."
        case .invalidKey: "The AI service rejected the API key. Check it in Settings."
        case .rateLimited: "The AI service is rate-limiting this key. Try again in a minute."
        case .overloaded: "The AI service is busy right now. Try again shortly."
        case .network: "Couldn't reach the AI service. Check your connection and the address in Settings."
        case .malformed: "The Shelf-Keeper's reply wasn't readable. Try again, or pick a more capable model."
        case .notConfigured: "Choose an AI service and a model in Settings first."
        case .http(let status, let message):
            if let message, !message.isEmpty { "The AI service returned an error (\(status)): \(message)" } else { "The AI service returned an error (\(status))." }
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

    func notes(game: String, digest: GameDigest, key: String, config: AIConfig = .default) async throws -> KeeperNotes {
        guard !config.model.isEmpty, config.base != nil else { throw KeeperError.notConfigured }
        switch config.wire {
        case .anthropic:
            let request = try Self.makeRequest(game: game, digest: digest, key: key, model: config.model)
            let (data, status) = try await send(request)
            return try Self.parse(data, status: status)
        case .openAICompatible:
            let request = try Self.makeChatRequest(game: game, digest: digest, key: key, config: config, jsonMode: true)
            var (data, status) = try await send(request)
            if status == 400 || status == 422 {
                // Some compatible servers reject `response_format`; the prompt alone still asks for JSON.
                let plain = try Self.makeChatRequest(game: game, digest: digest, key: key, config: config, jsonMode: false)
                (data, status) = try await send(plain)
            }
            return try Self.parseChat(data, status: status)
        }
    }

    /// Model ids the service offers, for the picker in Settings.
    func models(key: String, config: AIConfig) async throws -> [String] {
        let request = try Self.makeModelsRequest(key: key, config: config)
        let (data, status) = try await send(request)
        return try Self.parseModels(data, status: status)
    }

    private func send(_ request: URLRequest) async throws -> (Data, Int) {
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch is URLError { throw KeeperError.network }
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw KeeperError.network }
        return (data, status)
    }

    // MARK: Pure helpers

    static func makeRequest(game: String, digest: GameDigest, key: String, model: String = ShelfKeeperAI.model) throws -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 180)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if supportsDefaultFallbacks(model) { request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta") }
        request.httpBody = try requestBody(game: game, digest: digest, model: model)
        return request
    }

    /// `fallbacks: "default"` exists on the current top models only.
    static func supportsDefaultFallbacks(_ model: String) -> Bool {
        ["claude-opus-5-5", "claude-opus-5", "claude-fable-5-1", "claude-sonnet-5-5"].contains(model)
    }

    /// `output_config.effort` is rejected by older and smaller models (Haiku 4.5, Sonnet 4.5 and earlier).
    static func supportsEffort(_ model: String) -> Bool {
        ["claude-opus-5", "claude-sonnet-5", "claude-fable-5", "claude-mythos-5", "claude-opus-4-6", "claude-opus-4-7",
         "claude-opus-4-8", "claude-sonnet-4-6"].contains { model.hasPrefix($0) }
    }

    static func requestBody(game: String, digest: GameDigest, model: String = ShelfKeeperAI.model) throws -> Data {
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
        var outputConfig: [String: Any] = ["format": ["type": "json_schema", "schema": schema] as [String: Any]]
        if supportsEffort(model) { outputConfig["effort"] = "medium" }
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "output_config": outputConfig,
            "system": systemPrompt,
            "messages": [["role": "user", "content": userPrompt(game: game, digest: digest)]],
        ]
        if supportsDefaultFallbacks(model) { body["fallbacks"] = "default" }
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

    // MARK: OpenAI-compatible chat completions (OpenAI, Gemini, OpenRouter, Groq, Mistral, xAI, Ollama, custom)

    /// Appended to the system prompt for services without schema-constrained output.
    static let jsonInstruction = " Reply with a single JSON object and nothing else, with exactly these keys: "
        + "\"tagline\" (string), \"blurb\" (string), \"observations\" (array of strings), \"playstyle\" (string)."

    private static func authorize(_ request: inout URLRequest, key: String, wire: AIWire) {
        switch wire {
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .openAICompatible:
            if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        }
    }

    static func makeChatRequest(game: String, digest: GameDigest, key: String, config: AIConfig, jsonMode: Bool) throws -> URLRequest {
        guard let base = config.base, !config.model.isEmpty else { throw KeeperError.notConfigured }
        var request = URLRequest(url: base.appending(path: "chat/completions"), timeoutInterval: 180)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        authorize(&request, key: key, wire: .openAICompatible)
        // No max-token or sampling fields: their names and limits differ between services.
        var body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": systemPrompt + jsonInstruction],
                ["role": "user", "content": userPrompt(game: game, digest: digest)],
            ],
        ]
        if jsonMode { body["response_format"] = ["type": "json_object"] }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
        return request
    }

    static func parseChat(_ data: Data, status: Int) throws -> KeeperNotes {
        try throwIfHTTPError(data, status: status)
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let choice = (root["choices"] as? [[String: Any]])?.first else { throw KeeperError.malformed }
        switch choice["finish_reason"] as? String {
        case "length": throw KeeperError.truncated
        case "content_filter": throw KeeperError.refused
        default: break
        }
        let message = choice["message"] as? [String: Any]
        let text: String
        if let s = message?["content"] as? String { text = s }
        else if let parts = message?["content"] as? [[String: Any]] { text = parts.compactMap { $0["text"] as? String }.joined() }
        else if message?["refusal"] is String { throw KeeperError.refused }
        else { throw KeeperError.malformed }
        return try decodeNotes(fromText: text)
    }

    /// Finds the JSON object in a reply that may be wrapped in prose or a code fence.
    static func decodeNotes(fromText text: String) throws -> KeeperNotes {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let json = String(text[start...end]).data(using: .utf8),
              var notes = try? JSONDecoder().decode(KeeperNotes.self, from: json) else { throw KeeperError.malformed }
        notes.tagline = notes.tagline.trimmingCharacters(in: .whitespacesAndNewlines)
        notes.blurb = notes.blurb.trimmingCharacters(in: .whitespacesAndNewlines)
        notes.playstyle = notes.playstyle.trimmingCharacters(in: .whitespacesAndNewlines)
        notes.observations = notes.observations.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !notes.blurb.isEmpty, !notes.observations.isEmpty else { throw KeeperError.malformed }
        return notes
    }

    static func throwIfHTTPError(_ data: Data, status: Int) throws {
        guard !(200..<300).contains(status) else { return }
        switch status {
        case 401, 403: throw KeeperError.invalidKey
        case 429: throw KeeperError.rateLimited
        case 529, 500...599: throw KeeperError.overloaded
        default:
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = (root?["error"] as? [String: Any])?["message"] as? String ?? root?["error"] as? String ?? root?["message"] as? String
            throw KeeperError.http(status, message)
        }
    }

    // MARK: Model list

    static func makeModelsRequest(key: String, config: AIConfig) throws -> URLRequest {
        guard let base = config.base else { throw KeeperError.notConfigured }
        var request = URLRequest(url: base.appending(path: "models"), timeoutInterval: 30)
        request.httpMethod = "GET"
        authorize(&request, key: key, wire: config.wire)
        return request
    }

    /// Both wire formats answer `{"data": [{"id": …}, …]}`; ids are returned sorted, without a `models/` prefix.
    static func parseModels(_ data: Data, status: Int) throws -> [String] {
        try throwIfHTTPError(data, status: status)
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = root["data"] as? [[String: Any]] else { throw KeeperError.malformed }
        let ids = list.compactMap { $0["id"] as? String }.map { $0.hasPrefix("models/") ? String($0.dropFirst(7)) : $0 }
        return Array(Set(ids)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
