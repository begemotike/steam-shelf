import XCTest
@testable import SteamShelf

final class CoverURLTests: XCTestCase {
    private let base = "https://shared.akamai.steamstatic.com/store_item_assets/"
    private let assetHash = "480bd879ac737921bfa2529a6fea15961267ad21"

    func testAssetURL() {
        let url = CoverURLs.assetURL(format: "steam/apps/3527290/${FILENAME}?t=1790591892",
                                     asset: "\(assetHash)/library_600x900_2x.jpg")
        XCTAssertEqual(url, "\(base)steam/apps/3527290/\(assetHash)/library_600x900_2x.jpg?t=1790591892")
    }

    func testUnhashed() {
        XCTAssertEqual(CoverURLs.unhashedPortrait2x(appID: 620), "\(base)steam/apps/620/library_600x900_2x.jpg")
        XCTAssertEqual(CoverURLs.unhashedHeader(appID: 620), "\(base)steam/apps/620/header.jpg")
    }

    func testPortraitCandidates() {
        let hashed = StoreAssets(asset_url_format: "steam/apps/3527290/${FILENAME}?t=1",
                                 library_capsule: "\(assetHash)/library_600x900.jpg",
                                 library_capsule_2x: "\(assetHash)/library_600x900_2x.jpg", header: nil)
        let c = CoverURLs.portraitCandidates(appID: 3527290, assets: hashed)
        XCTAssertEqual(c, [
            "\(base)steam/apps/3527290/\(assetHash)/library_600x900_2x.jpg?t=1",
            "\(base)steam/apps/3527290/\(assetHash)/library_600x900.jpg?t=1",
            "\(base)steam/apps/3527290/library_600x900_2x.jpg",
        ])

        let bare = StoreAssets(asset_url_format: "steam/apps/620/${FILENAME}",
                               library_capsule: "library_600x900_2x.jpg",
                               library_capsule_2x: "library_600x900_2x.jpg", header: nil)
        XCTAssertEqual(CoverURLs.portraitCandidates(appID: 620, assets: bare),
                       ["\(base)steam/apps/620/library_600x900_2x.jpg"])

        XCTAssertEqual(CoverURLs.portraitCandidates(appID: 620, assets: nil),
                       [CoverURLs.unhashedPortrait2x(appID: 620)])

        let dota = StoreAssets(asset_url_format: "steam/apps/570/${FILENAME}?t=2", library_capsule: nil,
                               library_capsule_2x: "abc123/library_capsule_2x.jpg", header: nil)
        XCTAssertEqual(CoverURLs.portraitCandidates(appID: 570, assets: dota).first,
                       "\(base)steam/apps/570/abc123/library_capsule_2x.jpg?t=2")
    }

    func testHeader() {
        let assets = StoreAssets(asset_url_format: "steam/apps/3527290/${FILENAME}?t=1", library_capsule: nil,
                                 library_capsule_2x: nil, header: "31bac6/header.jpg")
        XCTAssertEqual(CoverURLs.header(appID: 3527290, assets: assets), "\(base)steam/apps/3527290/31bac6/header.jpg?t=1")
        XCTAssertEqual(CoverURLs.header(appID: 620, assets: nil), CoverURLs.unhashedHeader(appID: 620))
    }

    // SteamIDInput lives here to keep four test files.
    func testSteamIDInput() {
        XCTAssertEqual(SteamIDInput.parse("76561197960287930"), .steamID64("76561197960287930"))
        XCTAssertEqual(SteamIDInput.parse("https://steamcommunity.com/profiles/76561197960287930"), .steamID64("76561197960287930"))
        XCTAssertEqual(SteamIDInput.parse("https://steamcommunity.com/profiles/76561197960287930/"), .steamID64("76561197960287930"))
        XCTAssertEqual(SteamIDInput.parse("https://steamcommunity.com/id/gabelogannewell/"), .vanity("gabelogannewell"))
        XCTAssertEqual(SteamIDInput.parse("  gabelogannewell "), .vanity("gabelogannewell"))
        XCTAssertNil(SteamIDInput.parse("hello world"))
        XCTAssertNil(SteamIDInput.parse(""))
        XCTAssertNil(SteamIDInput.parse("7656119796028793")) 
    }
}
