import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@main struct SteamShelfApp: App {
    @State private var appModel: AppModel
    let container: ModelContainer

    init() {
        let mode: LaunchMode = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ? .tests : .normal
        // `--demo` is a normal launch that merely starts on the demo shelf; Settings and Leave Demo work as usual.
        let startDemo = CommandLine.arguments.contains("--demo")

        let container: ModelContainer
        do {
            container = try ModelContainer(for: ShelfRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: mode != .normal))
        } catch {
            fatalError("Could not create the SwiftData container: \(error)")
        }
        self.container = container
        _appModel = State(initialValue: AppModel(mode: mode, container: container, startDemo: startDemo))
        if mode == .normal { _ = Updater.shared }   // starts the scheduled update check
    }

    var body: some Scene {
        Window("Steam Shelf", id: "shelf") {
            ShelfView().environment(appModel)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: Theme.Metrics.windowDefaultW, height: Theme.Metrics.windowDefaultH)
        .windowResizability(.contentMinSize)
        .commands {
            UpdateCommands()
            ShelfCommands(model: appModel)
        }

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
            Divider()
            Button("Export Shelf…") { model.beginExport() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Import Shelf…") { model.beginImport() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
        }
        CommandMenu("Shelf") {
            Button("Next Page") { model.go(to: model.pageIndex + 1) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("Previous Page") { model.go(to: model.pageIndex - 1) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
        }
    }
}

extension UTType {
    static let steamShelf = UTType(exportedAs: "net.outofajam.steamshelf")
}

/// FileDocument wrapper around the shareable JSON produced by `ShelfDocumentCodec`.
struct ShelfFile: FileDocument {
    static let readableContentTypes = [UTType.steamShelf]
    static let writableContentTypes = [UTType.steamShelf]

    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
