# LarianFormats

Path: [`Sources/Personalizer/LarianFormats.swift`](../../Sources/Personalizer/LarianFormats.swift) (418 lines)

Readers for the binary formats Larian games use for saves: LZ4 (block and frame), zstd (through the SwiftPM `libzstd` product), the LSPK package (`.lsv`, version 18) and the LSF binary tree (versions 5 to 7). They are Swift ports of [`tools/bg3/lspk.py`](tools-bg3.md) and `tools/bg3/lsf.py`. **Every read is bounds-checked and throws `PersonalizerError.corrupt` (or `unsupported`) instead of trapping**, because the input is untrusted file data. A global cap, `maxSectionBytes = 1 << 29` (512 MiB), bounds any single decompressed section.

## Depends on / used by

- Depends on: `libzstd` (SwiftPM, `ZSTD_decompress`, `ZSTD_isError`), [GamePersonalizer](GamePersonalizer.md) (`PersonalizerError`).
- Used by: [BG3Personalizer](BG3Personalizer.md) (`LSPKPackage`, `LSF.parse`, `LSFNode`), [Tests](Tests.md) (`LarianFormatsTests`, fixtures in `LarianFixtures`).

## Byte reading

| Item | Behaviour |
|---|---|
| `enum Bytes` | `static func int<T: FixedWidthInteger>(_ b: [UInt8], _ offset: Int, as: T.Type) throws -> T`: little-endian read at `offset`, `corrupt("read past end")` if out of range. `static func slice(_ b:_ offset:_ length:) throws -> ArraySlice<UInt8>`: `corrupt("slice out of range")`. |
| `private struct Cursor` | `bytes`, `pos`; `mutating func next<T>() throws -> T` and `take(_ n: Int) throws -> ArraySlice<UInt8>` advance `pos` using `Bytes`. |

## LZ4

`enum LZ4`

| Signature | Behaviour |
|---|---|
| `static func decodeBlock(_ src: Data, into dst: inout [UInt8], maxOutput: Int) throws` and `decodeBlock(_ s: [UInt8], ...)` | Standard LZ4 block decode. **Appends** to `dst` and resolves match offsets against *everything already in `dst`*, which is what makes linked frame blocks work. Validates: truncated length bytes, literal runs beyond the input or `maxOutput`, truncated offsets, `offset == 0` or beyond `dst`, and output size. Matches may overlap themselves (run-length), copied byte by byte. The last sequence carries literals only. `maxOutput` caps the total size of `dst`. |
| `static func decodeFrame(_ src: Data, maxOutput: Int = maxSectionBytes) throws -> [UInt8]` | LZ4 frame (magic `0x184D2204`). Parses FLG (version must be 1, else `unsupported("lz4 frame version")`), skips BD, optional content size (8 bytes), dictionary id (4), header checksum; then loops over blocks: size word `0` ends, high bit set = stored; each compressed block is decoded into the *same* growing buffer so linked blocks resolve; skips block checksums and the content checksum without verifying them. |

Apple's Compression framework is not used because it cannot decode linked frame blocks.

## zstd

`enum Zstd`: `static func decompress(_ data: Data, uncompressedSize: Int) throws -> Data`. Rejects sizes below 0 or above the cap (`corrupt("zstd: bad size")`), returns empty for size 0, calls `ZSTD_decompress` into a buffer of the declared size, throws `corrupt("zstd: decompression failed")` when `ZSTD_isError`, and returns the written prefix.

## LSPK package (`.lsv`)

`struct LSPKPackage: Sendable`: private `entries: [String: Entry]` (`offset: UInt64`, `method: UInt8`, `sizeOnDisk`, `size`), `url`, public `names: [String]` in file order, `entrySize = 272`.

Layout read by `init(url:) throws`:

| Offset | Content |
|---|---|
| header 0 | `"LSPK"` magic (else `corrupt("not an LSPK package")`) |
| 4 | version `UInt32`, must be 15 to 18 (else `unsupported("LSPK version n")`); BG3 saves are 18 |
| 8 | file-list offset `UInt64` |
| at list offset | `numFiles UInt32`, `compressedSize UInt32`, then an LZ4 *block* decoding to `numFiles * 272` bytes (sanity limits: 1,000,000 files and the section cap) |
| each 272-byte entry | name (256 bytes, NUL-terminated UTF-8), offset low `UInt32` at 256, offset high `UInt16` at 260, flags `UInt8` at 263 (low nibble = compression method), size on disk `UInt32` at 264, uncompressed size `UInt32` at 268 |

| Signature | Behaviour |
|---|---|
| `init(url: URL) throws` | Reads only the header and file table (file handle with range checks via private `read(_:at:count:fileSize:)`, which throws `corrupt("range outside file")`/`short read`). Later duplicates of a name overwrite earlier ones; `names` keeps first-seen order. |
| `func data(for name: String) throws -> Data` | `corrupt("no such entry: ...")` if absent. Reads `sizeOnDisk` bytes at the offset. Method 0 (or size 0): raw. Method 2: LZ4 block into `size`. Method 3: zstd. Method 1 (zlib): `unsupported("zlib entries")`. Other: `unsupported`. Each call opens and closes its own file handle. |

## LSF tree

| Type | Definition |
|---|---|
| `LSFValue` | `enum: Sendable, Equatable { string(String), int(Int64), double(Double), bool(Bool), other }` |
| `LSFNode` | `final class` (not `Sendable`; used only inside one synchronous parse/digest call and never sent across an actor boundary): `name`, `attributes: [String: LSFValue]`, `children`; `children(named:)`, `child(named:)`, `walk(_:)` (depth-first, self first), `descendants`. |
| `LSF` | `enum` with `static func parse(_ data: Data, keepOnly rootNames: Set<String>? = nil) throws -> [LSFNode]` |

### LSF binary layout handled by `parse`

1. Magic `"LSOF"`, version `UInt32` (5, 6 or 7; others `unsupported`). The engine version is 8 bytes (i64) for v5+, so the size block starts at offset 16.
2. Section sizes as `UInt32` pairs (uncompressed, on disk): **v6/v7 have five pairs** (names, keys, nodes, attributes, values); **v5 has four** (no keys).
3. A byte of compression flags (low nibble: 0 none, 2 LZ4, 3 zstd), a byte, a `UInt16`, then `metaFormat UInt32`; `metaFormat == 1` means the **long format** for nodes and attributes.
4. Sections in order, each possibly compressed. If the on-disk size is 0 and the uncompressed size is not, the section is stored raw. Names use an LZ4 *block*; keys (v6+), nodes, attributes and values use LZ4 *frames* (`chunked`), with `maxOutput` set to the declared size.
5. **Names**: `bucketCount UInt32` (must not exceed the section length), then per bucket a `UInt16` count and strings (`UInt16` length plus bytes). A name index is `bucket = idx >> 16`, `i = idx & 0xFFFF`.
6. **Attributes**: *long* format (16 bytes each): `nameIndex UInt32`, `typeAndLength UInt32` (type = low 6 bits, length = value >> 6), `next Int32`, `offset UInt32`. *Short* format (12 bytes): `nameIndex`, `typeAndLength`, `node Int32`; the value offset is the running sum of lengths and `next` links are rebuilt by chaining attributes with the same node index.
7. **Values** by type id: strings (20, 21, 22, 23, 29, 30: NUL-terminated UTF-8); ints 1 (u8), 2 (i16), 3 (u16), 4 (i32), 5 (u32), 24 (u64 if it fits), 26 and 32 (i64), 27 (i8); floats 6 (f32) and 7 (f64); bool 19; everything else (translated strings, UUIDs, vectors...) is `.other`. A length mismatch also yields `.other`.
8. **Nodes**: *long* format 16 bytes: `nameIndex UInt32`, `parent Int32` at +4, `next` (unused) at +8, `firstAttr Int32` at +12. *Short* format 12 bytes: `nameIndex`, `firstAttr Int32` at +4, `parent Int32` at +8. A parent must be -1 or an earlier node (`guard parent >= -1, parent < i`), otherwise `corrupt("bad parent index")`.
9. Node attributes are followed through `next` links with a step counter to reject cycles (`corrupt("attribute cycle")`).

### `keepOnly`

With `keepOnly` set, a root node is kept only if its name is in the set, and a non-root node is kept only if its parent was. `LSFNode`s are built **only for kept subtrees** (the full node table is still walked for parent links), which keeps memory low on the roughly 300,000-node `Globals.lsf` of a late-game BG3 save. Returns the kept roots in order.

## Gotchas

- Checksums in LZ4 frames are skipped, not verified; corruption shows up as decode errors or implausible values.
- Python reference differences: `tools/bg3/lsf.py` also decodes some types this port returns as `.other` (UUID type 31, translated strings 28/33, vectors 8 to 13) because the journal extraction does not need them.
- The cap applies per section, not per file; the whole `Globals.lsf` is nevertheless held in memory as `[UInt8]` copies during parsing.

## See also

[Personalizer](../architecture/personalizer.md), [tools/bg3](tools-bg3.md), [Tests](Tests.md).
