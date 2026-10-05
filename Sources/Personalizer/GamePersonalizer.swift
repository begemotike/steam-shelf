import Foundation

enum PersonalizerError: Error, Equatable { case noFolderAccess, noSaves, corrupt(String), unsupported(String) }

/// What a personalizer extracts from a game's local saves; the plain-text halves go into the AI prompt.
struct GameDigest: Sendable, Equatable {
    var history: String        // whole-history section of the prompt (plain text)
    var latest: String         // deep dive on the most recent save (plain text)
    var fingerprint: String    // changes when there is something new to say
    var saveCount: Int
}

protocol GamePersonalizer: Sendable {
    var appID: Int { get }
    var displayName: String { get }
    /// `nil` = no saves found. Runs synchronously; call it off the main actor.
    /// `timeZone` is where the saves were played; file dates carry no zone, so a travelling Mac would shift every clock time.
    func digest(steamRoot: URL, timeZone: TimeZone) throws -> GameDigest?
}

enum Personalizers {
    static let all: [any GamePersonalizer] = [BG3Personalizer()]
    static func forApp(_ appID: Int) -> (any GamePersonalizer)? { all.first { $0.appID == appID } }
}
