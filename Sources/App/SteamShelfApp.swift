import SwiftUI
import SwiftData

@main struct SteamShelfApp: App {
    @State private var appModel: AppModel
    let container: ModelContainer

    init() {
        let mode: LaunchMode
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { mode = .tests }
        else if CommandLine.arguments.contains("--demo") { mode = .demo }
        else { mode = .normal }

        let container: ModelContainer
        do {
            container = try ModelContainer(for: ShelfRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: mode != .normal))
        } catch {
            fatalError("Could not create the SwiftData container: \(error)")
        }
        self.container = container
        _appModel = State(initialValue: AppModel(mode: mode, container: container))
    }

    var body: some Scene {
        Window("Steam Shelf", id: "shelf") {
            ShelfView().environment(appModel)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: Theme.Metrics.windowDefaultW, height: Theme.Metrics.windowDefaultH)
        .windowResizability(.contentMinSize)
        .commands { ShelfCommands(model: appModel) }

        Settings {
            SettingsView().environment(appModel)
        }
    }
}

struct ShelfCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Refresh Library") { Task { await model.refreshLibrary() } }
                .keyboardShortcut("r", modifiers: .command)
            // Export / Import arrive in B7.
        }
        CommandMenu("Shelf") {
            Button("Next Page") { model.go(to: model.pageIndex + 1) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("Previous Page") { model.go(to: model.pageIndex - 1) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
        }
    }
}
