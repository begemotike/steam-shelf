import XCTest
import SwiftData
@testable import SteamShelf

final class LarianFormatsTests: XCTestCase {
    static func fixture(_ b64: String) throws -> Data {
        try XCTUnwrap(Data(base64Encoded: b64))
    }

    func testLZ4BlockVector() throws {
        var out: [UInt8] = []
        try LZ4.decodeBlock(Self.fixture(LarianFixtures.lz4BlockBase64), into: &out, maxOutput: 10_000)
        XCTAssertEqual(String(decoding: out, as: UTF8.self), LarianFixtures.lz4BlockExpected)
    }

    func testLZ4CorruptInputThrows() throws {
        let vector = try Self.fixture(LarianFixtures.lz4BlockBase64)
        var threw = 0
        for cut in 1..<vector.count {
            var out: [UInt8] = []
            do { try LZ4.decodeBlock(vector.prefix(cut), into: &out, maxOutput: 10_000) } catch is PersonalizerError { threw += 1 }
        }
        XCTAssertGreaterThan(threw, 0)
        var out: [UInt8] = []
        XCTAssertThrowsError(try LZ4.decodeBlock(vector.prefix(10), into: &out, maxOutput: 10_000))
        // A match offset pointing before the start of the output.
        XCTAssertThrowsError(try LZ4.decodeBlock(Data([0x10, 0x41, 0x05, 0x00]), into: &out, maxOutput: 100))
        // Output cap.
        out = []
        XCTAssertThrowsError(try LZ4.decodeBlock(vector, into: &out, maxOutput: 20))
    }

    func testLZ4FrameRejectsGarbage() {
        XCTAssertThrowsError(try LZ4.decodeFrame(Data([1, 2, 3, 4, 5, 6, 7, 8])))
        XCTAssertThrowsError(try LZ4.decodeFrame(Data([0x04, 0x22, 0x4D, 0x18, 0x64])))
    }

    func testZstdRejectsGarbage() {
        XCTAssertThrowsError(try Zstd.decompress(Data([1, 2, 3, 4, 5]), uncompressedSize: 100))
    }

    // MARK: LSF

    private func dump(_ n: LSFNode, _ depth: Int = 0) -> [String] {
        let attrs = n.attributes.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        return ["\(depth):\(n.name)[\(attrs)]"] + n.children.flatMap { dump($0, depth + 1) }
    }

    func testLSFPlainAndLZ4Match() throws {
        let plain = try LSF.parse(Self.fixture(LarianFixtures.lsfPlainBase64))
        let lz4 = try LSF.parse(Self.fixture(LarianFixtures.lsfLZ4Base64))
        XCTAssertEqual(plain.map(\.name), ["Waypoints", "Journal"])
        XCTAssertEqual(plain.flatMap { dump($0) }, lz4.flatMap { dump($0) })
        let journal = try XCTUnwrap(plain.last)
        XCTAssertEqual(journal.children.map(\.name), ["QuestCategories", "Quests", "DialogLogs"])
        let logs = try XCTUnwrap(journal.child(named: "DialogLogs")).children(named: "DialogLog")
        XCTAssertEqual(logs.count, 4)
        let lines = journal.descendants.filter { $0.name == "DialogLogLine" }
        let second = try XCTUnwrap(lines.dropFirst().first)
        XCTAssertEqual(second.attributes["RollAbility"], .int(6))
        XCTAssertEqual(second.attributes["RollSkill"], .int(3))
        XCTAssertEqual(second.attributes["RollIsSuccess"], .bool(true))
    }

    func testLSFKeepOnly() throws {
        let kept = try LSF.parse(Self.fixture(LarianFixtures.lsfLZ4Base64), keepOnly: ["Journal"])
        XCTAssertEqual(kept.map(\.name), ["Journal"])
        XCTAssertEqual(kept[0].children.count, 3)
    }

    func testLSFCorruptThrows() throws {
        let good = try Self.fixture(LarianFixtures.lsfLZ4Base64)
        XCTAssertThrowsError(try LSF.parse(Data("nope".utf8)))
        for cut in stride(from: 8, to: good.count, by: 7) {
            do { _ = try LSF.parse(good.prefix(cut)) } catch is PersonalizerError { continue } catch { XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try LSF.parse(good.prefix(good.count / 2)))
    }

    // MARK: LSPK

    static func writeFixtureLSV() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "fixture-\(UUID().uuidString).lsv")
        try fixture(LarianFixtures.lsvBase64).write(to: url)
        return url
    }

    func testLSPKPackage() throws {
        let url = try Self.writeFixtureLSV()
        defer { try? FileManager.default.removeItem(at: url) }
        let pkg = try LSPKPackage(url: url)
        XCTAssertEqual(pkg.names, ["meta.lsf", "SaveInfo.json", "Globals.lsf"])
        let info = try XCTUnwrap(JSONSerialization.jsonObject(with: pkg.data(for: "SaveInfo.json")) as? [String: Any])
        XCTAssertEqual(info["Save Name"] as? String, "Goblin Camp CLEARED - 26h 12m")
        let globals = try LSF.parse(pkg.data(for: "Globals.lsf"))
        XCTAssertTrue(globals.contains { $0.name == "Journal" })
        XCTAssertThrowsError(try pkg.data(for: "missing"))
    }

    func testLSPKTruncatedFileThrows() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "trunc-\(UUID().uuidString).lsv")
        defer { try? FileManager.default.removeItem(at: url) }
        try Self.fixture(LarianFixtures.lsvBase64).prefix(60).write(to: url)
        XCTAssertThrowsError(try LSPKPackage(url: url))
    }
}

final class BG3PersonalizerTests: XCTestCase {
    static let utc = TimeZone(identifier: "UTC") ?? .gmt

    static func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: s) ?? .distantPast
    }

    static func member(_ origin: String, _ main: String? = nil, _ sub: String? = nil, level: Int? = nil) -> BG3Member {
        BG3Member(origin: origin, mainClass: main, subClass: sub, level: level, xp: nil)
    }

    static func record(_ when: String, _ name: String, hero: String = "Corth", party: [BG3Member]? = nil) -> BG3SaveRecord {
        BG3SaveRecord(modified: date(when), hero: hero, saveName: name,
                      members: party ?? [member("Generic", "Ranger", "BeastMaster", level: 4), member("Gale"), member("Karlach")])
    }

    /// Builds `<root>/userdata/1234/1086940/remote/_SAVE_Public/Savegames/Story/Corth-123__<name>/<name>.lsv` from the fixture.
    func makeSteamRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "steamroot-\(UUID().uuidString)", directoryHint: .isDirectory)
        let folder = root.appending(path: "userdata/1234/1086940/remote/_SAVE_Public/Savegames/Story/Corth-123__Goblin Camp CLEARED - 26h 12m", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try LarianFormatsTests.fixture(LarianFixtures.lsvBase64).write(to: folder.appending(path: "Goblin Camp CLEARED - 26h 12m.lsv"))
        return root
    }

    func testDigestFromFixturePackage() throws {
        let root = try makeSteamRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let digest = try XCTUnwrap(BG3Personalizer().digest(steamRoot: root))
        XCTAssertEqual(digest.saveCount, 1)
        XCTAssertTrue(digest.fingerprint.hasPrefix("1:"))
        for needle in ["Goblin Camp CLEARED - 26h 12m", "26h12m", "L5 Ranger/BeastMaster", "Gale", "+quasit", "Corth"] {
            XCTAssertTrue(digest.history.contains(needle), "history missing \(needle):\n\(digest.history)")
        }
        let latest = digest.latest
        for needle in ["DEN_Conflict", "DEN_IdolTheft", "UND_MyconidRevenge → UND_MyconidRevenge_KillNere",
                       "GLO_SpeakWithDead_Generic ×2", "Persuasion 1 passed / 1 failed", "Insight 1 passed (passive)",
                       "Strength check 1 passed", "DifficultyMedium", "4.1.1.6848561", "Completed quests (2)"] {
            XCTAssertTrue(latest.contains(needle), "latest missing \(needle):\n\(latest)")
        }
        XCTAssertFalse(latest.contains("HIDDEN_WLD_Rewards"))
        XCTAssertFalse(latest.contains(".lsj"))
        XCTAssertFalse(latest.contains("Journal unavailable"))
    }

    func testNoSavesReturnsNil() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "empty-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertNil(try BG3Personalizer().digest(steamRoot: root))
    }

    func testFolderNameParsing() {
        let p = BG3Personalizer.parseFolder("Corth-1234567__Putrid Bog - 17h 23m")
        XCTAssertEqual(p.hero, "Corth")
        XCTAssertEqual(p.saveName, "Putrid Bog - 17h 23m")
        XCTAssertEqual(BG3Personalizer.parseFolder("Odd-Name-99__AutoSave_3").hero, "Odd-Name")
    }

    func testPartyAndPlaytimeText() {
        let r = Self.record("2024-02-05T21:40:00Z", "Putrid Bog - 17h 17m new attempt",
                            party: [Self.member("Generic", "Ranger", "BeastMaster", level: 4), Self.member("Generic"), Self.member("Wyll"),
                                    Self.member("QUEST_FOR_QuasitSummon"), Self.member("SUMMON_Raven"), Self.member("Something_Else")])
        XCTAssertEqual(r.playtime, "17h17m")
        XCTAssertEqual(r.classText, "L4 Ranger/BeastMaster")
        XCTAssertEqual(r.partyText, "with custom character, Wyll +quasit +raven +summon")
        XCTAssertEqual(Self.record("2024-02-05T21:40:00Z", "killed ethel outside").playtime, nil)
        XCTAssertEqual(Self.record("2024-02-05T21:40:00Z", "x", party: [Self.member("Generic")]).partyText, "solo")
    }

    func testHistoryLineFormat() {
        let text = BG3Format.history([Self.record("2024-02-05T21:40:00Z", "Putrid Bog - 17h 17m new attempt")], timeZone: Self.utc)
        XCTAssertTrue(text.contains("2024-02-05 21:40 | Corth | \"Putrid Bog - 17h 17m new attempt\" | 17h17m | L4 Ranger/BeastMaster | with Gale, Karlach"), text)
        XCTAssertTrue(text.contains("Total saves: 1"))
        XCTAssertTrue(text.contains("Corth (1 save)"))
    }

    func testAutosaveCollapsingAndReloadNote() {
        var records = [Self.record("2024-03-01T10:00:00Z", "Camp - 5h 0m")]
        for k in 0..<5 { records.append(Self.record("2024-03-01T11:0\(k):00Z", "AutoSave_\(k)")) }
        records.append(Self.record("2024-03-02T11:00:00Z", "AutoSave_9"))                         // next day: its own line
        records.append(Self.record("2024-03-02T11:30:00Z", "AutoSave_1", hero: "Tav"))           // other hero: its own line
        records.append(Self.record("2024-03-03T09:00:00Z", "Camp - 4h 10m"))                    // reload
        let text = BG3Format.history(records.shuffled(), timeZone: Self.utc)
        XCTAssertEqual(text.components(separatedBy: "5 autosaves").count - 1, 1)
        XCTAssertTrue(text.contains("| Corth | 5 autosaves |"))
        XCTAssertEqual(text.components(separatedBy: " | ").filter { $0.hasPrefix("\"AutoSave_") }.count, 2)
        XCTAssertTrue(text.contains("Total saves: 9"))
        XCTAssertTrue(text.contains("lower playtime than the previous save by the same hero means the player reloaded"))
        XCTAssertTrue(text.contains("Tav (1 save)"))
    }

    func testHistoryCapKeepsMostRecent() {
        let records = (0..<300).map { Self.record("2024-01-01T00:00:00Z", "Save \($0) - \($0)h 0m")
            .with(modified: Date(timeIntervalSince1970: 1_700_000_000 + Double($0) * 3600)) }
        let text = BG3Format.history(records, timeZone: Self.utc)
        XCTAssertTrue(text.contains("Total saves: 300"))
        XCTAssertTrue(text.contains("Save 299 "))
        XCTAssertFalse(text.contains("\"Save 49 "))
        XCTAssertTrue(text.contains("\"Save 50 "))
    }

    func testLatestWithoutJournal() {
        let info = BG3SaveInfo(saveName: "x", difficulty: "DifficultyHard", gameVersion: "1", currentLevel: nil,
                               members: [Self.member("Generic", "Rogue", nil, level: 3)])
        let text = BG3Format.latest(info: info, hero: "Corth", saveName: "x", journal: nil)
        XCTAssertTrue(text.contains("Journal unavailable."))
        XCTAssertTrue(text.contains("Corth (hero): Rogue, level 3"))
    }
}

private extension BG3SaveRecord {
    func with(modified: Date) -> BG3SaveRecord { var c = self; c.modified = modified; return c }
}

final class ShelfKeeperAITests: XCTestCase {
    static let digest = GameDigest(history: "HISTORY-TEXT", latest: "LATEST-TEXT", fingerprint: "3:100", saveCount: 3)

    func body() throws -> (raw: String, obj: [String: Any]) {
        let data = try ShelfKeeperAI.requestBody(game: "Baldur's Gate 3", digest: Self.digest)
        let raw = String(decoding: data, as: UTF8.self)
        return (raw, try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]))
    }

    func testRequestBodyShape() throws {
        let (raw, obj) = try body()
        XCTAssertEqual(obj["model"] as? String, "claude-opus-5-5")
        XCTAssertTrue(raw.contains("\"fallbacks\":\"default\""))
        XCTAssertEqual(obj["max_tokens"] as? Int, 16000)
        for forbidden in ["thinking", "temperature", "top_p", "top_k"] { XCTAssertNil(obj[forbidden], forbidden) }
        let config = try XCTUnwrap(obj["output_config"] as? [String: Any])
        XCTAssertEqual(config["effort"] as? String, "medium")
        let format = try XCTUnwrap(config["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        XCTAssertEqual(schema["required"] as? [String], ["tagline", "blurb", "observations", "playstyle"])
        let props = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertEqual(Set(props.keys), ["tagline", "blurb", "observations", "playstyle"])
        XCTAssertTrue((obj["system"] as? String ?? "").hasPrefix("You are the Shelf-Keeper, the dry, fond curator"))
        let messages = try XCTUnwrap(obj["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        let content = try XCTUnwrap(messages[0]["content"] as? String)
        XCTAssertTrue(content.hasPrefix("Game: Baldur's Gate 3\n\n== SAVE HISTORY ==\nHISTORY-TEXT\n\n== MOST RECENT SAVE ==\nLATEST-TEXT\n\nWrite:\n- tagline:"))
    }

    func testRequestHeadersAndURL() throws {
        let r = try ShelfKeeperAI.makeRequest(game: "G", digest: Self.digest, key: "test-key")
        XCTAssertEqual(r.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(r.httpMethod, "POST")
        XCTAssertEqual(r.timeoutInterval, 180)
        XCTAssertEqual(r.value(forHTTPHeaderField: "content-type"), "application/json")
        XCTAssertEqual(r.value(forHTTPHeaderField: "x-api-key"), "test-key")
        XCTAssertEqual(r.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(r.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01")
    }

    private func response(stop: String = "end_turn", blocks: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["stop_reason": stop, "content": blocks])
    }

    func testParseSkipsThinkingBlocks() throws {
        let json = #"{"tagline":" Wolf Whisperer ","blurb":"Fifty saves.","observations":["One."," ","Two."],"playstyle":"Talks first."}"#
        let data = try response(blocks: [["type": "thinking", "thinking": "hmm"], ["type": "fallback", "x": 1], ["type": "text", "text": json]])
        let notes = try ShelfKeeperAI.parse(data, status: 200)
        XCTAssertEqual(notes, KeeperNotes(tagline: "Wolf Whisperer", blurb: "Fifty saves.", observations: ["One.", "Two."], playstyle: "Talks first."))
    }

    func testParseRefusalAndTruncation() throws {
        XCTAssertThrowsError(try ShelfKeeperAI.parse(response(stop: "refusal", blocks: []), status: 200)) { XCTAssertEqual($0 as? KeeperError, .refused) }
        XCTAssertThrowsError(try ShelfKeeperAI.parse(response(stop: "max_tokens", blocks: [["type": "text", "text": "{"]]), status: 200)) {
            XCTAssertEqual($0 as? KeeperError, .truncated)
        }
    }

    func testParseHTTPErrors() throws {
        let body = Data(#"{"type":"error","error":{"type":"invalid_request_error","message":"nope"}}"#.utf8)
        XCTAssertThrowsError(try ShelfKeeperAI.parse(body, status: 401)) { XCTAssertEqual($0 as? KeeperError, .invalidKey) }
        XCTAssertThrowsError(try ShelfKeeperAI.parse(body, status: 429)) { XCTAssertEqual($0 as? KeeperError, .rateLimited) }
        XCTAssertThrowsError(try ShelfKeeperAI.parse(body, status: 529)) { XCTAssertEqual($0 as? KeeperError, .overloaded) }
        XCTAssertThrowsError(try ShelfKeeperAI.parse(body, status: 503)) { XCTAssertEqual($0 as? KeeperError, .overloaded) }
        XCTAssertThrowsError(try ShelfKeeperAI.parse(body, status: 400)) { XCTAssertEqual($0 as? KeeperError, .http(400, "nope")) }
        XCTAssertThrowsError(try ShelfKeeperAI.parse(Data("<html>".utf8), status: 418)) { XCTAssertEqual($0 as? KeeperError, .http(418, nil)) }
        XCTAssertFalse(KeeperError.invalidKey.userMessage.isEmpty)
        XCTAssertTrue(KeeperError.http(400, "nope").userMessage.contains("nope"))
    }

    func testParseMalformed() throws {
        let bad = try response(blocks: [["type": "text", "text": "not json at all"]])
        XCTAssertThrowsError(try ShelfKeeperAI.parse(bad, status: 200)) { XCTAssertEqual($0 as? KeeperError, .malformed) }
        let missing = try response(blocks: [["type": "text", "text": #"{"tagline":"x"}"#]])
        XCTAssertThrowsError(try ShelfKeeperAI.parse(missing, status: 200)) { XCTAssertEqual($0 as? KeeperError, .malformed) }
        XCTAssertThrowsError(try ShelfKeeperAI.parse(Data("nope".utf8), status: 200)) { XCTAssertEqual($0 as? KeeperError, .malformed) }
    }
}

@MainActor final class KeeperModelTests: XCTestCase {
    static let t0 = Date(timeIntervalSince1970: 1_780_000_000)

    func testBackOfBoxContentDecodesWithoutNewFields() throws {
        let old = #"{"blurb":"Old.","tagline":"T","providerID":"local.v1","inputFingerprint":"x","generatedAt":"2026-05-01T00:00:00Z"}"#
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        let c = try d.decode(BackOfBoxContent.self, from: Data(old.utf8))
        XCTAssertNil(c.observations)
        XCTAssertNil(c.detail)
        XCTAssertFalse(c.isAIWritten)
    }

    func testBackOfBoxContentRoundTripsNewFields() throws {
        let c = BackOfBoxContent(blurb: "b", tagline: "t", providerID: "anthropic.claude-opus-5-5", inputFingerprint: "118:1700000000",
                                 generatedAt: Self.t0, observations: ["one", "two"], detail: "Plays chatty.")
        let back = try JSONDecoder().decode(BackOfBoxContent.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back, c)
        XCTAssertTrue(c.isAIWritten)
        XCTAssertEqual(c.savesRead, 118)
    }

    func testNotesSurviveShelfDocumentRoundTrip() throws {
        var doc = ShelfDocumentTests.document()
        doc.entries[0].blurb = BackOfBoxContent(blurb: "b", tagline: "t", providerID: "anthropic.claude-opus-5-5", inputFingerprint: "3:1",
                                                generatedAt: ShelfDocumentTests.t0, observations: ["o"], detail: "d")
        XCTAssertEqual(try ShelfDocumentCodec.decode(ShelfDocumentCodec.encode(doc)), doc)
    }

    private func makeModel() throws -> AppModel {
        let container = try ModelContainer(for: ShelfRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let model = AppModel(mode: .tests, container: container)
        try model.importDocument(ShelfDocumentCodec.encode(ShelfDocumentTests.document()))
        return model
    }

    func testBlurbIfNeededKeepsAINotes() async throws {
        let model = try makeModel()
        let ai = BackOfBoxContent(blurb: "AI blurb", tagline: "AI tag", providerID: "anthropic.claude-opus-5-5", inputFingerprint: "3:1",
                                  generatedAt: Self.t0, observations: ["o"], detail: "d")
        model.update(620) { $0.blurb = ai }
        await model.blurbIfNeeded(for: 620)
        XCTAssertEqual(model.document.entries.first { $0.appID == 620 }?.blurb, ai)
    }

    func testClearNotesReturnsToTemplate() async throws {
        let model = try makeModel()
        model.update(620) { $0.blurb = BackOfBoxContent(blurb: "AI", tagline: "t", providerID: "anthropic.claude-opus-5-5", inputFingerprint: "3:1",
                                                        generatedAt: Self.t0, observations: ["o"], detail: "d") }
        // The demo/tests shelf is read-only for notes: clearing and writing are refused.
        XCTAssertFalse(model.canWriteNotes)
        model.clearNotes(for: 620)
        XCTAssertEqual(model.document.entries.first { $0.appID == 620 }?.blurb?.providerID, "anthropic.claude-opus-5-5")
        // With the AI blurb gone (what clearNotes does on a local shelf), the template comes back.
        model.update(620) { $0.blurb = nil }
        await model.blurbIfNeeded(for: 620)
        XCTAssertEqual(model.document.entries.first { $0.appID == 620 }?.blurb?.providerID, "local.v1")
        await model.writeNotes(for: 620)
        XCTAssertEqual(model.keeperState(for: 620), .idle)
    }

    func testKeeperErrorText() {
        XCTAssertEqual(KeeperText.message(for: PersonalizerError.noSaves), "No save files were found for this game.")
        XCTAssertEqual(KeeperText.message(for: KeeperError.rateLimited), KeeperError.rateLimited.userMessage)
        XCTAssertFalse(KeeperText.message(for: PersonalizerError.corrupt("x")).contains("x"))
    }
}
