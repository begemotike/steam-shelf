import Foundation
import libzstd

// Larian save formats: LZ4, zstd, LSPK (.lsv package) and LSF (binary tree).
// Ports of tools/bg3/lspk.py and tools/bg3/lsf.py. Every read is bounds-checked and throws
// `PersonalizerError.corrupt` instead of trapping.

/// Upper bound on any single decompressed section; real Larian sections are at most tens of MB.
private let maxSectionBytes = 1 << 29

// MARK: - Byte reading

enum Bytes {
    /// Little-endian integer at `offset`, or `.corrupt`.
    static func int<T: FixedWidthInteger>(_ b: [UInt8], _ offset: Int, as type: T.Type = T.self) throws -> T {
        let size = MemoryLayout<T>.size
        guard offset >= 0, offset <= b.count - size else { throw PersonalizerError.corrupt("read past end") }
        var v: UInt64 = 0
        for k in 0..<size { v |= UInt64(b[offset + k]) << UInt64(8 * k) }
        return T(truncatingIfNeeded: v)
    }

    static func slice(_ b: [UInt8], _ offset: Int, _ length: Int) throws -> ArraySlice<UInt8> {
        guard offset >= 0, length >= 0, offset <= b.count, length <= b.count - offset else {
            throw PersonalizerError.corrupt("slice out of range")
        }
        return b[offset..<(offset + length)]
    }
}

private struct Cursor {
    let bytes: [UInt8]
    var pos = 0
    init(_ bytes: [UInt8]) { self.bytes = bytes }

    mutating func next<T: FixedWidthInteger>(_ type: T.Type = T.self) throws -> T {
        let v: T = try Bytes.int(bytes, pos)
        pos += MemoryLayout<T>.size
        return v
    }

    mutating func take(_ n: Int) throws -> ArraySlice<UInt8> {
        let s = try Bytes.slice(bytes, pos, n)
        pos += n
        return s
    }
}

// MARK: - LZ4

enum LZ4 {
    /// Standard LZ4 block decoding. Appends to `dst` and resolves match offsets against everything already in
    /// `dst`, which is what makes linked frame blocks work. `maxOutput` caps the total size of `dst`.
    static func decodeBlock(_ src: Data, into dst: inout [UInt8], maxOutput: Int) throws {
        try decodeBlock([UInt8](src), into: &dst, maxOutput: maxOutput)
    }

    static func decodeBlock(_ s: [UInt8], into dst: inout [UInt8], maxOutput: Int) throws {
        var i = 0
        let n = s.count
        func length(_ initial: Int) throws -> Int {
            var total = initial
            guard initial == 15 else { return total }
            while true {
                guard i < n else { throw PersonalizerError.corrupt("lz4: truncated length") }
                let b = Int(s[i]); i += 1
                total += b
                guard total <= maxOutput else { throw PersonalizerError.corrupt("lz4: length too large") }
                if b != 255 { return total }
            }
        }
        while i < n {
            let token = Int(s[i]); i += 1
            let literals = try length(token >> 4)
            guard literals <= n - i, literals <= maxOutput - dst.count else { throw PersonalizerError.corrupt("lz4: literal run out of range") }
            dst.append(contentsOf: s[i..<(i + literals)])
            i += literals
            if i == n { return }                       // the last sequence carries literals only
            guard i + 2 <= n else { throw PersonalizerError.corrupt("lz4: truncated offset") }
            let offset = Int(s[i]) | (Int(s[i + 1]) << 8)
            i += 2
            guard offset > 0, offset <= dst.count else { throw PersonalizerError.corrupt("lz4: bad match offset") }
            let matchLength = try length(token & 15) + 4
            guard matchLength <= maxOutput - dst.count else { throw PersonalizerError.corrupt("lz4: output too large") }
            let start = dst.count - offset
            for k in 0..<matchLength { dst.append(dst[start + k]) }   // may overlap itself (run-length)
        }
    }

    /// LZ4 frame (magic 0x184D2204). Every block goes into the same growing buffer, so linked blocks resolve.
    static func decodeFrame(_ src: Data, maxOutput: Int = maxSectionBytes) throws -> [UInt8] {
        let s = [UInt8](src)
        var c = Cursor(s)
        guard try c.next(UInt32.self) == 0x184D2204 else { throw PersonalizerError.corrupt("lz4: bad frame magic") }
        let flg = try c.next(UInt8.self)
        _ = try c.next(UInt8.self)                      // BD
        guard flg >> 6 == 1 else { throw PersonalizerError.unsupported("lz4 frame version") }
        let blockChecksum = flg & 0x10 != 0
        let contentSize = flg & 0x08 != 0
        let contentChecksum = flg & 0x04 != 0
        let dictID = flg & 0x01 != 0
        if contentSize { _ = try c.take(8) }
        if dictID { _ = try c.take(4) }
        _ = try c.next(UInt8.self)                      // header checksum

        var out: [UInt8] = []
        while true {
            let raw = try c.next(UInt32.self)
            if raw == 0 { break }
            let stored = raw & 0x8000_0000 != 0
            let size = Int(raw & 0x7FFF_FFFF)
            let block = try c.take(size)
            if stored {
                guard size <= maxOutput - out.count else { throw PersonalizerError.corrupt("lz4: output too large") }
                out.append(contentsOf: block)
            } else {
                try decodeBlock(Array(block), into: &out, maxOutput: maxOutput)
            }
            if blockChecksum { _ = try c.take(4) }
        }
        if contentChecksum { _ = try c.take(4) }
        return out
    }
}

// MARK: - zstd

enum Zstd {
    static func decompress(_ data: Data, uncompressedSize: Int) throws -> Data {
        guard uncompressedSize >= 0, uncompressedSize <= maxSectionBytes else { throw PersonalizerError.corrupt("zstd: bad size") }
        if uncompressedSize == 0 { return Data() }
        var out = [UInt8](repeating: 0, count: uncompressedSize)
        let written: Int = out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                ZSTD_decompress(dst.baseAddress, dst.count, src.baseAddress, src.count)
            }
        }
        guard ZSTD_isError(written) == 0 else { throw PersonalizerError.corrupt("zstd: decompression failed") }
        return Data(out.prefix(written))
    }
}

// MARK: - LSPK

struct LSPKPackage: Sendable {
    private struct Entry: Sendable {
        var offset: UInt64, method: UInt8, sizeOnDisk: Int, size: Int
    }

    private let url: URL
    private let entries: [String: Entry]
    let names: [String]

    private static let entrySize = 272

    init(url: URL) throws {
        self.url = url
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: url) } catch { throw PersonalizerError.corrupt("cannot open package") }
        defer { try? handle.close() }
        let fileSize: UInt64
        do { fileSize = try handle.seekToEnd() } catch { throw PersonalizerError.corrupt("cannot size package") }

        let header = try Self.read(handle, at: 0, count: 22, fileSize: fileSize)
        guard header.prefix(4).elementsEqual("LSPK".utf8) else { throw PersonalizerError.corrupt("not an LSPK package") }
        let version: UInt32 = try Bytes.int(header, 4)
        guard (15...18).contains(version) else { throw PersonalizerError.unsupported("LSPK version \(version)") }
        let listOffset: UInt64 = try Bytes.int(header, 8)

        let listHead = try Self.read(handle, at: listOffset, count: 8, fileSize: fileSize)
        let numFiles = Int(try Bytes.int(listHead, 0, as: UInt32.self))
        let compressed = Int(try Bytes.int(listHead, 4, as: UInt32.self))
        guard numFiles <= 1_000_000, numFiles * Self.entrySize <= maxSectionBytes else { throw PersonalizerError.corrupt("implausible file count") }
        let block = try Self.read(handle, at: listOffset + 8, count: compressed, fileSize: fileSize)
        var table: [UInt8] = []
        try LZ4.decodeBlock(block, into: &table, maxOutput: numFiles * Self.entrySize)
        guard table.count >= numFiles * Self.entrySize else { throw PersonalizerError.corrupt("short file table") }

        var map: [String: Entry] = [:]
        var order: [String] = []
        for i in 0..<numFiles {
            let base = i * Self.entrySize
            let nameBytes = table[base..<(base + 256)].prefix { $0 != 0 }
            let name = String(decoding: nameBytes, as: UTF8.self)
            let low: UInt32 = try Bytes.int(table, base + 256)
            let high: UInt16 = try Bytes.int(table, base + 260)
            let flags: UInt8 = try Bytes.int(table, base + 263)
            let disk: UInt32 = try Bytes.int(table, base + 264)
            let unc: UInt32 = try Bytes.int(table, base + 268)
            if map[name] == nil { order.append(name) }
            map[name] = Entry(offset: UInt64(low) | (UInt64(high) << 32), method: flags & 0x0F, sizeOnDisk: Int(disk), size: Int(unc))
        }
        entries = map
        names = order
    }

    func data(for name: String) throws -> Data {
        guard let e = entries[name] else { throw PersonalizerError.corrupt("no such entry: \(name)") }
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: url) } catch { throw PersonalizerError.corrupt("cannot open package") }
        defer { try? handle.close() }
        let fileSize: UInt64
        do { fileSize = try handle.seekToEnd() } catch { throw PersonalizerError.corrupt("cannot size package") }
        let raw = try Self.read(handle, at: e.offset, count: e.sizeOnDisk, fileSize: fileSize)
        if e.method == 0 || e.size == 0 { return Data(raw) }
        switch e.method {
        case 1: throw PersonalizerError.unsupported("zlib entries")
        case 2:
            var out: [UInt8] = []
            try LZ4.decodeBlock(raw, into: &out, maxOutput: e.size)
            return Data(out)
        case 3: return try Zstd.decompress(Data(raw), uncompressedSize: e.size)
        default: throw PersonalizerError.unsupported("compression method \(e.method)")
        }
    }

    private static func read(_ handle: FileHandle, at offset: UInt64, count: Int, fileSize: UInt64) throws -> [UInt8] {
        guard count >= 0, offset <= fileSize, UInt64(count) <= fileSize - offset else { throw PersonalizerError.corrupt("range outside file") }
        do {
            try handle.seek(toOffset: offset)
            let data = try handle.read(upToCount: count) ?? Data()
            guard data.count == count else { throw PersonalizerError.corrupt("short read") }
            return [UInt8](data)
        } catch let e as PersonalizerError {
            throw e
        } catch {
            throw PersonalizerError.corrupt("read failed")
        }
    }
}

// MARK: - LSF

enum LSFValue: Sendable, Equatable {
    case string(String), int(Int64), double(Double), bool(Bool), other
}

/// A node of an LSF tree. A class for cheap tree building; used only inside one synchronous parse/digest call
/// and never sent across an actor boundary.
final class LSFNode {
    let name: String
    var attributes: [String: LSFValue] = [:]
    var children: [LSFNode] = []
    init(name: String) { self.name = name }

    func children(named n: String) -> [LSFNode] { children.filter { $0.name == n } }
    func child(named n: String) -> LSFNode? { children.first { $0.name == n } }

    /// Depth-first, self first.
    func walk(_ visit: (LSFNode) -> Void) {
        visit(self)
        for c in children { c.walk(visit) }
    }
    var descendants: [LSFNode] {
        var out: [LSFNode] = []
        walk { out.append($0) }
        return out
    }
}

enum LSF {
    private struct Attr {
        var nameIndex: Int, type: Int, length: Int, next: Int, offset: Int
    }

    static func parse(_ data: Data, keepOnly rootNames: Set<String>? = nil) throws -> [LSFNode] {
        let b = [UInt8](data)
        guard b.count >= 8, b[0..<4].elementsEqual("LSOF".utf8) else { throw PersonalizerError.corrupt("not an LSF file") }
        let version: UInt32 = try Bytes.int(b, 4)
        guard (5...7).contains(version) else { throw PersonalizerError.unsupported("LSF version \(version)") }
        var c = Cursor(b)
        c.pos = 8 + 8                                      // engine version is i64 for v5+

        var sizes: [Int] = []
        let pairs = version >= 6 ? 5 : 4
        for _ in 0..<(pairs * 2) { sizes.append(Int(try c.next(UInt32.self))) }
        let sUnc = sizes[0], sDisk = sizes[1]
        let o = version >= 6 ? 4 : 2                        // v5 has no keys pair
        let kUnc = version >= 6 ? sizes[2] : 0, kDisk = version >= 6 ? sizes[3] : 0
        let nUnc = sizes[o], nDisk = sizes[o + 1], aUnc = sizes[o + 2], aDisk = sizes[o + 3]
        let vUnc = sizes[o + 4], vDisk = sizes[o + 5]

        let compression = try c.next(UInt8.self)
        _ = try c.next(UInt8.self)
        _ = try c.next(UInt16.self)
        let metaFormat = try c.next(UInt32.self)
        let method = compression & 0x0F
        let longFormat = metaFormat == 1

        func section(_ unc: Int, _ disk: Int, chunked: Bool) throws -> [UInt8] {
            guard unc <= maxSectionBytes, disk <= maxSectionBytes else { throw PersonalizerError.corrupt("implausible section size") }
            if disk == 0 && unc != 0 { return Array(try c.take(unc)) }
            let raw = Array(try c.take(disk))
            if unc == 0 || raw.isEmpty { return [] }
            switch method {
            case 0: return raw
            case 2:
                if chunked { return try LZ4.decodeFrame(Data(raw), maxOutput: max(unc, 1)) }
                var out: [UInt8] = []
                try LZ4.decodeBlock(raw, into: &out, maxOutput: unc)
                return out
            case 3: return [UInt8](try Zstd.decompress(Data(raw), uncompressedSize: unc))
            default: throw PersonalizerError.unsupported("LSF compression \(method)")
            }
        }
        let namesB = try section(sUnc, sDisk, chunked: false)
        if version >= 6 { _ = try section(kUnc, kDisk, chunked: true) }     // keys: unused
        let nodesB = try section(nUnc, nDisk, chunked: true)
        let attrsB = try section(aUnc, aDisk, chunked: true)
        let valsB = try section(vUnc, vDisk, chunked: true)

        // Names
        var names: [[String]] = []
        var p = 0
        let bucketCount = Int(try Bytes.int(namesB, p, as: UInt32.self)); p += 4
        guard bucketCount <= namesB.count else { throw PersonalizerError.corrupt("bad bucket count") }
        for _ in 0..<bucketCount {
            let count = Int(try Bytes.int(namesB, p, as: UInt16.self)); p += 2
            var bucket: [String] = []
            for _ in 0..<count {
                let len = Int(try Bytes.int(namesB, p, as: UInt16.self)); p += 2
                bucket.append(String(decoding: try Bytes.slice(namesB, p, len), as: UTF8.self)); p += len
            }
            names.append(bucket)
        }
        func name(_ idx: Int) throws -> String {
            let bucket = idx >> 16, i = idx & 0xFFFF
            guard bucket < names.count, i < names[bucket].count else { throw PersonalizerError.corrupt("bad name index") }
            return names[bucket][i]
        }

        // Attributes
        var attrs: [Attr] = []
        if longFormat {
            for i in 0..<(attrsB.count / 16) {
                let ni: UInt32 = try Bytes.int(attrsB, i * 16)
                let tl: UInt32 = try Bytes.int(attrsB, i * 16 + 4)
                let next: Int32 = try Bytes.int(attrsB, i * 16 + 8)
                let off: UInt32 = try Bytes.int(attrsB, i * 16 + 12)
                attrs.append(Attr(nameIndex: Int(ni), type: Int(tl & 0x3F), length: Int(tl >> 6), next: Int(next), offset: Int(off)))
            }
        } else {
            var offset = 0
            var lastForNode: [Int32: Int] = [:]
            for i in 0..<(attrsB.count / 12) {
                let ni: UInt32 = try Bytes.int(attrsB, i * 12)
                let tl: UInt32 = try Bytes.int(attrsB, i * 12 + 4)
                let node: Int32 = try Bytes.int(attrsB, i * 12 + 8)
                attrs.append(Attr(nameIndex: Int(ni), type: Int(tl & 0x3F), length: Int(tl >> 6), next: -1, offset: offset))
                offset += Int(tl >> 6)
                if let prev = lastForNode[node] { attrs[prev].next = i }
                lastForNode[node] = i
            }
        }

        func value(_ a: Attr) throws -> LSFValue {
            let v = try Bytes.slice(valsB, a.offset, a.length)
            let arr = Array(v)
            switch a.type {
            case 20, 21, 22, 23, 29, 30:
                return .string(String(decoding: arr.prefix { $0 != 0 }, as: UTF8.self))
            case 1: return arr.count == 1 ? .int(Int64(arr[0])) : .other
            case 2: return arr.count == 2 ? .int(Int64(try Bytes.int(arr, 0, as: Int16.self))) : .other
            case 3: return arr.count == 2 ? .int(Int64(try Bytes.int(arr, 0, as: UInt16.self))) : .other
            case 4: return arr.count == 4 ? .int(Int64(try Bytes.int(arr, 0, as: Int32.self))) : .other
            case 5: return arr.count == 4 ? .int(Int64(try Bytes.int(arr, 0, as: UInt32.self))) : .other
            case 6: return arr.count == 4 ? .double(Double(Float(bitPattern: try Bytes.int(arr, 0, as: UInt32.self)))) : .other
            case 7: return arr.count == 8 ? .double(Double(bitPattern: try Bytes.int(arr, 0, as: UInt64.self))) : .other
            case 19: return arr.count >= 1 ? .bool(arr[0] != 0) : .other
            case 24:
                guard arr.count == 8, let x = Int64(exactly: try Bytes.int(arr, 0, as: UInt64.self)) else { return .other }
                return .int(x)
            case 26, 32: return arr.count == 8 ? .int(try Bytes.int(arr, 0, as: Int64.self)) : .other
            case 27: return arr.count == 1 ? .int(Int64(Int8(bitPattern: arr[0]))) : .other
            default: return .other
            }
        }

        // Nodes
        let nodeSize = longFormat ? 16 : 12
        let nodeCount = nodesB.count / nodeSize
        var made: [LSFNode?] = Array(repeating: nil, count: nodeCount)
        var kept = [Bool](repeating: false, count: nodeCount)
        var roots: [LSFNode] = []
        for i in 0..<nodeCount {
            let base = i * nodeSize
            let ni: UInt32 = try Bytes.int(nodesB, base)
            let parent: Int, firstAttr: Int
            if longFormat {
                parent = Int(try Bytes.int(nodesB, base + 4, as: Int32.self))
                firstAttr = Int(try Bytes.int(nodesB, base + 12, as: Int32.self))
            } else {
                firstAttr = Int(try Bytes.int(nodesB, base + 4, as: Int32.self))
                parent = Int(try Bytes.int(nodesB, base + 8, as: Int32.self))
            }
            guard parent >= -1, parent < i else { throw PersonalizerError.corrupt("bad parent index") }
            let nodeName = try name(Int(ni))
            if parent == -1 {
                kept[i] = rootNames.map { $0.contains(nodeName) } ?? true
            } else {
                kept[i] = kept[parent]
            }
            guard kept[i] else { continue }
            let node = LSFNode(name: nodeName)
            var a = firstAttr
            var steps = 0
            while a >= 0, a < attrs.count {
                steps += 1
                guard steps <= attrs.count else { throw PersonalizerError.corrupt("attribute cycle") }
                node.attributes[try name(attrs[a].nameIndex)] = try value(attrs[a])
                a = attrs[a].next
            }
            made[i] = node
            if parent == -1 { roots.append(node) } else { made[parent]?.children.append(node) }
        }
        return roots
    }
}
