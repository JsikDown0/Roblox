"""fbxbin.py — 바이너리 FBX(7.x) 최소 파서: 노드 트리 + 속성(배열은 zlib 해제)."""
import struct, zlib
import numpy as np

class Node:
    __slots__ = ("name", "props", "children")
    def __init__(s, name, props, children): s.name, s.props, s.children = name, props, children
    def find(s, name): return [c for c in s.children if c.name == name]
    def first(s, name):
        for c in s.children:
            if c.name == name: return c
    def __repr__(s): return f"<{s.name} {s.props[:3]} {len(s.children)}>"

def parse(path):
    d = open(path, "rb").read()
    ver = struct.unpack_from("<I", d, 23)[0]
    big = ver >= 7500
    pos = 27
    def read_prop(p):
        t = chr(d[p]); p += 1
        if t == "Y": return struct.unpack_from("<h", d, p)[0], p + 2
        if t == "C": return bool(d[p]), p + 1
        if t == "I": return struct.unpack_from("<i", d, p)[0], p + 4
        if t == "F": return struct.unpack_from("<f", d, p)[0], p + 4
        if t == "D": return struct.unpack_from("<d", d, p)[0], p + 8
        if t == "L": return struct.unpack_from("<q", d, p)[0], p + 8
        if t in "SR":
            n = struct.unpack_from("<I", d, p)[0]; p += 4
            v = d[p:p + n]; p += n
            return (v.decode("utf-8", "replace") if t == "S" else v), p
        if t in "fdlib":
            n, enc, clen = struct.unpack_from("<III", d, p); p += 12
            raw = d[p:p + clen]; p += clen
            if enc == 1: raw = zlib.decompress(raw)
            dt = {"f": "<f4", "d": "<f8", "l": "<i8", "i": "<i4", "b": "<i1"}[t]
            return np.frombuffer(raw, dtype=dt, count=n).copy(), p
        raise ValueError(t)
    def read_node(p):
        if big:
            end, nprop, plen = struct.unpack_from("<QQQ", d, p); p += 24
        else:
            end, nprop, plen = struct.unpack_from("<III", d, p); p += 12
        nl = d[p]; p += 1
        name = d[p:p + nl].decode(); p += nl
        if end == 0: return None, p
        props = []
        for _ in range(nprop):
            v, p = read_prop(p); props.append(v)
        kids = []
        sentinel = 25 if big else 13
        while p < end:
            if end - p == sentinel and d[p:p + sentinel] == b"\0" * sentinel: p += sentinel; break
            c, p = read_node(p)
            if c is None: break
            kids.append(c)
        return Node(name, props, kids), end
    top = []
    while pos < len(d) - 200:
        n, pos = read_node(pos)
        if n is None: break
        top.append(n)
    return ver, top
