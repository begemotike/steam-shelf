import struct, sys, lz4.block, zstandard, zlib, json, os

def read_lspk(path):
    """Return {name: bytes-loader} for an LSPK v18 package (BG3 save)."""
    f = open(path, 'rb')
    sig, ver, list_off, list_size, flags, prio = struct.unpack('<4sIQIBB', f.read(22))
    assert sig == b'LSPK', sig
    f.seek(list_off)
    num, comp = struct.unpack('<II', f.read(8))
    table = lz4.block.decompress(f.read(comp), uncompressed_size=num * 272)
    entries = {}
    for i in range(num):
        e = table[i*272:(i+1)*272]
        name = e[:256].split(b'\0', 1)[0].decode('utf-8', 'replace')
        off_lo, off_hi, part, fl, disk, unc = struct.unpack('<IHBBII', e[256:272])
        entries[name] = (off_lo | (off_hi << 32), fl & 0x0F, disk, unc)
    def load(name):
        off, method, disk, unc = entries[name]
        f.seek(off); raw = f.read(disk)
        if method == 0 or unc == 0: return raw
        if method == 1: return zlib.decompress(raw)
        if method == 2: return lz4.block.decompress(raw, uncompressed_size=unc)
        if method == 3: return zstandard.ZstdDecompressor().decompress(raw, max_output_size=unc)
        raise ValueError(method)
    return entries, load

if __name__ == '__main__':
    entries, load = read_lspk(sys.argv[1])
    for n, (off, m, d, u) in entries.items(): print(f"{n:40s} method={m} disk={d:>9} unc={u:>9}")
    if 'SaveInfo.json' in entries:
        print(json.dumps(json.loads(load('SaveInfo.json')), indent=1)[:2500])
