import Foundation

/// The two wire formats the Shelf-Keeper speaks. Almost every service other than Anthropic offers an
/// OpenAI-compatible chat-completions endpoint, so two formats plus a custom base URL cover the field.
enum AIWire: String, Codable, Sendable { case anthropic, openAICompatible }

struct AIProviderPreset: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let wire: AIWire
    let baseURL: String
    /// Where to get a key (nil for local/custom).
    let keyURL: String?
    let needsKey: Bool
    /// Preselected model; nil means "pick one from the list the service returns".
    let defaultModel: String?
    /// Key prefixes that identify this service when a key is pasted. Longest match wins.
    let keyPrefixes: [String]
    /// Whether the user edits the base URL (custom endpoints and local servers).
    let editableBaseURL: Bool
}

enum AIProviders {
    static let all: [AIProviderPreset] = [
        .init(id: "anthropic", name: "Anthropic (Claude)", wire: .anthropic, baseURL: "https://api.anthropic.com/v1",
              keyURL: "https://console.anthropic.com/", needsKey: true, defaultModel: "claude-opus-5-5",
              keyPrefixes: ["sk-ant-"], editableBaseURL: false),
        .init(id: "openai", name: "OpenAI", wire: .openAICompatible, baseURL: "https://api.openai.com/v1",
              keyURL: "https://platform.openai.com/api-keys", needsKey: true, defaultModel: nil,
              keyPrefixes: ["sk-proj-", "sk-"], editableBaseURL: false),
        .init(id: "gemini", name: "Google Gemini", wire: .openAICompatible,
              baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
              keyURL: "https://aistudio.google.com/apikey", needsKey: true, defaultModel: nil,
              keyPrefixes: ["AIza"], editableBaseURL: false),
        .init(id: "openrouter", name: "OpenRouter", wire: .openAICompatible, baseURL: "https://openrouter.ai/api/v1",
              keyURL: "https://openrouter.ai/keys", needsKey: true, defaultModel: nil,
              keyPrefixes: ["sk-or-"], editableBaseURL: false),
        .init(id: "groq", name: "Groq", wire: .openAICompatible, baseURL: "https://api.groq.com/openai/v1",
              keyURL: "https://console.groq.com/keys", needsKey: true, defaultModel: nil,
              keyPrefixes: ["gsk_"], editableBaseURL: false),
        .init(id: "mistral", name: "Mistral", wire: .openAICompatible, baseURL: "https://api.mistral.ai/v1",
              keyURL: "https://console.mistral.ai/api-keys", needsKey: true, defaultModel: nil,
              keyPrefixes: [], editableBaseURL: false),
        .init(id: "xai", name: "xAI (Grok)", wire: .openAICompatible, baseURL: "https://api.x.ai/v1",
              keyURL: "https://console.x.ai/", needsKey: true, defaultModel: nil,
              keyPrefixes: ["xai-"], editableBaseURL: false),
        .init(id: "ollama", name: "Ollama (on this Mac)", wire: .openAICompatible, baseURL: "http://localhost:11434/v1",
              keyURL: nil, needsKey: false, defaultModel: nil, keyPrefixes: [], editableBaseURL: true),
        .init(id: "custom", name: "Other (OpenAI-compatible)", wire: .openAICompatible, baseURL: "",
              keyURL: nil, needsKey: false, defaultModel: nil, keyPrefixes: [], editableBaseURL: true),
    ]

    static let fallback = all[0]

    static func preset(_ id: String) -> AIProviderPreset { all.first { $0.id == id } ?? fallback }

    /// The service a pasted key belongs to, judged by its prefix (longest prefix wins, so `sk-ant-` and
    /// `sk-or-` beat OpenAI's plain `sk-`). nil when the key gives no hint.
    static func detect(fromKey key: String) -> AIProviderPreset? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        var best: (preset: AIProviderPreset, length: Int)?
        for preset in all {
            for prefix in preset.keyPrefixes where trimmed.hasPrefix(prefix) && prefix.count > (best?.length ?? 0) {
                best = (preset, prefix.count)
            }
        }
        return best?.preset
    }
}

/// The user's current choice of service, endpoint and model (persisted in UserDefaults; keys live in the Keychain).
struct AIConfig: Codable, Sendable, Equatable {
    var providerID: String
    var baseURL: String
    var model: String

    static let `default` = AIConfig(preset: AIProviders.fallback)

    init(providerID: String, baseURL: String, model: String) {
        self.providerID = providerID; self.baseURL = baseURL; self.model = model
    }

    init(preset: AIProviderPreset) {
        self.init(providerID: preset.id, baseURL: preset.baseURL, model: preset.defaultModel ?? "")
    }

    var preset: AIProviderPreset { AIProviders.preset(providerID) }
    var wire: AIWire { preset.wire }

    /// The validated endpoint root, without a trailing slash. Plain http is allowed only for this Mac.
    var base: URL? {
        let text = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return nil }
        if scheme == "https" { return url }
        if scheme == "http", ["localhost", "127.0.0.1", "::1"].contains(host) { return url }
        return nil
    }

    /// Stored with the notes so a shelf records what wrote them.
    var contentProviderID: String { "ai.\(providerID).\(model)" }
}
