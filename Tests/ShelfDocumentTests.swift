import XCTest
import SwiftData
@testable import SteamShelf

final class ShelfDocumentTests: XCTestCase {
    static let t0 = Date(timeIntervalSince1970: 1_780_000_000)   // whole seconds: ISO8601 drops sub-seconds

    static func entry(_ id: Int, _ title: String, shelved: Bool = true, full: Bool = false) -> ShelfEntry {
        ShelfEntry(
            appID: id, title: title, isShelved: shelved,
            rating: full ? 4 : nil,
            note: full ? "Bought it during a sale at 2 a.m. — ça va très bien 🎮" : "",
            purchaseDate: full ? t0 : nil,
            firstSeenAt: t0,
            stats: CachedSteamStats(
                playtimeMinutes: full ? 1234 : 0, lastPlayed: full ? t0 : nil, hasCommunityStats: full,
                achievementsEarned: full ? 10 : nil, achievementsTotal: full ? 50 : nil,
                achievementsState: full ? .ok : .unknown, fetchedAt: full ? t0 : nil),
            art: ArtRefs(portraitURLs: full ? ["https://example.com/a.jpg"] : [], headerURL: full ? "https://example.com/h.jpg" : nil),
            blurb: full ? BackOfBoxContent(blurb: "Blurb.", tagline: "Tag", providerID: "local.v1", inputFingerprint: "x", generatedAt: t0) : nil)
    }

    static func document() -> ShelfDocument {
        ShelfDocument(id: UUID(), title: "Test Shelf",
                      owner: ShelfOwner(steamID64: "76561198000000000", displayName: "Tester", avatarURL: nil),
                      createdAt: t0, updatedAt: t0,
                      entries: [entry(620, "Portal 2", full: true), entry(10, "Bare", shelved: false)])
    }

    func testRoundTrip() throws {
        let doc = Self.document()
        let data = try ShelfDocumentCodec.encode(doc)
        XCTAssertEqual(try ShelfDocumentCodec.decode(data), doc)
    }

    func testUnsupportedVersionThrows() throws {
        var doc = Self.document()
        doc.version = 2
        let data = try ShelfDocumentCodec.encode(doc)
        XCTAssertThrowsError(try ShelfDocumentCodec.decode(data)) { error in
            XCTAssertEqual(error as? DocumentError, .unsupportedVersion(2))
        }
    }

    func testUnknownKeysIgnored() throws {
        let data = try ShelfDocumentCodec.encode(Self.document())
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        obj["futureField"] = ["a": 1]
        let patched = try JSONSerialization.data(withJSONObject: obj)
        XCTAssertNoThrow(try ShelfDocumentCodec.decode(patched))
    }

    func testForSharingDropsUnshelved() {
        let doc = Self.document()
        XCTAssertEqual(doc.entries.count, 2)
        XCTAssertEqual(doc.forSharing().entries.map(\.appID), [620])
    }

    func testMoveMakesArrangementCustomAndInsertAppends() {
        var doc = Self.document()
        doc.entries = [Self.entry(1, "Alpha"), Self.entry(2, "Beta"), Self.entry(3, "Gamma")]
        XCTAssertEqual(doc.arrangement, .alphabetical)
        XCTAssertTrue(doc.move(appID: 3, before: 1))
        XCTAssertEqual(doc.entries.map(\.appID), [3, 1, 2])
        XCTAssertEqual(doc.arrangement, .custom)
        XCTAssertTrue(doc.move(appID: 3, before: nil))
        XCTAssertEqual(doc.entries.map(\.appID), [1, 2, 3])
        XCTAssertFalse(doc.move(appID: 2, before: 2))
        XCTAssertFalse(doc.move(appID: 99, before: 1))
        doc.insert(Self.entry(4, "Aardvark"))            // custom: appended, not sorted
        XCTAssertEqual(doc.entries.map(\.appID), [1, 2, 3, 4])
        doc.arrangeAlphabetically()
        XCTAssertEqual(doc.entries.map(\.title), ["Aardvark", "Alpha", "Beta", "Gamma"])
        XCTAssertEqual(doc.arrangement, .alphabetical)
        doc.insert(Self.entry(5, "Delta"))               // alphabetical again: sorted in
        XCTAssertEqual(doc.entries.map(\.title), ["Aardvark", "Alpha", "Beta", "Delta", "Gamma"])
    }

    func testArrangementRoundTripsAndDefaultsForOldDocuments() throws {
        var doc = Self.document()
        doc.move(appID: 10, before: 620)
        let data = try ShelfDocumentCodec.encode(doc)
        XCTAssertEqual(try ShelfDocumentCodec.decode(data).arrangement, .custom)
        // A document written before `arrangement` existed decodes as alphabetical.
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "arrangement")
        let old = try JSONSerialization.data(withJSONObject: json)
        XCTAssertEqual(try ShelfDocumentCodec.decode(old).arrangement, .alphabetical)
    }

    func testInsertSortedOrdering() {
        var doc = ShelfDocument.empty(owner: ShelfOwner(steamID64: nil, displayName: "My Shelf", avatarURL: nil))
        doc.insertSorted(Self.entry(3, "Zelda-like"))
        doc.insertSorted(Self.entry(2, "ábc"))
        doc.insertSorted(Self.entry(1, "the Witcher"))
        XCTAssertEqual(doc.entries.map(\.title), ["ábc", "the Witcher", "Zelda-like"])
    }

    func testLocalBackOfBoxDeterministicAndBucketed() async throws {
        let provider = LocalBackOfBoxProvider()
        var e = Self.entry(620, "Portal 2", full: true)
        let a = try await provider.content(for: BackOfBoxContext(entry: e))
        let b = try await provider.content(for: BackOfBoxContext(entry: e))
        XCTAssertEqual(a.blurb, b.blurb)
        XCTAssertEqual(a.tagline, b.tagline)
        XCTAssertTrue(a.blurb.contains("modest trophy shelf") || a.blurb.contains("Trophy"))
        e.stats.playtimeMinutes = 60 * 600
        let c = try await provider.content(for: BackOfBoxContext(entry: e))
        XCTAssertNotEqual(a.blurb, c.blurb)
        XCTAssertNotEqual(a.inputFingerprint, c.inputFingerprint)
    }

    @MainActor func testLocalShelfSourceSaveThenLoad() throws {
        let container = try ModelContainer(for: ShelfRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let source = LocalShelfSource(container: container)
        XCTAssertNil(try source.load())
        var doc = Self.document()
        try source.save(doc)
        XCTAssertEqual(try source.load(), doc)
        doc.title = "Renamed"
        try source.save(doc)
        XCTAssertEqual(try source.load()?.title, "Renamed")
    }

    @MainActor func testAppModelTestsModeAndDemoToggle() async throws {
        let container = try ModelContainer(for: ShelfRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let model = AppModel(mode: .tests, container: container)
        await model.onLaunch()                      // must be a no-op: no network, no Keychain
        XCTAssertFalse(model.hasAPIKey)
        XCTAssertTrue(model.document.entries.isEmpty)

        model.startDemo()
        XCTAssertEqual(model.document.shelvedEntries.count, 40)
        XCTAssertEqual(model.pagination.pageCount, 3)
        XCTAssertEqual(model.library?.games.count, 50)

        let victim = model.document.shelvedEntries[0]
        model.update(victim.appID) { $0.rating = 5; $0.note = "keep me" }
        model.setShelved(victim.appID, false)
        XCTAssertEqual(model.document.shelvedEntries.count, 39)
        model.setShelved(victim.appID, true)
        let restored = try XCTUnwrap(model.document.entries.first { $0.appID == victim.appID })
        XCTAssertEqual(restored.rating, 5)
        XCTAssertEqual(restored.note, "keep me")

        model.go(to: 2)
        XCTAssertEqual(model.pageIndex, 2)
        model.setAllShelved(false, appIDs: model.document.shelvedEntries.map(\.appID))
        XCTAssertEqual(model.pageIndex, 0)          // clamped after the shelf emptied
    }
}
