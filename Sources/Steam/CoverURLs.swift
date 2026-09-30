import Foundation

enum CoverURLs {
    static let assetBase = "https://shared.akamai.steamstatic.com/store_item_assets/"
    private static let filenameToken = "${FILENAME}"

    static func assetURL(format: String, asset: String) -> String {
        assetBase + format.replacingOccurrences(of: filenameToken, with: asset)
    }

    static func unhashedPortrait2x(appID: Int) -> String {
        "\(assetBase)steam/apps/\(appID)/library_600x900_2x.jpg"
    }

    static func unhashedHeader(appID: Int) -> String {
        "\(assetBase)steam/apps/\(appID)/header.jpg"
    }

    /// Ordered, de-duplicated candidates: hashed 2x, hashed 1x (only when a URL format is known), unhashed 2x.
    static func portraitCandidates(appID: Int, assets: StoreAssets?) -> [String] {
        var result: [String] = []
        func add(_ url: String) { if !result.contains(url) { result.append(url) } }
        if let assets, let format = assets.asset_url_format {
            if let a = assets.library_capsule_2x { add(assetURL(format: format, asset: a)) }
            if let a = assets.library_capsule { add(assetURL(format: format, asset: a)) }
        }
        add(unhashedPortrait2x(appID: appID))
        return result
    }

    static func header(appID: Int, assets: StoreAssets?) -> String {
        if let assets, let format = assets.asset_url_format, let h = assets.header {
            return assetURL(format: format, asset: h)
        }
        return unhashedHeader(appID: appID)
    }
}
