import XCTest
@testable import SteamShelf

final class SteamDecodingTests: XCTestCase {
    private func d(_ s: String) -> Data { Data(s.utf8) }

    // MARK: Fixtures
    static let vanityOK = #"{ "response": { "steamid": "76561197960287930", "success": 1 } }"#
    static let vanityNoMatch = #"{ "response": { "success": 42, "message": "No match" } }"#
    static let summaries = #"""
    { "response": { "players": [ {
      "steamid": "76561197960287930", "communityvisibilitystate": 3, "profilestate": 1,
      "personaname": "Rabscuttle", "profileurl": "https://steamcommunity.com/id/gabelogannewell/",
      "avatar": "https://avatars.steamstatic.com/h.jpg", "avatarfull": "https://avatars.steamstatic.com/h_full.jpg",
      "personastate": 0, "lastlogoff": 1700000000, "timecreated": 1063407589 } ] } }
    """#
    static let summariesEmpty = #"{ "response": { "players": [] } }"#
    static let ownedGames = #"""
    { "response": { "game_count": 2, "games": [
      { "appid": 620, "name": "Portal 2", "playtime_forever": 1234,
        "img_icon_url": "2e478fc6874d06ae5baf0d147f6f21203291aa02", "has_community_visible_stats": true,
        "playtime_windows_forever": 1200, "playtime_mac_forever": 34, "playtime_linux_forever": 0,
        "playtime_deck_forever": 0, "rtime_last_played": 1726000000, "playtime_disconnected": 0 },
      { "appid": 440, "name": "Team Fortress 2", "playtime_forever": 0,
        "img_icon_url": "e3f595a92552da3d664ad00277fad2107345f743", "rtime_last_played": 0 } ] } }
    """#
    static let ownedPrivate = #"{"response":{}}"#
    static let ownedZero = #"{"response":{"game_count":0}}"#
    static let ownedMissing = #"{"response":{"game_count":1,"games":[{"appid":7,"playtime_forever":5}]}}"#
    static let achievementsOK = #"""
    { "playerstats": { "steamID": "7656119", "gameName": "Portal 2", "achievements": [
      { "apiname": "A", "achieved": 1, "unlocktime": 1303000000, "name": "A", "description": "a" },
      { "apiname": "B", "achieved": 1, "unlocktime": 1303000001 },
      { "apiname": "C", "achieved": 0, "unlocktime": 0 } ], "success": true } }
    """#
    static let achievementsNone = #"{ "playerstats": { "steamID": "7656119", "gameName": "X", "success": true } }"#
    static let achievementsPrivate = #"{"playerstats":{"error":"Profile is not public","success":false}}"#
    static let achievementsNoStats = #"{"playerstats":{"error":"Requested app has no stats","success":false}}"#
    static let html403 = "<html><head><title>Forbidden</title></head><body><h1>Forbidden</h1></body></html>"
    static let getItems = #"""
    { "response": { "store_items": [
      { "item_type": 0, "id": 3527290, "success": 1, "visible": true, "name": "PEAK", "appid": 3527290, "type": 0,
        "assets": { "asset_url_format": "steam/apps/3527290/${FILENAME}?t=1790591892",
          "header": "31bac6b2eccf09b368f5e95ce510bae2baf3cfcd/header.jpg",
          "library_capsule": "480bd879ac737921bfa2529a6fea15961267ad21/library_600x900.jpg",
          "library_capsule_2x": "480bd879ac737921bfa2529a6fea15961267ad21/library_600x900_2x.jpg",
          "library_hero": "x/library_hero.jpg", "main_capsule": "x/capsule_616x353.jpg" } },
      { "item_type": 0, "id": 620, "success": 1, "name": "Portal 2", "appid": 620,
        "assets": { "asset_url_format": "steam/apps/620/${FILENAME}?t=1790187113",
          "library_capsule_2x": "library_600x900_2x.jpg", "header": "header.jpg" } },
      { "id": 999999999, "success": 15, "appid": 0 } ] } }
    """#

    // MARK: Tests
    func testVanity() throws {
        XCTAssertEqual(try SteamClient.parseVanity(d(Self.vanityOK)), "76561197960287930")
        XCTAssertThrowsError(try SteamClient.parseVanity(d(#"{"response":{"success":42,"message":"No match"}}"#))) {
            XCTAssertEqual($0 as? SteamError, .vanityNotFound)
        }
        XCTAssertThrowsError(try SteamClient.parseVanity(d(Self.vanityNoMatch)))
    }

    func testSummaries() throws {
        let p = try SteamClient.parseSummaries(d(Self.summaries))
        XCTAssertEqual(p.personaname, "Rabscuttle")
        XCTAssertEqual(p.communityvisibilitystate, 3)
        XCTAssertThrowsError(try SteamClient.parseSummaries(d(Self.summariesEmpty))) {
            XCTAssertEqual($0 as? SteamError, .profileNotFound)
        }
    }

    func testOwnedGames() throws {
        let games = try SteamClient.parseOwnedGames(d(Self.ownedGames))
        XCTAssertEqual(games.map(\.appid), [620, 440])
        XCTAssertNotNil(games[0].lastPlayedDate)
        XCTAssertNil(games[1].lastPlayedDate)
        XCTAssertNil(games[1].has_community_visible_stats)
        XCTAssertThrowsError(try SteamClient.parseOwnedGames(d(Self.ownedPrivate))) {
            XCTAssertEqual($0 as? SteamError, .gameDetailsPrivate)
        }
        XCTAssertEqual(try SteamClient.parseOwnedGames(d(Self.ownedZero)), [])
        let m = try SteamClient.parseOwnedGames(d(Self.ownedMissing))
        XCTAssertEqual(m.first?.displayName, "App 7")
        XCTAssertNil(m.first?.rtime_last_played)
    }

    func testAchievements() throws {
        XCTAssertEqual(try SteamClient.parseAchievements(d(Self.achievementsOK), status: 200), AchievementSummary(earned: 2, total: 3))
        XCTAssertEqual(try SteamClient.parseAchievements(d(Self.achievementsNone), status: 200), AchievementSummary(earned: 0, total: 0))
        XCTAssertThrowsError(try SteamClient.parseAchievements(d(Self.achievementsPrivate), status: 403)) {
            XCTAssertEqual($0 as? SteamError, .privateProfile)
        }
        XCTAssertThrowsError(try SteamClient.parseAchievements(d(Self.achievementsNoStats), status: 400)) {
            XCTAssertEqual($0 as? SteamError, .noStats)
        }
        XCTAssertThrowsError(try SteamClient.parseAchievements(d(Self.html403), status: 403)) {
            XCTAssertEqual($0 as? SteamError, .invalidKey)
        }
    }

    func testStoreItems() throws {
        let items = try SteamClient.parseStoreItems(d(Self.getItems))
        XCTAssertEqual(Set(items.keys), [3527290, 620])
        XCTAssertEqual(items[620]?.library_capsule_2x, "library_600x900_2x.jpg")
    }

    func testStoreItemsInputJSON() throws {
        let json = try SteamClient.storeItemsInputJSON(appIDs: [620, 10])
        XCTAssertTrue(json.contains(#""appid":620"#))
        XCTAssertTrue(json.contains(#""include_assets":true"#))
    }

    func testCheckStatus() {
        XCTAssertThrowsError(try SteamClient.checkStatus(401)) { XCTAssertEqual($0 as? SteamError, .invalidKey) }
        XCTAssertThrowsError(try SteamClient.checkStatus(403)) { XCTAssertEqual($0 as? SteamError, .invalidKey) }
        XCTAssertThrowsError(try SteamClient.checkStatus(429)) { XCTAssertEqual($0 as? SteamError, .rateLimited) }
        XCTAssertThrowsError(try SteamClient.checkStatus(500)) { XCTAssertEqual($0 as? SteamError, .http(500)) }
        XCTAssertNoThrow(try SteamClient.checkStatus(200))
    }

    func testResolveSteamID64DoesNotTouchNetwork() async throws {
        // Ephemeral session that would fail if used; .steamID64 must return immediately.
        let client = SteamClient(session: URLSession(configuration: .ephemeral))
        let id = try await client.resolveSteamID(.steamID64("76561197960287930"), key: "")
        XCTAssertEqual(id, "76561197960287930")
    }

    func testLibraryFoldersInstalledAppIDs() {
        let vdf = #"""
        "libraryfolders"
        {
        	"0"
        	{
        		"path"		"/Users/x/Library/Application Support/Steam"
        		"label"		""
        		"apps"
        		{
        			"8930"		"4837870324"
        			"620"		"1068179754"
        		}
        	}
        	"1"
        	{
        		"path"		"/Volumes/Games/SteamLibrary"
        		"apps"
        		{
        			"3527290"		"123"
        		}
        	}
        }
        """#
        XCTAssertEqual(SteamInstalls.installedAppIDs(vdf: vdf), [8930, 620, 3527290])
        XCTAssertEqual(SteamInstalls.installedAppIDs(vdf: "\"libraryfolders\"\n{\n}"), [])
        XCTAssertEqual(SteamInstalls.launchURL(appID: 620)?.absoluteString, "steam://rungameid/620")
    }
}
