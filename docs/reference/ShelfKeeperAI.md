# ShelfKeeperAI

Path: [`Sources/Personalizer/ShelfKeeperAI.swift`](../../Sources/Personalizer/ShelfKeeperAI.swift) (305 lines)

The client that turns a `GameDigest` into `KeeperNotes` by calling an AI service. It owns the prompts, builds requests for the two wire formats (Anthropic Messages API and OpenAI-compatible chat completions), lists a service's models, parses replies tolerantly and maps every failure to a `KeeperError` with user-facing copy. Request building and response parsing are pure `static` functions so they are covered by offline tests; the actor itself only owns an ephemeral `URLSession`. The full prompt text is quoted in [AI writer](../architecture/ai-writer.md#the-prompts-verbatim).

## Depends on / used by

- Depends on: [AIProvider](AIProvider.md) (`AIConfig`, `AIWire`), [GamePersonalizer](GamePersonalizer.md) (`GameDigest`).
- Used by: [AppModel](AppModel.md) (`keeperAI`: `notes`, `models`), [KeeperNotesPanel](KeeperNotesPanel.md) indirectly through `KeeperError.userMessage`, [Tests](Tests.md) (`ShelfKeeperAITests`, `AIProviderTests`).

## Types

### `KeeperNotes`

`struct KeeperNotes: Codable, Sendable, Equatable`: `tagline` (at most six words), `blurb` (at most 160 characters), `observations: [String]` (4 to 6, each at most 35 words), `playstyle` (2 to 3 sentences about the most recent save; the model is asked for 3 to 4). These limits are *requests in the prompt*, not enforced by the app. The model's `drafts` array is part of the schema but is not a field of `KeeperNotes`: decoding ignores it, so drafts are discarded.

### `KeeperError`

`enum KeeperError: Error, Equatable { refused, truncated, invalidKey, rateLimited, overloaded, network, malformed, notConfigured, http(Int, String?) }`

| Case | `userMessage` | Raised when |
|---|---|---|
| `refused` | "The model declined to write about this one." | Anthropic `stop_reason == "refusal"`; chat `finish_reason == "content_filter"` or a `refusal` string in the message |
| `truncated` | "The notes ran too long and were cut off. Try again." | `stop_reason == "max_tokens"`; chat `finish_reason == "length"` |
| `invalidKey` | "The AI service rejected the API key. Check it in Settings." | HTTP 401 (Anthropic path) or 401/403 (chat and models) |
| `rateLimited` | "The AI service is rate-limiting this key. Try again in a minute." | 429 |
| `overloaded` | "The AI service is busy right now. Try again shortly." | 529 or any 5xx |
| `network` | "Couldn't reach the AI service. Check your connection and the address in Settings." | `URLError` (other than cancel) or a non-HTTP response |
| `malformed` | "The Shelf-Keeper's reply wasn't readable. Try again, or pick a more capable model." | Unparseable JSON, missing fields; chat reply without a blurb or observations |
| `notConfigured` | "Choose an AI service and a model in Settings first." | Empty model or invalid base URL |
| `http(status, message)` | "The AI service returned an error (status): message" (or without message) | Any other non-2xx; message pulled from the error JSON when present |

## `ShelfKeeperAI`

`actor ShelfKeeperAI`; `static let model = "claude-sonnet-5-5"`; `static let endpoint = URL("https://api.anthropic.com/v1/messages")`; private `session = URLSession(configuration: .ephemeral)` (no cookies, no disk cache).

### Instance methods

| Signature | Behaviour |
|---|---|
| `func notes(game: String, digest: GameDigest, key: String, config: AIConfig = .default) async throws -> KeeperNotes` | Throws `notConfigured` if the model is empty or `config.base` is nil. `.anthropic`: `makeRequest` then `parse`. `.openAICompatible`: `makeChatRequest(jsonMode: true)`; if the status is 400 or 422 it retries once with `jsonMode: false` (some servers reject `response_format`; the prompt alone still asks for JSON); then `parseChat`. |
| `func models(key: String, config: AIConfig) async throws -> [String]` | `makeModelsRequest` then `parseModels`. |
| `private func send(_ request: URLRequest) async throws -> (Data, Int)` | Maps cancellation (`CancellationError` or `URLError.cancelled`) to `CancellationError`, other `URLError` to `KeeperError.network`. Returns the HTTP status. |

### Anthropic wire (static, pure)

| Signature | Behaviour |
|---|---|
| `static func makeRequest(game:digest:key:model:) throws -> URLRequest` | POST to `endpoint`, timeout 180 s, headers `content-type: application/json`, `x-api-key`, `anthropic-version: 2023-06-01`, and `anthropic-beta: server-side-fallback-2026-07-01` only when `supportsDefaultFallbacks(model)`. |
| `static func supportsDefaultFallbacks(_ model: String) -> Bool` | Exact match in `claude-opus-5-5`, `claude-opus-5`, `claude-fable-5-1`, `claude-sonnet-5-5`. |
| `static func supportsEffort(_ model: String) -> Bool` | Prefix match against `claude-opus-5`, `claude-sonnet-5`, `claude-fable-5`, `claude-mythos-5`, `claude-opus-4-6`, `claude-opus-4-7`, `claude-opus-4-8`, `claude-sonnet-4-6` (older/smaller models such as Haiku 4.5 reject `effort`). |
| `static func requestBody(game:digest:model:) throws -> Data` | JSON with sorted keys: `model`, `max_tokens: 16000`, `output_config` (`format` = `json_schema` with a closed schema requiring `drafts`, `tagline`, `blurb`, `observations`, `playstyle`; plus `effort: "medium"` when supported), `system`, `messages` (one user message), and `fallbacks: "default"` when supported. No `thinking`, `temperature`, `top_p` or `top_k`. See [AI writer](../architecture/ai-writer.md#request-bodies) for the exact shape. |
| `static func parse(_ data: Data, status: Int) throws -> KeeperNotes` | Non-2xx: 401 `invalidKey`, 429 `rateLimited`, 529/5xx `overloaded`, other `http(status, error.message)`. Then `stop_reason` `refusal`/`max_tokens` map to errors; text is the concatenation of `content` blocks of `type == "text"` (so thinking blocks are skipped), decoded as `KeeperNotes`; whitespace is trimmed and blank observations are dropped. |

### OpenAI-compatible wire

| Signature | Behaviour |
|---|---|
| `static let jsonInstruction` | Appended to the system prompt: asks for a single JSON object with exactly the five keys. |
| `private static func authorize(_:key:wire:)` | Anthropic: `x-api-key` and `anthropic-version`. Compatible: `Authorization: Bearer <key>` only if the key is non-empty (keyless local servers work). |
| `static func makeChatRequest(game:digest:key:config:jsonMode:) throws -> URLRequest` | POST `<base>/chat/completions`, 180 s. Body: `model`, `messages` (system = prompt + `jsonInstruction`, user = user prompt), and `response_format: {"type": "json_object"}` when `jsonMode`. No max-token or sampling fields (names and limits differ between services). Throws `notConfigured` without base/model. |
| `static func parseChat(_ data: Data, status: Int) throws -> KeeperNotes` | `throwIfHTTPError`; first choice; `finish_reason` `length` gives `truncated`, `content_filter` gives `refused`; content may be a string or an array of `{text}` parts; a `refusal` string gives `refused`; then `decodeNotes(fromText:)`. |
| `static func decodeNotes(fromText:) throws -> KeeperNotes` | Takes the substring from the first `{` to the last `}` (so prose or a code fence around the JSON is tolerated), decodes, trims, and requires a non-empty `blurb` and at least one observation; otherwise `malformed`. |
| `static func throwIfHTTPError(_ data: Data, status: Int) throws` | 2xx passes; 401 and 403 `invalidKey`; 429; 529/5xx; else `http(status, message)` where the message is read from `error.message`, `error` as a string, or `message`. |

### Model list

| Signature | Behaviour |
|---|---|
| `static func makeModelsRequest(key:config:) throws -> URLRequest` | GET `<base>/models`, 30 s, authorised per wire. |
| `static func parseModels(_ data: Data, status: Int) throws -> [String]` | Expects `{"data":[{"id":...}]}` (both wires). Strips a `models/` prefix when present, de-duplicates, sorts with `localizedStandardCompare` (so `alpha-2` precedes `alpha-10`). |

## Isolation

`ShelfKeeperAI` is an `actor`; its static helpers are nonisolated pure functions. `KeeperNotes`, `KeeperError`, `GameDigest` and `AIConfig` are `Sendable` value types, so they cross from the actor to `AppModel` safely.

## Gotchas

- Anthropic requests ignore `config.base` and always go to `api.anthropic.com` (see [AIProvider](AIProvider.md)).
- `max_tokens` is 16000 on Anthropic. The compatible wire sends no limit at all, so truncation behaviour is the service's default.
- A `400`/`422` retry doubles the cost of a failed call on services that reject JSON mode; the second request is identical except for `response_format`.
- The ephemeral session means no connection reuse across notes runs.

## See also

[AI writer](../architecture/ai-writer.md), [App and state](../architecture/app-and-state.md) (`writeNotes`), [Open questions: Sonnet 5.5 default...](../decisions/OPEN_QUESTIONS.md#sonnet-55-default-counted-facts-save-time-zone-2026-10-04).
