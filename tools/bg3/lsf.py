import struct, lz4.block, lz4.frame, zstandard, zlib, uuid

class Node:
    __slots__ = ('name', 'attrs', 'children', 'parent')
    def __init__(self, name): self.name = name; self.attrs = {}; self.children = []; self.parent = None
    def find(self, name):
        for c in self.children:
            if c.name == name: yield c
    def walk(self):
        yield self
        for c in self.children: yield from c.walk()

def _decomp(raw, unc, method, chunked):
    if unc == 0: return b''
    if not raw: return b''
    if method == 0: return raw
    if method == 1: return zlib.decompress(raw)
    if method == 2:
        return lz4.frame.decompress(raw) if chunked else lz4.block.decompress(raw, uncompressed_size=unc)
    if method == 3: return zstandard.ZstdDecompressor().decompressobj().decompress(raw)
    raise ValueError(method)

def parse_lsf(data):
    assert data[:4] == b'LSOF'
    ver = struct.unpack_from('<I', data, 4)[0]
    pos = 8 + (8 if ver >= 5 else 4)
    if ver >= 6:
        (s_unc, s_disk, k_unc, k_disk, n_unc, n_disk, a_unc, a_disk, v_unc, v_disk) = struct.unpack_from('<10I', data, pos); pos += 40
    else:
        (s_unc, s_disk, n_unc, n_disk, a_unc, a_disk, v_unc, v_disk) = struct.unpack_from('<8I', data, pos); pos += 32; k_unc = k_disk = 0
    comp, _u2, _u3, meta_fmt = struct.unpack_from('<BBHI', data, pos); pos += 8
    method = comp & 0x0F
    def section(unc, disk, chunked):
        nonlocal pos
        if disk == 0 and unc != 0:
            raw = data[pos:pos+unc]; pos += unc; return raw
        raw = data[pos:pos+disk]; pos += disk
        return _decomp(raw, unc, method, chunked)
    names_b = section(s_unc, s_disk, False)
    keys_b = section(k_unc, k_disk, True) if ver >= 6 else b''
    nodes_b = section(n_unc, n_disk, True)
    attrs_b = section(a_unc, a_disk, True)
    vals_b = section(v_unc, v_disk, True)
    # names
    names = []; p = 0
    nb = struct.unpack_from('<I', names_b, p)[0]; p += 4
    for _ in range(nb):
        cnt = struct.unpack_from('<H', names_b, p)[0]; p += 2
        bucket = []
        for _ in range(cnt):
            ln = struct.unpack_from('<H', names_b, p)[0]; p += 2
            bucket.append(names_b[p:p+ln].decode('utf-8', 'replace')); p += ln
        names.append(bucket)
    def nm(idx): return names[idx >> 16][idx & 0xFFFF]
    long_fmt = (meta_fmt == 1)
    # attributes
    attrs = []
    if long_fmt:
        for i in range(len(attrs_b) // 16):
            ni, tl, nxt, off = struct.unpack_from('<IIiI', attrs_b, i*16)
            attrs.append((ni, tl & 0x3F, tl >> 6, nxt, off))
    else:
        off = 0; prev = {}
        raw = []
        for i in range(len(attrs_b) // 12):
            ni, tl, node = struct.unpack_from('<IIi', attrs_b, i*12)
            raw.append([ni, tl & 0x3F, tl >> 6, -1, off, node]); off += tl >> 6
            if node in prev: raw[prev[node]][3] = i
            prev[node] = i
        attrs = [tuple(r[:5]) for r in raw]; first_attr = {}
        for i, r in enumerate(raw): first_attr.setdefault(r[5], i)
    def value(t, ln, off):
        b = vals_b[off:off+ln]
        try:
            if t in (20, 21, 22, 23, 29, 30): return b.split(b'\0', 1)[0].decode('utf-8', 'replace')
            if t == 1: return b[0]
            if t == 2: return struct.unpack('<h', b)[0]
            if t == 3: return struct.unpack('<H', b)[0]
            if t == 4: return struct.unpack('<i', b)[0]
            if t == 5: return struct.unpack('<I', b)[0]
            if t == 6: return struct.unpack('<f', b)[0]
            if t == 7: return struct.unpack('<d', b)[0]
            if t == 19: return b[0] != 0
            if t in (24,): return struct.unpack('<Q', b)[0]
            if t in (26, 32): return struct.unpack('<q', b)[0]
            if t == 27: return struct.unpack('<b', b)[0]
            if t == 31: return str(uuid.UUID(bytes_le=bytes(b)))
            if t in (28, 33):
                if ln >= 6:
                    # version u16, handle length i32, handle
                    hl = struct.unpack_from('<i', b, 2)[0]; return b[6:6+max(hl-1,0)].decode('utf-8','replace')
                return ''
            if 8 <= t <= 13: 
                n = ln // 4; return struct.unpack('<%d%s' % (n, 'i' if t <= 10 else 'f'), b)
        except Exception: return None
        return ('raw', t, ln)
    # nodes
    nodes = []; roots = []
    size = 16 if long_fmt else 12
    for i in range(len(nodes_b) // size):
        if long_fmt: ni, parent, nxt, fa = struct.unpack_from('<Iiii', nodes_b, i*16)
        else:
            ni, fa, parent = struct.unpack_from('<Iii', nodes_b, i*12)
        n = Node(nm(ni)); nodes.append(n)
        a = fa
        while a != -1 and a < len(attrs):
            ani, t, ln, nxt2, off = attrs[a]
            n.attrs[nm(ani)] = value(t, ln, off)
            a = nxt2
        if parent == -1: roots.append(n)
        else: n.parent = nodes[parent]; nodes[parent].children.append(n)
    return roots
