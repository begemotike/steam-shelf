import AppKit
import OSLog

private let bookmarkDefaultsKey = "steamFolderBookmark"
private let bookmarkOptions: URL.BookmarkCreationOptions = [.withSecurityScope, .securityScopeAllowOnlyReadAccess]

/// The user's one-time grant of the Steam folder (save files live under `userdata/`, outside the sandbox).
/// The security-scoped bookmark is kept in UserDefaults, not the Keychain: it is not a secret (only this app can use it),
/// this is Apple's documented pattern, and Keychain reads are what cause password prompts.
@MainActor enum SteamFolderAccess {
    private static let log = Logger(subsystem: "net.outofajam.SteamShelf", category: "SteamFolderAccess")

    /// A bookmark exists and resolves.
    static var isGranted: Bool { resolve() != nil }

    /// Shows the folder picker; returns true when a valid Steam folder (one containing `userdata`) was granted.
    static func requestAccess() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = SteamInstalls.steamappsDirectory?.deletingLastPathComponent()
        panel.prompt = "Grant Access"
        panel.message = "Steam Shelf reads your save files here to write notes about your games. Choose the Steam folder."
        guard panel.runModal() == .OK, let url = panel.url else { return false }

        var isDir: ObjCBool = false
        let hasUserdata = FileManager.default.fileExists(atPath: url.appending(path: "userdata").path, isDirectory: &isDir) && isDir.boolValue
        guard hasUserdata else {
            let alert = NSAlert()
            alert.messageText = "That doesn't look like the Steam folder"
            alert.informativeText = "Choose the folder named Steam (it contains a folder called userdata)."
            alert.runModal()
            return false
        }
        do {
            let data = try url.bookmarkData(options: bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: bookmarkDefaultsKey)
            return true
        } catch {
            log.error("Could not create the folder bookmark: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    static func revoke() { UserDefaults.standard.removeObject(forKey: bookmarkDefaultsKey) }

    /// Runs `body` with the security scope open; the scope is always closed afterwards.
    nonisolated static func withAccess<T>(_ body: (URL) throws -> T) throws -> T {
        guard let resolved = resolve() else { throw PersonalizerError.noFolderAccess }
        guard resolved.url.startAccessingSecurityScopedResource() else { throw PersonalizerError.noFolderAccess }
        defer { resolved.url.stopAccessingSecurityScopedResource() }
        if resolved.stale, let fresh = try? resolved.url.bookmarkData(options: bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: bookmarkDefaultsKey)
        }
        return try body(resolved.url)
    }

    nonisolated private static func resolve() -> (url: URL, stale: Bool)? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkDefaultsKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        return (url, stale)
    }
}
