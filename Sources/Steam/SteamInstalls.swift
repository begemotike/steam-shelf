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

    // MARK: Direct launch

    /// Every `"path"` value in libraryfolders.vdf (the default library plus any on other volumes).
    static func libraryPaths(vdf: String) -> [String] {
        values(forKey: "path", in: vdf).map { $0.replacingOccurrences(of: "\\\\", with: "\\") }
    }

    /// Every `"key"  "value"` pair in a VDF text, regardless of line layout.
    private static func values(forKey key: String, in text: String) -> [String] {
        let pattern = "\"" + NSRegularExpression.escapedPattern(for: key) + "\"\\s*\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }

    /// `"installdir"` from an appmanifest, e.g. "Baldurs Gate 3".
    static func installDir(manifest: String) -> String? {
        values(forKey: "installdir", in: manifest).first
    }

    /// The game's folder under `<library>/steamapps/common/`, searching every library we can read.
    static func installFolder(appID: Int) -> URL? {
        guard let dir = steamappsDirectory,
              let vdf = try? String(contentsOf: dir.appending(path: "libraryfolders.vdf"), encoding: .utf8) else { return nil }
        let fm = FileManager.default
        for lib in libraryPaths(vdf: vdf) {
            let steamapps = URL(fileURLWithPath: lib).appending(path: "steamapps", directoryHint: .isDirectory)
            let manifestURL = steamapps.appending(path: "appmanifest_\(appID).acf")
            guard let manifest = try? String(contentsOf: manifestURL, encoding: .utf8),
                  let name = installDir(manifest: manifest) else { continue }
            let folder = steamapps.appending(path: "common", directoryHint: .isDirectory).appending(path: name, directoryHint: .isDirectory)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue { return folder }
        }
        return nil
    }

    /// Picks the `.app` to run inside a game folder: shallowest first, then the name closest to the
    /// folder's name, then alphabetical. Looks at most three levels deep (Paradox games keep theirs in `binaries/`).
    static func appBundle(inInstallFolder folder: URL, maxDepth: Int = 3) -> URL? {
        let fm = FileManager.default
        var candidates: [(depth: Int, url: URL)] = []
        func walk(_ url: URL, depth: Int) {
            guard depth <= maxDepth,
                  let items = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
            for item in items {
                guard (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                if item.pathExtension == "app" { candidates.append((depth, item)) }
                else if depth < maxDepth { walk(item, depth: depth + 1) }
            }
        }
        walk(folder, depth: 1)
        guard !candidates.isEmpty else { return nil }
        let hint = normalized(folder.lastPathComponent)
        func score(_ url: URL) -> Int {
            let name = normalized(url.deletingPathExtension().lastPathComponent)
            if name == hint { return 0 }
            if hint.contains(name) || name.contains(hint) { return 1 }
            if name.contains("launcher") { return 3 }
            return 2
        }
        return candidates.sorted {
            if $0.depth != $1.depth { return $0.depth < $1.depth }
            let sa = score($0.url), sb = score($1.url)
            if sa != sb { return sa < sb }
            return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
        }.first?.url
    }

    private static func normalized(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// The app bundle to open directly for this game, if we can find one.
    static func launchBundle(appID: Int) -> URL? {
        installFolder(appID: appID).flatMap { appBundle(inInstallFolder: $0) }
    }
}
