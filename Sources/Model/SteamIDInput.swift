import Foundation

enum SteamIDInput: Equatable, Sendable {
    case steamID64(String)
    case vanity(String)

    static func parse(_ raw: String) -> SteamIDInput? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if s.isEmpty { return nil }

        if isSteamID64(s) { return .steamID64(s) }

        let lower = s.lowercased()
        for prefix in ["https://steamcommunity.com/", "http://steamcommunity.com/", "steamcommunity.com/",
                       "https://www.steamcommunity.com/", "http://www.steamcommunity.com/"] where lower.hasPrefix(prefix) {
            let rest = String(s.dropFirst(prefix.count))
            if rest.lowercased().hasPrefix("profiles/") {
                let id = String(rest.dropFirst("profiles/".count))
                return isSteamID64(id) ? .steamID64(id) : nil
            }
            if rest.lowercased().hasPrefix("id/") {
                let name = String(rest.dropFirst("id/".count))
                return isVanity(name) ? .vanity(name) : nil
            }
            return nil
        }
        return isVanity(s) ? .vanity(s) : nil
    }

    private static func isSteamID64(_ s: String) -> Bool {
        s.count == 17 && s.hasPrefix("7656119") && s.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func isVanity(_ s: String) -> Bool {
        guard (2...32).contains(s.count) else { return false }
        // All-digit strings are malformed SteamID64s (e.g. 16 digits), not custom URLs.
        if s.allSatisfy({ $0.isASCII && $0.isNumber }) { return false }
        return s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }
}
