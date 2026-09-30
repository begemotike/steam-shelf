import Foundation
import ImageIO
import OSLog

struct CoverRequest: Sendable, Hashable {
    let appID: Int
    let title: String
    let portraitURLs: [String]
    let headerURL: String?
}

enum CoverResult: Sendable {
    case portrait(SendableImage)
    case header(SendableImage)
    case none
}

actor ImageCache {
    private static let log = Logger(subsystem: "net.outofajam.SteamShelf", category: "ImageCache")
    private static let missTTL: TimeInterval = 7 * 24 * 3600
    private static let memoryCap = 200
    private static let maxPixel = 1200

    private let fileManager: FileManager
    private let session: URLSession
    private var memory: [Int: CoverResult] = [:]
    private var inFlight: [Int: Task<CoverResult, Never>] = [:]
    private var misses: [Int: Date] = [:]
    private var missesLoaded = false

    init(fileManager: FileManager = .default, session: URLSession = .shared) {
        self.fileManager = fileManager
        self.session = session
    }

    func cover(for request: CoverRequest) async -> CoverResult {
        if let hit = memory[request.appID] { return hit }
        if let task = inFlight[request.appID] { return await task.value }
        let task = Task { await self.resolve(request) }
        inFlight[request.appID] = task
        let result = await task.value
        inFlight[request.appID] = nil
        remember(result, for: request.appID)
        return result
    }

    func clearMemory() { memory.removeAll() }

    // MARK: Resolution

    private func resolve(_ request: CoverRequest) async -> CoverResult {
        let id = request.appID
        let dir = coversDirectory()

        // Disk
        if let dir {
            let portrait = dir.appending(path: "\(id).jpg")
            if let image = Self.decode(url: portrait) { return .portrait(SendableImage(cgImage: image)) }
            let header = dir.appending(path: "\(id)-header.jpg")
            if let image = Self.decode(url: header) { return .header(SendableImage(cgImage: image)) }
        }

        // Recent miss
        loadMissesIfNeeded()
        if let missedAt = misses[id], Date().timeIntervalSince(missedAt) < Self.missTTL { return .none }

        // Network: portraits, then header
        for urlString in request.portraitURLs {
            if Task.isCancelled { return .none }
            if let data = await fetchImageData(urlString), let image = Self.decode(data: data) {
                if let dir { try? data.write(to: dir.appending(path: "\(id).jpg"), options: .atomic) }
                return .portrait(SendableImage(cgImage: image))
            }
        }
        if let headerURL = request.headerURL, !Task.isCancelled,
           let data = await fetchImageData(headerURL), let image = Self.decode(data: data) {
            if let dir { try? data.write(to: dir.appending(path: "\(id)-header.jpg"), options: .atomic) }
            return .header(SendableImage(cgImage: image))
        }

        if !Task.isCancelled {
            misses[id] = Date()
            saveMisses()
        }
        return .none
    }

    private func fetchImageData(_ urlString: String) async -> Data? {
        guard let url = URL(string: urlString), url.scheme == "https" else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.mimeType?.hasPrefix("image/") == true else { return nil }
            return data
        } catch {
            Self.log.debug("Image fetch failed: \(url.lastPathComponent, privacy: .public)")
            return nil
        }
    }

    private func remember(_ result: CoverResult, for id: Int) {
        // Don't memoize .none: a later call may succeed (e.g. after the URL list changes).
        if case .none = result { return }
        if memory.count >= Self.memoryCap, let victim = memory.keys.first { memory[victim] = nil }
        memory[id] = result
    }

    // MARK: Decoding

    private static func decode(url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return image(from: source)
    }

    private static func decode(data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return image(from: source)
    }

    private static func image(from source: CGImageSource) -> CGImage? {
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let height = (props?[kCGImagePropertyPixelHeight] as? Int) ?? 0
        let width = (props?[kCGImagePropertyPixelWidth] as? Int) ?? 0
        if max(height, width) > maxPixel {
            let options: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: Disk layout

    private func coversDirectory() -> URL? {
        guard let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appending(path: "SteamShelf/covers", directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func missesURL() -> URL? { coversDirectory()?.appending(path: "misses.json") }

    private func loadMissesIfNeeded() {
        guard !missesLoaded else { return }
        missesLoaded = true
        guard let url = missesURL(), let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let raw = try? decoder.decode([String: Date].self, from: data) {
            for (k, v) in raw { if let id = Int(k) { misses[id] = v } }
        }
    }

    private func saveMisses() {
        guard let url = missesURL() else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let raw = Dictionary(uniqueKeysWithValues: misses.map { (String($0.key), $0.value) })
        if let data = try? encoder.encode(raw) { try? data.write(to: url, options: .atomic) }
    }
}
