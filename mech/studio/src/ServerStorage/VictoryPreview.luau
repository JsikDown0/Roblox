-- VictoryPreview (ModuleScript, ServerStorage) — 10-30 승리포즈를 에디트 모드에서(플레이 안 누르고) 직접 둘러보기
-- 유저 10-30 "패드 밟으면 컷씬이랑 포즈가 나오게 했는데 그거 에딧 모드에서도 볼 수 있어?" · "내가 직접 수동으로 들어가서 볼 수 있는 루트만"
-- 명령 모음(보기 → 명령 모음)에 한 줄:
--   require(game.ServerStorage.VictoryPreview).play("A")       -- 무대(workspace.VictoryStage)에서 A 자세를 한 번 움직이고 마지막 자세로 멈춤("B" 도 같음)
--   require(game.ServerStorage.VictoryPreview).pose("A", 2.4)  -- 그 초의 자세로 세워 둠(초를 빼면 눈 번쩍 = 마무리 자세)
--   require(game.ServerStorage.VictoryPreview).clear()         -- 치움(저장하기 전에)
-- 카메라는 안 건드림 — 편집 카메라로 직접 돌려 보면 됨. 컷씬 카메라·승리 UI 까지 다 보려면 플레이(F5) → 시험장 주황 발판 A/B
-- 데이터 = 플레이와 같음: ReplicatedStorage.VictoryPoseData + VictoryPoseFix(A 무릎 보정) · 기체 = MechProto.AeroTemplate 복제(workspace._VictoryPreview)
-- 에디트 모드라 [실측 10-30]: Motor6D.Transform 은 파트를 안 움직임 · C0 로 돌리면 관절 자리가 0.75 어긋나고 · 편집 카메라는 스크립트로 옮긴 값을
--   몇 프레임 뒤 되돌려 놓음 → 파트를 전부 고정(Anchored)해 관절 식(Part1 = Part0·C0·T·C1⁻¹)으로 자리를 직접 놓음 · 카메라는 안 씀
-- ⚠️ 자세 식(sample)은 StarterPlayerScripts.VictoryCutsceneClient 와 같음 — 그쪽을 고치면 여기도
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local M = {}
local PELVIS_PIVOT = Vector3.new(0, 17.2, 0)
local RIG_NAME = "_VictoryPreview"
-- 플레이 컷씬이 돌리는 관절만(나머지 관절은 그대로 = 쉬는 자세) — VictoryCutsceneClient JOINTS 와 같은 목록
local DRIVEN = {}
for _, n in ipairs({ "Root", "Waist", "Neck", "ShoulderL", "ShoulderR", "ElbowL", "ElbowR", "PadL", "PadR", "HipL", "HipR",
	"KneeL", "KneeR", "AnkleL", "AnkleR", "SkirtJointFL", "SkirtJointFR", "SkirtJointSL", "SkirtJointSR", "WingJointL", "WingJointR", "Grip" }) do DRIVEN[n] = true end
local cur = nil   -- { rig, conn, hrpCF, motors(Part0 별), welds, parts, flames }

local function qcf(t, i)
	local b = i * 4
	return CFrame.new(0, 0, 0, t[b + 1], t[b + 2], t[b + 3], t[b + 4])
end
local function sample(clip, j, f)
	local t = clip.q[j]
	if not t then return CFrame.identity end
	local n = clip.frames
	local i0 = math.clamp(math.floor(f), 0, n - 1)
	local i1 = math.min(i0 + 1, n - 1)
	local a = math.clamp(f - i0, 0, 1)
	local cf = qcf(t, i0):Lerp(qcf(t, i1), a)
	if j == "Root" then
		local p = clip.rootp
		local p0 = Vector3.new(p[i0 * 3 + 1], p[i0 * 3 + 2], p[i0 * 3 + 3])
		local p1 = Vector3.new(p[i1 * 3 + 1], p[i1 * 3 + 2], p[i1 * 3 + 3])
		cf = CFrame.new(p0:Lerp(p1, a)) * cf
	end
	return cf
end
local function getClip(name)
	local DATA = require(RS:WaitForChild("VictoryPoseData"))
	local clip = DATA[name]
	if clip and name == "A" then   -- 무릎 쏴 높이 보정(플레이와 같음)
		local Fix = require(RS:WaitForChild("VictoryPoseFix"))
		local ok, c = pcall(function() return (Fix.kneelA(clip, Fix.rig(RS.MechProto.AeroTemplate))) end)
		if ok and c then clip = c else warn("[VictoryPreview] A 무릎 보정 실패 — 원본으로:", c) end
	end
	return clip
end

function M.clear()
	if cur and cur.conn then cur.conn:Disconnect() end
	cur = nil
	for _, o in ipairs(workspace:GetChildren()) do if o.Name == RIG_NAME then o:Destroy() end end
end

local function build()
	M.clear()
	local stage = workspace:FindFirstChild("VictoryStage")
	if not stage then warn("[VictoryPreview] workspace.VictoryStage 없음"); return nil end
	local rig = RS.MechProto.AeroTemplate:Clone()
	rig.Name = RIG_NAME
	for _, d in ipairs(rig:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ProximityPrompt") or d:IsA("Humanoid") then d:Destroy() end
	end
	local hrp = rig:FindFirstChild("HumanoidRootPart")
	-- 무장 상태(플레이 컷씬과 같음): 허리 뒤 라이플·손 칼 숨김
	local stowed = rig:FindFirstChild("RifleStowed", true)
	if stowed and stowed:IsA("BasePart") then stowed.Transparency = 1 end
	local saber = rig:FindFirstChild("Saber")
	local inHand = saber and saber:FindFirstChild("InHand")
	if inHand then
		for _, d in ipairs(inHand:GetDescendants()) do
			if d:IsA("BasePart") then d.Transparency = 1 elseif d:IsA("Light") or d:IsA("Trail") then d.Enabled = false end
		end
	end
	local root = rig:FindFirstChild("Root", true)
	local C = { rig = rig, hrp = hrp, by0 = {}, welds = {}, parts = {}, flames = { back = {}, leg = {} } }
	C.hrpCF = stage.CFrame * CFrame.new(PELVIS_PIVOT) * root.C0:Inverse()
	for _, d in ipairs(rig:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false end
		if d:IsA("Motor6D") and d.Part0 and d.Part1 then
			C.by0[d.Part0] = C.by0[d.Part0] or {}
			table.insert(C.by0[d.Part0], d)
		end
		if d.Name == "Flame" then
			local par = d.Parent and d.Parent.Name or ""
			table.insert(par:find("Boost") and C.flames.leg or C.flames.back, d)
		end
	end
	-- 용접으로 붙은 파트(관절 없는 것): 쉬는 자세의 상대 자리를 기억해 부모를 따라감
	local moved = {}
	for _, ms in pairs(C.by0) do for _, m in ipairs(ms) do moved[m.Part1] = true end end
	for _, w in ipairs(rig:GetDescendants()) do
		if (w:IsA("WeldConstraint") or w:IsA("Weld")) and w.Part0 and w.Part1 then
			local a, b = w.Part0, w.Part1
			if moved[b] or b == hrp then a, b = b, a end   -- 움직이는 쪽(a)에 따라가는 쪽(b)
			if not moved[b] and b ~= hrp then C.welds[#C.welds + 1] = { a, b, a.CFrame:Inverse() * b.CFrame } end
		end
	end
	rig.Parent = workspace
	cur = C
	return C
end
local function setFlames(list, on)
	for _, d in ipairs(list) do
		if d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") or d:IsA("Fire") or d:IsA("Light") then d.Enabled = on
		elseif d:IsA("BasePart") then d.Transparency = on and 0 or 1 end
	end
end
-- t 초의 자세로 파트를 놓음(관절 식 그대로, 뿌리부터)
local function apply(C, clip, t)
	local f = math.clamp(t, 0, clip.frames / clip.fps) * clip.fps
	local cf = { [C.hrp] = C.hrpCF }
	local q, i = { C.hrp }, 1
	local parts, cfs = { C.hrp }, { C.hrpCF }
	while q[i] do
		local p0 = q[i]; i += 1
		for _, m in ipairs(C.by0[p0] or {}) do
			local c = cf[p0] * m.C0 * (DRIVEN[m.Name] and sample(clip, m.Name, f) or CFrame.identity) * m.C1:Inverse()
			cf[m.Part1] = c
			parts[#parts + 1] = m.Part1; cfs[#cfs + 1] = c
			q[#q + 1] = m.Part1
		end
	end
	for _, w in ipairs(C.welds) do
		local c = (cf[w[1]] or w[1].CFrame) * w[3]
		cf[w[2]] = c
		parts[#parts + 1] = w[2]; cfs[#cfs + 1] = c
	end
	workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	local fb, fl = 0, 0
	for _, k in ipairs(clip.flames or {}) do if t >= k[1] then fb, fl = k[2], k[3] end end
	setFlames(C.flames.back, fb > 0.4); setFlames(C.flames.leg, fl > 0.4)
end
function M.pose(name, t)
	name = name or "A"
	local clip = getClip(name)
	if not clip then warn("[VictoryPreview] 클립 없음:", name); return end
	local C = build(); if not C then return end
	t = t or clip.eye or (clip.frames / clip.fps)
	apply(C, clip, t)
	print(("[VictoryPreview] %s 자세 %.2f초(전체 %.2f초) — 무대에 세워 둠. 치우기 = .clear()"):format(name, t, clip.frames / clip.fps))
end

function M.play(name)
	name = name or "A"
	local clip = getClip(name)
	if not clip then warn("[VictoryPreview] 클립 없음:", name); return end
	local C = build(); if not C then return end
	local endT = clip.frames / clip.fps
	local t0 = os.clock()
	apply(C, clip, 0)
	C.conn = RunService.Heartbeat:Connect(function()
		if cur ~= C or not C.rig.Parent then C.conn:Disconnect(); return end
		local t = os.clock() - t0
		local ok, err = pcall(apply, C, clip, t)
		if not ok then warn("[VictoryPreview] 오류 — 멈춤:", err); C.conn:Disconnect(); return end
		if t >= endT then C.conn:Disconnect() end   -- 마지막 자세로 멈춰 둠(둘러보기)
	end)
	print(("[VictoryPreview] %s 재생(%.2f초) → 마지막 자세로 멈춤. 다시 = .play · 치우기 = .clear()"):format(name, endT))
end
return M
