import Foundation
import AppKit

/// Which owned games are installed locally, read from the Steam client's `libraryfolders.vdf`.
/// That file lists every library folder (including other volumes) with an `"apps"` block of
/// installed app IDs, so one read covers everything without touching the other folders.
enum SteamInstalls {
    /// The Steam client's support directory in the *real* home (the sandbox container's home is not it).
    static var steamappsDirectory: URL? {
        guard let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: home))
            .appending(path: "Library/Application Support/Steam/steamapps", directoryHint: .isDirectory)
    }

    /// True when a Steam client is registered for `steam://` URLs.
    static var isSteamAvailable: Bool {
        guard let url = URL(string: "steam://") else { return false }
        return NSWorkspace.shared.urlForApplication(toOpen: url) != nil
    }

    /// Installed app IDs, or nil when the manifest can't be read (no Steam, or no file access).
    static func scan() -> Set<Int>? {
        guard let dir = steamappsDirectory,
              let text = try? String(contentsOf: dir.appending(path: "libraryfolders.vdf"), encoding: .utf8) else { return nil }
        return installedAppIDs(vdf: text)
    }

    /// Pure parser: collects the keys of every `"apps" { "<appid>" "<size>" ... }` block.
    static func installedAppIDs(vdf: String) -> Set<Int> {
        var ids = Set<Int>()
        var inApps = false
        var depth = 0
        for rawLine in vdf.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if inApps {
                if line == "{" { depth += 1; continue }
                if line == "}" { depth -= 1; if depth == 0 { inApps = false }; continue }
                // "8930"		"4837870324"
                let parts = line.split(separator: "\"").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                if let first = parts.first, let id = Int(first) { ids.insert(id) }
            } else if line == "\"apps\"" {
                inApps = true; depth = 0
            }
        }
        return ids
    }

    static func launchURL(appID: Int) -> URL? { URL(string: "steam://rungameid/\(appID)") }
}
