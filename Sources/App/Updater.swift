import SwiftUI
import Sparkle

/// Thin wrapper around Sparkle's standard updater. Automatic checks run once a day (Info.plist
/// `SUScheduledCheckInterval`); the menu item triggers a manual check with Sparkle's own UI.
@MainActor final class Updater {
    static let shared = Updater()
    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    func checkForUpdates() { controller.checkForUpdates(nil) }
}

struct UpdateCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { Updater.shared.checkForUpdates() }
        }
    }
}
