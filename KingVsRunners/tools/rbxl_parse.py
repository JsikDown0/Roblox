"""Minimal Roblox binary place (.rbxl) parser: instances, Name/Source/Disabled/Enabled/RunContext, parent tree."""
import struct, sys, json
import lz4.block, zstandard

def read_chunks(data):
    assert data[:8] == b"<roblox!", "not binary rbxl"
    pos = 32
    while pos < len(data):
        name = data[pos:pos+4]; clen, ulen = struct.unpack_from("<II", data, pos+4); pos += 16
        if clen == 0:
            body = data[pos:pos+ulen]; pos += ulen
        else:
            raw = data[pos:pos+clen]; pos += clen
            if raw[:4] == b"\x28\xb5\x2f\xfd":
                body = zstandard.ZstdDecompressor().decompress(raw, max_output_size=ulen)
            else:
                body = lz4.block.decompress(raw, uncompressed_size=ulen)
        yield name, body
        if name == b"END\0":
            break

def interleaved_i32(buf, off, n):
    out = []
    for i in range(n):
        b = bytes(buf[off + k*n + i] for k in range(4))
        x = int.from_bytes(b, "big")
        out.append((x >> 1) ^ -(x & 1))
    return out, off + 4*n

def refs(buf, off, n):
    vals, off = interleaved_i32(buf, off, n)
    acc = 0; out = []
    for v in vals:
        acc += v; out.append(acc)
    return out, off

def rstr(buf, off):
    (l,) = struct.unpack_from("<I", buf, off)
    return bytes(buf[off+4:off+4+l]), off+4+l

WANT = {"Name", "Source", "Disabled", "Enabled", "RunContext", "LinkedSource"}

def parse(path):
    data = open(path, "rb").read()
    classes = {}  # id -> (name, [refs])
    inst = {}     # ref -> dict
    parent = {}
    for name, body in read_chunks(data):
        if name == b"INST":
            cid, = struct.unpack_from("<I", body, 0)
            cname, off = rstr(body, 4)
            off += 1  # format
            n, = struct.unpack_from("<I", body, off); off += 4
            rl, off = refs(body, off, n)
            cname = cname.decode()
            classes[cid] = (cname, rl)
            for r in rl:
                inst[r] = {"ClassName": cname}
        elif name == b"PROP":
            cid, = struct.unpack_from("<I", body, 0)
            pname, off = rstr(body, 4); pname = pname.decode()
            if pname not in WANT:
                continue
            t = body[off]; off += 1
            cname, rl = classes[cid]
            if t == 0x01:
                for r in rl:
                    s, off = rstr(body, off)
                    inst[r][pname] = s.decode("utf-8", "replace")
            elif t == 0x02:
                for i, r in enumerate(rl):
                    inst[r][pname] = bool(body[off+i])
            elif t == 0x12:  # enum
                vals = []
                n = len(rl)
                for i in range(n):
                    vals.append(int.from_bytes(bytes(body[off + k*n + i] for k in range(4)), "big"))
                for r, v in zip(rl, vals):
                    inst[r][pname] = v
        elif name == b"PRNT":
            n, = struct.unpack_from("<I", body, 1)
            ch, off = refs(body, 5, n)
            pa, off = refs(body, off, n)
            for c, p in zip(ch, pa):
                parent[c] = p
    return inst, parent

if __name__ == "__main__":
    inst, parent = parse(sys.argv[1])
    for r, d in inst.items():
        d["Parent"] = parent.get(r, -1)
    json.dump({str(k): v for k, v in inst.items()}, open(sys.argv[2], "w"), ensure_ascii=False)
    print(len(inst), "instances")
