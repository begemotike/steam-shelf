# tools/bg3

Path: [`tools/bg3/`](../../tools/bg3) (2 Python files: `lspk.py`, `lsf.py`)

Python reference implementations of the Larian save formats, used to understand the formats and to cross-check the Swift port in [LarianFormats](LarianFormats.md) and [BG3Personalizer](BG3Personalizer.md) against real saves (the `--dump-digest` debug flag exists for that comparison). They also generated the synthetic fixtures in `Tests/LarianFixtures.swift`. They are developer tools, not shipped and not run by tests. Dependencies (not vendored): `lz4`, `zstandard`, and the standard library (`struct`, `zlib`, `uuid`, `json`).

## Depends on / used by

- Depends on: Python 3 with `lz4` and `zstandard` packages.
- Used by: developers; informs [LarianFormats](LarianFormats.md); fixture generation for [Tests](Tests.md).

## `lspk.py`

| Function | Behaviour |
|---|---|
| `read_lspk(path) -> (entries, load)` | Reads the 22-byte header (`<4sIQIBB`: signature, version, file-list offset, list size, flags, priority), asserts `LSPK`, reads the file table at the list offset (`num`, `compressed` as two `uint32`, an LZ4 block of `num * 272` bytes). Each 272-byte entry: 256-byte NUL-terminated name, then `<IHBBII` (offset low 32 bits, offset high 16 bits, part, flags, size on disk, uncompressed size); offset = low | (high << 32); method = flags & 0x0F. Returns `entries` (`name -> (offset, method, disk, unc)`) and a `load(name)` closure that handles method 0 (stored), 1 (zlib), 2 (LZ4 block), 3 (zstd). |
| `__main__` | Prints each entry with method and sizes and, if present, the first 2,500 characters of `SaveInfo.json` pretty-printed. Usage: `python3 lspk.py <save.lsv>`. |

## `lsf.py`

| Item | Behaviour |
|---|---|
| `class Node` | `name`, `attrs`, `children`, `parent`; `find(name)`, `walk()`. |
| `_decomp(raw, unc, method, chunked)` | zero-length guards; method 0 raw, 1 zlib, 2 LZ4 (frame when `chunked`, else block with `uncompressed_size`), 3 zstd. |
| `parse_lsf(data) -> [Node]` | Asserts `LSOF`. For version 5 and above skips 8 bytes of engine version; reads ten `uint32` section sizes for v6+ (names, keys, nodes, attributes, values) or eight for v5; then `<BBHI` (compression, two unused, metadata format). Sections are read in order (stored raw when disk size is 0). Names: bucket table. Attributes: 16-byte records in the long format (`meta_fmt == 1`), else 12-byte records with computed offsets and node-chained `next`. Values by type id, including UUID (31), translated strings (28, 33) and int/float vectors (8 to 13), which the Swift port leaves as "other". Nodes: 16-byte (long) or 12-byte records; attributes are followed through the `next` chain; parent links build the tree and `-1` parents are roots. |

## Differences from the Swift port

The Swift port adds bounds checks everywhere, size caps (512 MiB per section), cycle detection on attribute chains, a `keepOnly` filter that avoids building nodes outside chosen roots, and stricter version checks (LSPK 15 to 18; LSF 5 to 7). The Python tools do none of these and trust their input. The Swift port reads fewer value types because the journal extraction needs only strings, integers and booleans.

## See also

[Personalizer](../architecture/personalizer.md), [LarianFormats](LarianFormats.md), [Tests](Tests.md).
