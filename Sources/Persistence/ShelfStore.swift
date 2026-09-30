import Foundation
import SwiftData

@Model final class ShelfRecord {
    @Attribute(.unique) var shelfID: UUID
    var kindRaw: String
    var updatedAt: Date
    var documentData: Data

    init(shelfID: UUID, kindRaw: String, updatedAt: Date, documentData: Data) {
        self.shelfID = shelfID
        self.kindRaw = kindRaw
        self.updatedAt = updatedAt
        self.documentData = documentData
    }
}

@MainActor protocol ShelfSource: AnyObject {
    var sourceID: String { get }
    var isEditable: Bool { get }
    func load() throws -> ShelfDocument?
    func save(_ document: ShelfDocument) throws
}

@MainActor final class LocalShelfSource: ShelfSource {
    let sourceID = "local"
    let isEditable = true
    private let context: ModelContext

    init(container: ModelContainer) {
        self.context = container.mainContext
    }

    private func localRecord() throws -> ShelfRecord? {
        let kind = "local"
        var descriptor = FetchDescriptor<ShelfRecord>(predicate: #Predicate { $0.kindRaw == kind })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func load() throws -> ShelfDocument? {
        guard let record = try localRecord() else { return nil }
        return try ShelfDocumentCodec.decode(record.documentData)
    }

    func save(_ document: ShelfDocument) throws {
        let data = try ShelfDocumentCodec.encode(document)
        if let record = try localRecord() {
            record.shelfID = document.id
            record.updatedAt = document.updatedAt
            record.documentData = data
        } else {
            context.insert(ShelfRecord(shelfID: document.id, kindRaw: "local", updatedAt: document.updatedAt, documentData: data))
        }
        try context.save()
    }
}

@MainActor final class DemoShelfSource: ShelfSource {
    let sourceID = "demo"
    let isEditable = true
    private var stored: ShelfDocument?

    init(document: ShelfDocument? = nil) { stored = document }

    func load() throws -> ShelfDocument? { stored }
    func save(_ document: ShelfDocument) throws { stored = document }
}
