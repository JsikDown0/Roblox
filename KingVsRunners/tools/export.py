"""Export scripts from parsed tree into a readable folder mirror (Rojo naming)."""
import json, re, os, sys, hashlib, collections

tree = json.load(open(sys.argv[1]))
OUT = sys.argv[2]
SCRIPT = {"Script", "LocalScript", "ModuleScript"}

def chain(r):
    out = []
    while r != "-1" and r in tree:
        out.append(r); r = str(tree[r]["Parent"])
    return list(reversed(out))

def path(r):
    return "/".join(tree[x].get("Name", "?") for x in chain(r))

# ---- exclusion rules -------------------------------------------------------
BACKUP = re.compile(r"/_Archive|/_Backup_|_BACKUP$|/_TestRigs/|_OLD_DISABLED$")
TEST_DISABLED = re.compile(r"(^|/)_|Test|Diag|Probe|Tuner|Harness|__SoundScan|PerfTest")
THIRD_PARTY = [
    ("Roblox default Animate", re.compile(r"humanoidAnimateR15Moods|^function\s+waitForChild\(parent, childName\)")),
    ("Quenty (toolbox)", re.compile(r"@Quenty|Created by Quenty|ColorfulBody")),
    ("Luckymaxer (toolbox)", re.compile(r"^--Made by Luckymaxer")),
    ("ActualFreedom flag (toolbox)", re.compile(r"^--ActualFreedom")),
    ("Toolbox diamond sword", re.compile(r"^--It's raining diamonds!|^Diamond = script.Parent")),
    ("Toolbox AC-130 prop", re.compile(r"^while true do\s*\n\s*for i = 1, 360 do")),
]

rows, excluded = [], collections.defaultdict(list)
for r, d in tree.items():
    if d["ClassName"] not in SCRIPT:
        continue
    p = path(r); src = d.get("Source", "")
    if BACKUP.search(p):
        excluded["백업 사본"].append(p); continue
    top_level = re.match(r"^(ServerScriptService|StarterPlayer/StarterPlayerScripts)/[^/]+$", p)
    if top_level and d.get("Disabled") is True and TEST_DISABLED.search(p.split("/")[-1]):
        excluded["꺼져 있는 테스트·진단 스크립트"].append(p); continue
    tp = next((lab for lab, rx in THIRD_PARTY if rx.search(src.lstrip())), None)
    if tp:
        excluded[f"외부 코드: {tp}"].append(p); continue
    if not src.strip():
        excluded["빈 스크립트"].append(p); continue
    rows.append((p, r))

# ---- dedupe identical sources (skin variants / preview copies) -------------
def pref(p):  # prefer real item over preview copy, then alphabetical
    return (p.startswith("ReplicatedStorage/SkinPreviews"), p)
groups = collections.defaultdict(list)
for p, r in rows:
    groups[hashlib.sha1(tree[r]["Source"].encode()).hexdigest()].append((p, r))
keep, dups = [], []
for g in groups.values():
    g.sort(key=lambda x: pref(x[0]))
    keep.append(g[0])
    if len(g) > 1:
        dups.append((g[0][0], [x[0] for x in g[1:]]))

# ---- write -----------------------------------------------------------------
def safe(n):
    n = re.sub(r'[<>:"\\|?*\x00-\x1f/]', "_", n).strip().rstrip(".")
    return n or "_"
EXT = {"Script": ".server.luau", "LocalScript": ".client.luau", "ModuleScript": ".luau"}
keep_refs = {r for _, r in keep}
has_script_child = set()
for r in keep_refs:
    for a in chain(r)[:-1]:
        if tree[a]["ClassName"] in SCRIPT:
            has_script_child.add(a)

used = set(); total = 0
for p, r in sorted(keep, key=lambda x: x[0]):
    parts = []
    for a in chain(r)[:-1]:
        parts.append(safe(tree[a].get("Name", "?")))
    d = tree[r]; ext = EXT[d["ClassName"]]
    if r in has_script_child:
        rel = os.path.join(*parts, safe(d["Name"]), "init" + ext)
    else:
        rel = os.path.join(*parts, safe(d["Name"]) + ext)
    base, i = rel, 2
    while rel.lower() in used:
        rel = base.replace(ext, f"_{i}{ext}"); i += 1
    used.add(rel.lower())
    fp = os.path.join(OUT, "src", rel)
    os.makedirs(os.path.dirname(fp), exist_ok=True)
    src = d["Source"].replace("\r\n", "\n")
    open(fp, "w", encoding="utf-8").write(src if src.endswith("\n") else src + "\n")
    total += len(src)

# ---- report ----------------------------------------------------------------
json.dump({"excluded": excluded, "duplicates": dups}, open("work/export_report.json", "w"), ensure_ascii=False, indent=1)
print("written", len(keep), "files,", total, "chars")
for k, v in excluded.items():
    print(f"  excluded {len(v):3}  {k}")
print(f"  merged duplicates: {sum(len(x[1]) for x in dups)} copies in {len(dups)} groups")
