"""whirl_fbx.json → MechWhirlAnim(압축판): 사원수 · 위치를 int16 으로 묶어 base64 한 줄. 30fps 그대로."""
import json, base64, struct, sys, numpy as np, valk_melee2 as K
SP = "/tmp/claude-0/-home-claude/45a5ff43-da6d-586c-af9c-a80fba67e5ee/scratchpad/"
IN = sys.argv[1] if len(sys.argv) > 1 else "whirl_fbx.json"
OUT = sys.argv[2] if len(sys.argv) > 2 else "MechWhirlAnim2.lua"
d = json.load(open(SP + IN))
JN = ["Root", "Waist", "Neck", "ShoulderL", "ElbowL", "SaberGrip", "ShoulderR", "ElbowR", "HipL", "KneeL", "AnkleL", "HipR", "KneeR", "AnkleR"]
QS, PS = 32767, (int(sys.argv[3]) if len(sys.argv) > 3 else 3000)
vals = []
for fr, rt in zip(d["frames"], d["root"]):
    M = np.array(fr["Root"])
    vals += [M[1, 3] * PS, rt[0] * PS, rt[2] * PS]
    for n in JN:
        q = K.quat(np.array(fr[n])); q = q / np.linalg.norm(q)
        vals += [q[1] * QS, q[2] * QS, q[3] * QS, q[0] * QS]
iv = [int(round(max(-32767, min(32767, v)))) for v in vals]
b64 = base64.b64encode(struct.pack("<%dh" % len(iv), *iv)).decode()
per = 3 + 4 * len(JN)
src = f'''-- MechWhirlAnim (ModuleScript, MechPoses 의 자식) — 11-04 16:2x VALKYRIE E 회전베기 = Mixamo "Standing Melee Attack 360 High" FBX 그대로 옮김(유저 제공 · 전체 3.17초).
--   자동 생성 valk/valk_whirl_fbx.py → valk_whirl_fbx_export2.py(손으로 고치지 말 것). {d["fps"]}fps · 좌우 거울(사람 오른손 칼 → 기체 왼손) · 앞 = −Z
--   DATA = int16 묶음 base64 — 한 칸 = Root 높이 · HRP 수평 이동(오른쪽 +X, 뒤 +Z) · 관절 14개 사원수(x, y, z, w). 위치 ÷{PS} · 사원수 ÷{QS}
--   frames[i] = 관절 → CFrame(Transform) · root[i] = 첫 칸 기준 HRP 수평 이동(스터드, 기체 정면 기준 — 내 기체 화면이 이 속도로 HRP 를 실제로 움직임, MechValkyrie)
local JN = {{ {", ".join('"' + n + '"' for n in JN)} }}
local DATA = "{b64}"
local B = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local inv = {{}}
for i = 1, 64 do inv[string.byte(B, i)] = i - 1 end
local bytes = table.create(math.floor(#DATA * 3 / 4))
for i = 1, #DATA, 4 do
	local a, b, c, d = inv[string.byte(DATA, i)], inv[string.byte(DATA, i + 1)], inv[string.byte(DATA, i + 2)] or 0, inv[string.byte(DATA, i + 3)] or 0
	local n = a * 262144 + b * 4096 + c * 64 + d
	table.insert(bytes, bit32.rshift(n, 16)); table.insert(bytes, bit32.band(bit32.rshift(n, 8), 255)); table.insert(bytes, bit32.band(n, 255))
end
local function i16(k) local v = bytes[2 * k - 1] + bytes[2 * k] * 256; if v >= 32768 then v -= 65536 end return v end
local PER = {per}
local NF = {len(d["frames"])}
local frames, root = {{}}, {{}}
for f = 0, NF - 1 do
	local base = f * PER
	local y = i16(base + 1) / {PS}
	root[f + 1] = Vector3.new(i16(base + 2) / {PS}, 0, i16(base + 3) / {PS})
	local F, k = {{}}, base + 4
	for _, n in ipairs(JN) do
		local qx, qy, qz, qw = i16(k) / {QS}, i16(k + 1) / {QS}, i16(k + 2) / {QS}, i16(k + 3) / {QS}
		F[n] = CFrame.new(0, (n == "Root") and y or 0, 0, qx, qy, qz, qw)
		k += 4
	end
	frames[f + 1] = F
end
return {{ fps = {d["fps"]}, frames = frames, root = root, n = NF, length = (NF - 1) / {d["fps"]} }}
'''
open("/home/claude/valk/out/" + OUT, "w").write(src)
print(len(src), len(b64))
