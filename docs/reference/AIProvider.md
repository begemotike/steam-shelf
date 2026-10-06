# AIProvider

Path: [`Sources/Personalizer/AIProvider.swift`](../../Sources/Personalizer/AIProvider.swift) (101 lines)

Describes which AI services the Shelf-Keeper can use and what the user has chosen. There are two wire formats: Anthropic's Messages API, and OpenAI-compatible chat completions, which almost every other service offers. Presets plus a custom base URL cover the field. `AIConfig` is the user's persisted choice (service, endpoint, model); keys are *not* part of it and live in the Keychain.

## Depends on / used by

- Depends on: Foundation.
- Used by: [AppModel](AppModel.md) (`aiConfig`, `selectAIProvider`, `saveAIKey`, `aiReady`), [ShelfKeeperAI](ShelfKeeperAI.md) (wire, base, model), [SettingsView](SettingsView.md) (picker, address field), [Keychain](Keychain.md) (provider ids select accounts), [Tests](Tests.md) (`AIProviderTests`).

## Types

### `AIWire`

`enum AIWire: String, Codable, Sendable { anthropic, openAICompatible }`.

### `AIProviderPreset`

`struct AIProviderPreset: Identifiable, Sendable, Equatable`

| Field | Meaning |
|---|---|
| `id`, `name` | Stable key (also the Keychain suffix) and display name. |
| `wire` | `AIWire`. |
| `baseURL` | Endpoint root (for example `https://api.openai.com/v1`). |
| `keyURL` | Where to get a key (`nil` for local/custom). |
| `needsKey` | Whether a key is required. |
| `defaultModel` | Preselected model; `nil` means "pick from the list the service returns". Only Anthropic has one (`claude-sonnet-5-5`). |
| `keyPrefixes` | Prefixes that identify the service when a key is pasted; longest match wins. |
| `editableBaseURL` | Whether Settings shows an Address field (Ollama and custom). |

### `AIProviders`

`enum AIProviders` with `static let all`, `fallback` (the first, Anthropic), `preset(_ id:)` (falls back to Anthropic for an unknown id) and `detect(fromKey:)`.

Preset table (from source):

| id | Name | Wire | Base URL | Key needed | Key prefixes | Editable URL |
|---|---|---|---|---|---|---|
| `anthropic` | Anthropic (Claude) | anthropic | `https://api.anthropic.com/v1` | yes | `sk-ant-` | no |
| `openai` | OpenAI | openAICompatible | `https://api.openai.com/v1` | yes | `sk-proj-`, `sk-` | no |
| `gemini` | Google Gemini | openAICompatible | `https://generativelanguage.googleapis.com/v1beta/openai` | yes | `AIza` | no |
| `openrouter` | OpenRouter | openAICompatible | `https://openrouter.ai/api/v1` | yes | `sk-or-` | no |
| `groq` | Groq | openAICompatible | `https://api.groq.com/openai/v1` | yes | `gsk_` | no |
| `mistral` | Mistral | openAICompatible | `https://api.mistral.ai/v1` | yes | none | no |
| `xai` | xAI (Grok) | openAICompatible | `https://api.x.ai/v1` | yes | `xai-` | no |
| `ollama` | Ollama (on this Mac) | openAICompatible | `http://localhost:11434/v1` | no | none | yes |
| `custom` | Other (OpenAI-compatible) | openAICompatible | empty | no | none | yes |

`detect(fromKey:)` trims the key and returns the preset with the longest matching prefix (so `sk-ant-` and `sk-or-` beat OpenAI's plain `sk-`), or `nil` when nothing matches (for example Mistral keys, which have no distinctive prefix).

### `AIConfig`

`struct AIConfig: Codable, Sendable, Equatable { providerID, baseURL, model }`

| Member | Behaviour |
|---|---|
| `static let default` | `AIConfig(preset: AIProviders.fallback)` (Anthropic, Sonnet 5.5). |
| `init(providerID:baseURL:model:)`, `init(preset:)` | Preset init takes the preset's base URL and default model (or empty). |
| `preset`, `wire` | Looked up from `providerID`. |
| `base: URL?` | Validated endpoint root: trims whitespace and trailing slashes; requires a scheme and host; `https` accepted anywhere; plain `http` accepted only for `localhost`, `127.0.0.1` or `::1`. Otherwise `nil` (the UI shows "Use an https address..."). |
| `contentProviderID: String` | `"ai.<providerID>.<model>"`, stored on the notes so a shelf records what wrote them. |

## Gotchas

- For the Anthropic wire, `base` is only validated for non-nil; `ShelfKeeperAI.makeRequest` posts to the hard-coded `https://api.anthropic.com/v1/messages`, while `makeModelsRequest` *does* use `base`. Changing the Anthropic base URL is not possible in the UI (not editable), so the two never disagree in practice.
- Plain-http local access also requires the `NSAllowsLocalNetworking` ATS key in `Info.plist` (see [Distribution](../architecture/distribution.md)).
- The older stored `providerID` values `anthropic.<model>` (content provider ids from before multi-service support) are still recognised by `BackOfBoxContent.isAIWritten`.

## See also

[AI writer](../architecture/ai-writer.md), [Distribution](../architecture/distribution.md), [Open questions: Any AI service](../decisions/OPEN_QUESTIONS.md#any-ai-service-2026-10-01).
