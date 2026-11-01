-- MechFelsen (ModuleScript, MechClient 의 자식) — 10-30 HT-01 FELSEN 궁극기(X)의 화면 쪽
--   지금 = "돌진 내려찍기"(템플릿 속성 Ultimate = "AxeCharge", 아래 돌진 절) · 보관 = "도약 내려찍기"(AxeLeap — 속성만 바꾸면 다시 켜짐)
-- (보관) 도약 내려찍기:
-- 유저 10-30 16:25 "조준 위치를 향해 도끼를 번쩍 머리 위로 들고 뛰어들어서 도착하면 쿵 하면서 도끼를 내려찍고 지반을 흔드는 거야.
--   직격당한 적일수록 카메라 흔들림 + 큰 데미지" · 착지 원은 적에게도 보임 · 공중 적은 부딪히면 직격 · 부딪혀도 그대로 날아감 · 1.2초 · 준비 동작 없음
-- 규칙·수치 = MechConfig CFG.Leap · 판정 = MechServer LEAP. MechClient Source 20만 자 한도 때문에 따로 둠(MechFalco 와 같은 형태)
-- MechClient 가 init(ctx) 로 넘기는 것만 씀: mech() · fxPart(색, 크기, CFrame, 모양) · spark(자리, 법선) · shake(세기)
-- ⚠️ require 만으로는 아무것도 안 돎(RenderStepped·이벤트 연결은 init 에서) — 에디트에서 순수 함수만 시험할 수 있게
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Proto = RS:WaitForChild("MechProto")
local CFG = require(Proto:WaitForChild("MechConfig"))
local Remotes = Proto:WaitForChild("Remotes")

local FE = {}
local ctx = nil
FE.ORANGE, FE.CORE = Color3.fromRGB(255, 140, 40), Color3.fromRGB(255, 232, 190)   -- 중장갑 발광 주황(도끼 열선과 같은 계열)
FE.DUST, FE.ROCK = Color3.fromRGB(150, 138, 122), Color3.fromRGB(110, 104, 98)

-- ================= 도끼 자세 =================
-- 새 자세 없음 — 도끼 두 손 1타(MechPoses SHAPES.Heavy.combo2h slash1: 겨눔 R → 머리 위 W1 → V1 → 내리침 S1 → 땅 F1d → 겨눔)를 시각만 바꿔 씀:
--   뛰는 순간부터 0.3초에 머리 위로(0 ~ 0.42) · 날아가는 동안 W1 그대로(0.46) · 착지 0.14초 전부터 내리침(0.50 ~ 0.64, S1 = 날이 앞 아래)
--   · 착지하면 땅까지(0.64 ~ 0.78) · 잠깐 멈춤 · 겨눔으로(~ 1.39) = 착지 뒤 Recover 0.75초
-- MechClient animOne 이 meleeElapsed 대신 이 값을 씀 → 도끼 두 손 자세·열선·오른손 IK 가 근접 1타와 똑같이 그려짐(모든 화면, 서버 속성 시각)
local function leapMelee(m)
	local ph, k = CFG.leapPhase(m)
	if not ph then return nil end
	local L = CFG.Leap
	if ph == "fly" then
		local e = k * L.Time
		if e < 0.3 then return 0.42 * (e / 0.3), "slash1" end
		if e < L.Time - 0.14 then return 0.46, "slash1" end
		return 0.50 + (e - (L.Time - 0.14)), "slash1"
	end
	return math.min(1.39, 0.64 + k * L.Recover), "slash1"
end

-- ================= 내 기체 비행(조종 화면) =================
-- 서버 속성 LeapAt(서버 시각) · LeapTo(착지 서 있는 자리)대로 포물선(꼭대기 CFG.Leap.Height)을 직접 따라감(PlatformStand · 매 프레임 CFrame — 앞차기 공중제비와 같은 방식)
-- 늦게 봤으면(지연) 처음 본 자리에서 남은 시간에 포물선을 다시 맞춤 → 첫 프레임에 위로 튀지 않음(GR.flipDrive 와 같음). 착지 = LeapTo 에 놓고 풀어 줌
local D = nil   -- { at, from, k0, flat, yaw }
FE.driving = false
local function leapReset() D = nil; FE.driving = false end
local function leapYaw(m)   -- 날아가는 동안 몸 방향 = 착지 쪽(faceAlign 이 카메라 쪽으로 비틀지 않게)
	if not (D and m and m:GetAttribute("LeapAt") == D.at and CFG.leapPhase(m) == "fly") then return nil end
	return D.yaw
end
local function leapDrive(m, root, hum)
	local ph, k = CFG.leapPhase(m)
	local at = m:GetAttribute("LeapAt")
	local to = m:GetAttribute("LeapTo")
	if ph ~= "fly" or typeof(to) ~= "Vector3" then
		if FE.driving then
			FE.driving = false
			hum.PlatformStand = false
			if D and D.at == at and typeof(to) == "Vector3" then root.CFrame = CFrame.lookAlong(to, D.flat) end   -- 착지 자리에 정확히
			root.AssemblyLinearVelocity = Vector3.zero
		end
		return false
	end
	if not D or D.at ~= at then
		local fl = Vector3.new(to.X - root.Position.X, 0, to.Z - root.Position.Z)
		if fl.Magnitude < 0.5 then
			local lv = root.CFrame.LookVector
			fl = Vector3.new(lv.X, 0, lv.Z)
		end
		fl = fl.Magnitude > 0.01 and fl.Unit or Vector3.new(0, 0, -1)
		D = { at = at, from = root.Position, k0 = math.min(k, 0.9), flat = fl, yaw = math.atan2(-fl.X, -fl.Z) }
	end
	FE.driving = true
	hum.PlatformStand = true
	local u = math.clamp((k - D.k0) / (1 - D.k0), 0, 1)
	local pos = D.from:Lerp(to, u) + Vector3.new(0, 4 * CFG.Leap.Height * u * (1 - u), 0)
	root.AssemblyLinearVelocity = Vector3.zero
	root.CFrame = CFrame.lookAlong(pos, D.flat)
	return true
end

-- ================= 착지 원(모든 화면 — 적에게도) =================
-- 쏜 기체 속성 LeapGround(원 가운데 땅) · LeapAt → 날아가는 동안: 테두리(반지름 Radius, 주황 토막 32) + 옅은 바닥 + 가운데 원(CoreRadius = 가장 센 곳)
--   + 안에서 바깥으로 차오르는 판(다 차면 내려찍음 = 남은 시간). 보이는 원 = 판정 원(수평 Radius) — 서버와 같은 값
local rings = {}   -- [기체] = { at, border = {}, base, core, fill }
local function disc(color, d, tr, y, center)
	local p = ctx.fxPart(color, Vector3.new(0.15, d, d), CFrame.new(center + Vector3.new(0, y, 0)) * CFrame.Angles(0, 0, math.rad(90)), Enum.PartType.Cylinder)
	p.Transparency = tr
	return p
end
local function dropRing(m)
	local r = rings[m]
	if not r then return end
	for _, p in ipairs(r.border) do p:Destroy() end
	r.base:Destroy(); r.core:Destroy(); r.fill:Destroy()
	rings[m] = nil
end
local function buildRing(at, c)
	local L = CFG.Leap
	local R = L.Radius
	local r = { at = at, c = c, border = {} }
	local N = 32
	for i = 1, N do
		local a0, a1 = (i - 1) / N * 2 * math.pi, i / N * 2 * math.pi
		local p0 = c + Vector3.new(math.cos(a0) * R, 0.35, math.sin(a0) * R)
		local p1 = c + Vector3.new(math.cos(a1) * R, 0.35, math.sin(a1) * R)
		local seg = ctx.fxPart(FE.ORANGE, Vector3.new(0.7, 0.3, (p1 - p0).Magnitude + 0.15), CFrame.lookAt((p0 + p1) / 2, p1))
		seg.Transparency = 0.1
		r.border[i] = seg
	end
	r.base = disc(FE.ORANGE, 2 * R, 0.85, 0.2, c)
	r.core = disc(FE.CORE, 2 * L.CoreRadius, 0.6, 0.3, c)
	r.fill = disc(FE.ORANGE, 0.2, 0.6, 0.25, c)
	return r
end
local function stepRings()
	local seen = {}
	for _, m in ipairs(CollectionService:GetTagged("Mech")) do
		local ph, k = CFG.leapPhase(m)
		local c = m:GetAttribute("LeapGround")
		if ph == "fly" and typeof(c) == "Vector3" then
			seen[m] = true
			local at = m:GetAttribute("LeapAt")
			local r = rings[m]
			if r and r.at ~= at then dropRing(m); r = nil end
			if not r then r = buildRing(at, c); rings[m] = r end
			local d = math.max(0.2, 2 * CFG.Leap.Radius * k)
			r.fill.Size = Vector3.new(0.15, d, d)
			local blink = (math.floor(os.clock() * 8) % 2 == 0) and 0.05 or 0.25   -- 테두리 깜빡(경고)
			for _, s in ipairs(r.border) do s.Transparency = blink end
		end
	end
	for m in pairs(rings) do
		if not seen[m] then dropRing(m) end
	end
end

-- ================= 맞음 이펙트 =================
local function burst(pos, color, size, life)
	local b = ctx.fxPart(color, Vector3.one * 2, CFrame.new(pos), Enum.PartType.Ball)
	b.Transparency = 0.1
	TweenService:Create(b, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * size, Transparency = 1 }):Play()
	Debris:AddItem(b, life + 0.02)
end
-- 날아가다 공중 적에 부딪힘(서버 MechFX "leapAirHit")
local function airFx(m, victim, pos)
	burst(pos, FE.CORE, 14, 0.25)
	if typeof(ctx.spark) == "function" then ctx.spark(pos, Vector3.yAxis) end
	local me = ctx.mech()
	if victim == me then ctx.shake(1.0) elseif m == me then ctx.shake(0.6) end
end
-- 내려찍음(서버 MechFX "leapSlam", vs = 맞은 기체들 · ks = 세기 0~1 — 가운데 1): 주황 번쩍 + 흙먼지 고리가 원 밖까지 퍼짐 + 돌 조각이 튐
--   흔들림 = 맞은 내 기체는 0.4 + 0.8 × 세기 · 쏜 내 기체 0.9 · 안 맞았어도 가까우면(60 안) 조금
local function slamFx(m, c, vs, ks, R)
	R = R or CFG.Leap.Radius
	burst(c + Vector3.new(0, 2, 0), FE.CORE, 18, 0.3)
	local ring = ctx.fxPart(FE.DUST, Vector3.new(1.2, 6, 6), CFrame.new(c + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90)), Enum.PartType.Cylinder)
	ring.Material = Enum.Material.SmoothPlastic
	ring.Transparency = 0.25
	TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.4, R * 2.4, R * 2.4), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.52)
	local glow = ctx.fxPart(FE.ORANGE, Vector3.new(0.3, 4, 4), CFrame.new(c + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90)), Enum.PartType.Cylinder)
	glow.Transparency = 0.2
	TweenService:Create(glow, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.2, R * 2, R * 2), Transparency = 1 }):Play()
	Debris:AddItem(glow, 0.37)
	for i = 1, 14 do
		local a = math.random() * 2 * math.pi
		local dir = Vector3.new(math.cos(a), 0.6 + math.random() * 0.8, math.sin(a)).Unit
		local s = 0.8 + math.random() * 1.6
		local p = ctx.fxPart(FE.ROCK, Vector3.new(s, s, s), CFrame.new(c + Vector3.new(math.cos(a) * 3, 1, math.sin(a) * 3)) * CFrame.Angles(math.random() * 6, math.random() * 6, 0))
		p.Material = Enum.Material.Slate
		local life = 0.45 + math.random() * 0.25
		TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = p.CFrame + dir * (10 + math.random() * 10), Transparency = 1 }):Play()
		Debris:AddItem(p, life + 0.02)
	end
	if typeof(ctx.spark) == "function" then ctx.spark(c, Vector3.yAxis) end
	local me = ctx.mech()
	local s = 0
	if me == m then s = 0.9 end
	if type(vs) == "table" and type(ks) == "table" then
		for i, v in ipairs(vs) do
			if v == me then s = math.max(s, 0.4 + 0.8 * (tonumber(ks[i]) or 0)) end
		end
	end
	local mr = me and me:FindFirstChild("HumanoidRootPart")
	if s == 0 and mr then
		local d = (mr.Position - c).Magnitude
		if d < 60 then s = 0.3 * (1 - d / 60) end
	end
	if s > 0 then ctx.shake(s) end
end

-- ================= 10-30 돌진 내려찍기 (Ultimate = "AxeCharge") — 규칙·수치 = MechConfig CFG.Charge · 판정 = MechServer CHG =================
-- 유저 10-30 16:58 사이온 궁극기 — 긴 선딜(1초) + 앞으로 돌진하며 점점 가속 + 부딪힌 적·지형이면 즉시 들었던 도끼를 내려찍으며 정지
--   17:02 꺾기 가능(카메라 쪽 초당 TurnRate) · 멀리서 달려올수록 피해 · 공중 적도 멈추고 내려찍기 · 옆에 닿으면 밀쳐내고 계속
--   17:13 자세 = 2번 사이드 돌격(도끼를 왼 어깨 옆으로 치켜듦, 날 위·뒤 · 몸 앞으로 숙임 · 달리는 다리) — 시안 felsen_charge_key.lua [에디트 FK 10-30]
-- 서버 속성 ChargeAt · ChargeHitAt → CFG.chargePhase "windup" · "run" · "slam". 움직임은 조종 화면이 직접(PlatformStand · 매 프레임 CFrame)
local E = function(x, y, z) return CFrame.Angles(0, math.rad(y or 0), 0) * CFrame.Angles(math.rad(x or 0), 0, 0) * CFrame.Angles(0, 0, math.rad(z or 0)) end
local function sm(x) x = math.clamp(x, 0, 1); return x * x * (3 - 2 * x) end
local Players = game:GetService("Players")
local MP = require(script.Parent:WaitForChild("MechPoses"))

-- ---------- 도끼 자세: 도끼 두 손 표(SHAPES.Heavy.combo2h — 모든 화면이 공유)에 돌격 키 CH + 순서 ultCharge 를 넣음 ----------
--   시각(me): 선딜 0 → 1(겨눔 R → 머리 위 W1 0.35 → CH 0.6) · 달리는 동안 1.0(CH 유지) · 멈춘 뒤 1.0 + 경과(최대 Slam 0.9)
--   [에디트 FK 10-30 구간 검사 1/50초] R → CH 곧장은 0.06 ~ 0.40 동안 도끼가 왼 어깨 장갑·등·몸통·왼 위팔을 지남 → W1 경유는 겹침 0
--     (남는 건 오른손이 쥔 막대 · 내리치는 W1 → S1 순간 오른 위팔·몸통 = 도끼 1타와 같은 것)
--   멈춤 → CH → 머리 위 W1 → V1 → 날 앞 아래 S1 → 땅 F1d(= Swing 0.22, 서버 피해 시각) → 잠깐 → RV1 → 겨눔 R (1.9)
--   W1 → V1 → S1 → F1d → RV1 → R 은 도끼 1타(slash1)와 같은 길(1타가 구간 검사로 고른 경유 — RV1 없이 F1d → R 은 도끼가 몸통을 지남)
local CH_J = {
	Root = CFrame.new(0, -1, 0) * E(-15), Waist = CFrame.new(), Neck = E(14),
	ShoulderL = CFrame.new(0, 0, 0, -0.37523, 0.90785, 0.18714, -0.89470, -0.40750, 0.18293, 0.24233, -0.09879, 0.96515),
	ElbowL = CFrame.new(0, 0, 0, 1, 0, 0, 0, -0.42865, -0.90347, 0, 0.90347, -0.42865),
	SaberGrip = CFrame.new(0, 0, 0, 0.85359, -0.52094, -0.00211, -0.33483, -0.54554, -0.76829, 0.39908, 0.65651, -0.64010),
}
FE.CH_LEGS = { HipL = E(45), KneeL = E(-55), AnkleL = E(15), HipR = E(-22), KneeR = E(-25), AnkleR = E(20) }   -- 달리는 다리(왼발 앞)
local heavyTpl = Proto:FindFirstChild("HeavyTemplate")
local SH = heavyTpl and MP.shapeOf(heavyTpl)
if SH and SH.combo2h then
	SH.combo2h.keys.CH = { J = CH_J, rh = -8.12, poleR = Vector3.new(0.6, -1, 0.3) }
	SH.combo2h.seq.ultCharge = {
		{ 0.35, "R", "W1", "smooth", 0, 1 }, { 0.60, "W1", "CH", "smooth", 1, 1 }, { 1.00, "CH", "CH", "lin", 1, 1 },
		{ 1.06, "CH", "W1", "in", 1, 1 }, { 1.12, "W1", "V1", "in", 1, 1 }, { 1.16, "V1", "S1", "lin", 1, 1 }, { 1.22, "S1", "F1d", "out", 1, 1 },
		{ 1.45, "F1d", "F1d", "lin", 1, 1 }, { 1.70, "F1d", "RV1", "smooth", 1, 0 }, { 1.90, "RV1", "R", "smooth", 0, 0 },
	}
	if MP.SLASH_TRAIL then MP.SLASH_TRAIL.ultCharge = { 1.04, 1.24 } end   -- 도끼 열선 = 내리치는 동안
end

local CD = nil   -- 내 돌진 { at, yaw, fwd, vy, sides = {}, slamT, done, lastT }
local function chargeK(m)   -- 지금 단계 + 시각(내 기체는 멈춘 순간을 화면 시계로 — 서버 ChargeHitAt 이 도착하기 전에도 내려찍기 시작)
	local ph, k = CFG.chargePhase(m)
	if CD and m == ctx.mech() and CD.at == m:GetAttribute("ChargeAt") and CD.slamT then
		local s = os.clock() - CD.slamT
		if s < CFG.Charge.Slam then return "slam", s / CFG.Charge.Slam end
		return nil
	end
	return ph, k
end
local function chargeMelee(m)
	local ph, k = chargeK(m)
	if not ph then return nil end
	if ph == "windup" then return k, "ultCharge" end
	if ph == "run" then return 1.0, "ultCharge" end
	return 1.0 + k * CFG.Charge.Slam, "ultCharge"
end
function FE.charging(m)   -- 달리는 동안 등 부스터 불꽃
	return chargeK(m) == "run"
end
local grabPose, victimPose   -- 10-30 아래(그랩 절)에서 정의 — FE.pose 가 먼저 나오므로 전방 선언
function FE.pose(m, P, pitchDeg)   -- 다리(몸통·왼팔은 위 도끼 표가 그림): 선딜 동안 들어가고 · 달리는 동안 그대로 · 내려찍으며 뒤 2/3 에 걸쳐 풀림 · 10-30 그랩 자세도
	if grabPose then grabPose(m, P, pitchDeg) end
	if victimPose then victimPose(m, P) end   -- 10-31 그랩에 맞은 쪽
	local ph, k = chargeK(m)
	if not ph then return end
	local w = (ph == "windup") and sm(k / 0.6) or (ph == "run" and 1 or 1 - sm((k - 0.35) / 0.65))
	if w <= 0.001 then return end
	for n, cf in pairs(FE.CH_LEGS) do P[n] = (P[n] or CFrame.new()):Lerp(cf, w) end
end

-- ---------- 내 기체 달리기(조종 화면) ----------
-- 방향 = 달리기 시작할 때 카메라 수평 방향 → 매 프레임 카메라 쪽으로 최대 TurnRate°/초 · 속도 = CFG.chargeSpeed(달린 시간, 서버 시각)
-- 땅 = 발밑 광선으로 따라감(없으면 떨어짐) · 벽 = 앞 광선 3줄(발 +5 · 뿌리 · 뿌리 +6), 법선 Y < 0.6 이면 벽 → 그 자리에서 내려찍음
-- 기체 = 내 뿌리 +4 ↔ 상대 몸 막대(CFG.bodyDist) Contact 안: 앞 FrontAngle 안 = 멈추고 내려찍음(맞은 기체) · 밖 = 옆(한 번, 서버가 밀쳐냄) · 같은 팀은 지나감
-- 다 달리면(MaxTime) 그 자리에서 내려찍음 · 멈춘 뒤 Slam 초 동안 제자리 → 풀어 줌
local function teamOf(o)   -- MechDamage.teamOf 와 같은 규칙(속성 Team → 조종사 팀)
	local t = o:GetAttribute("Team")
	if t ~= nil then return t end
	local pid = o:GetAttribute("Pilot")
	local plr = (pid and Players:GetPlayerByUserId(pid)) or Players:GetPlayerFromCharacter(o)
	if plr and plr.Team and not plr.Neutral then return plr.Team end
	return nil
end
local function worldParams()   -- 기체 몸(Mech · MechDisplay) 빼고 · 안 부딪히는 파트(이펙트) 빼고
	local ex = {}
	for _, tag in ipairs({ "Mech", "MechDisplay" }) do
		for _, o in ipairs(CollectionService:GetTagged(tag)) do ex[#ex + 1] = o end
	end
	local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude; rp.FilterDescendantsInstances = ex
	rp.RespectCanCollide = true
	return rp
end
local function camFlat(fallback)
	local cam = workspace.CurrentCamera
	local lv = cam and cam.CFrame.LookVector or fallback
	local f = Vector3.new(lv.X, 0, lv.Z)
	return f.Magnitude > 0.05 and f.Unit or fallback
end
local function chargeRelease(hum, root)
	if FE.cDriving then
		FE.cDriving = false
		hum.PlatformStand = false
		root.AssemblyLinearVelocity = Vector3.zero
	end
end
local function chargeSlam(m, root, victim)
	CD.slamT = os.clock()
	Remotes.MechCharge:FireServer("slam", root.Position, victim)
end
local function chargeDrive(m, root, hum)
	local at = m:GetAttribute("ChargeAt")
	if not at then chargeRelease(hum, root); CD = nil; return false end
	if CD and CD.at ~= at then chargeRelease(hum, root); CD = nil end
	local C = CFG.Charge
	local now = workspace:GetServerTimeNow()
	local e = now - at
	if e < C.Windup then return false end   -- 선딜: 잠금(CFG.stunned) · 몸은 카메라 쪽으로(평소 faceAlign)
	if CD and CD.done then return false end
	if not CD then
		local lv = root.CFrame.LookVector
		local f = camFlat(Vector3.new(lv.X, 0, lv.Z).Magnitude > 0.05 and Vector3.new(lv.X, 0, lv.Z).Unit or Vector3.new(0, 0, -1))
		CD = { at = at, fwd = f, vy = 0, sides = {}, lastT = now }
	end
	local dt = math.clamp(now - CD.lastT, 0, 0.1); CD.lastT = now
	local hitAt = m:GetAttribute("ChargeHitAt")
	if not CD.slamT and hitAt and hitAt >= at then CD.slamT = os.clock() end   -- 서버가 먼저 내려찍음(신호가 늦음 — 서버 Windup + MaxTime + 0.6)
	FE.cDriving = true
	hum.PlatformStand = true
	root.AssemblyLinearVelocity = Vector3.zero
	if CD.slamT then   -- 멈춤: 제자리 → Slam 뒤 풀어 줌
		root.CFrame = CFrame.lookAlong(root.Position, CD.fwd)
		if os.clock() - CD.slamT >= C.Slam then CD.done = true; chargeRelease(hum, root) end
		return true
	end
	local runT = e - C.Windup
	-- 꺾기: 카메라 쪽으로 최대 TurnRate°/초
	local want = camFlat(CD.fwd)
	local ang = math.atan2(CD.fwd:Cross(want).Y, CD.fwd:Dot(want))
	local step = math.rad(C.TurnRate) * dt
	ang = math.clamp(ang, -step, step)
	CD.fwd = (CFrame.fromAxisAngle(Vector3.yAxis, ang) * CD.fwd).Unit
	local fwd = CD.fwd
	local pos = root.Position
	-- 기체 닿음
	local chest = pos + Vector3.new(0, 4, 0)
	local myTeam = teamOf(m)
	local cosF = math.cos(math.rad(C.FrontAngle))
	for _, o in ipairs(CollectionService:GetTagged("Mech")) do
		if o ~= m and o:IsDescendantOf(workspace) then
			local h = o:FindFirstChildOfClass("Humanoid")
			local orr = o:FindFirstChild("HumanoidRootPart")
			local ot = teamOf(o)
			if h and orr and h.Health > 0 and not (myTeam ~= nil and ot == myTeam) and CFG.bodyDist(o, chest) <= C.Contact then
				local rel = Vector3.new(orr.Position.X - pos.X, 0, orr.Position.Z - pos.Z)
				if rel.Magnitude < 0.5 or rel.Unit:Dot(fwd) >= cosF then
					root.CFrame = CFrame.lookAlong(pos, fwd)
					chargeSlam(m, root, o)
					return true
				elseif not CD.sides[o] then
					CD.sides[o] = true
					Remotes.MechCharge:FireServer("side", o)
				end
			end
		end
	end
	if runT >= C.MaxTime then   -- 다 달림
		root.CFrame = CFrame.lookAlong(pos, fwd)
		chargeSlam(m, root, nil)
		return true
	end
	local v = CFG.chargeSpeed(runT)
	local d = v * dt
	local rp = worldParams()
	local stand = hum.HipHeight + root.Size.Y / 2
	local foot = pos.Y - stand
	for _, hY in ipairs({ foot + 5, pos.Y, pos.Y + 6 }) do   -- 벽
		local o = Vector3.new(pos.X, hY, pos.Z)
		local r = workspace:Raycast(o, fwd * (d + 6), rp)
		if r and r.Normal.Y < 0.6 then
			root.CFrame = CFrame.lookAlong(pos, fwd)
			chargeSlam(m, root, nil)
			return true
		end
	end
	local np = pos + fwd * d
	local g = workspace:Raycast(np + Vector3.new(0, 6, 0), Vector3.new(0, -(stand + 6 + math.max(4, -CD.vy * dt * 2)), 0), rp)   -- 땅
	local y
	if g and g.Position.Y + stand >= np.Y + CD.vy * dt - 0.05 then
		y = g.Position.Y + stand; CD.vy = 0
	else
		CD.vy = math.max(-120, CD.vy - workspace.Gravity * dt)
		y = np.Y + CD.vy * dt
		if g then y = math.max(y, g.Position.Y + stand) end
	end
	root.CFrame = CFrame.lookAlong(Vector3.new(np.X, y, np.Z), fwd)
	return true
end
local function chargeYaw(m)
	if not (CD and m and m:GetAttribute("ChargeAt") == CD.at and not CD.done) then return nil end
	return math.atan2(-CD.fwd.X, -CD.fwd.Z)
end

-- ---------- 이펙트 ----------
-- 내려찍음(서버 MechFX "chargeSlam", ks = 직격 1 · 광역 AoeMul) = 도약 내려찍기와 같은 이펙트를 광역 반지름(AoeRadius)으로
-- 옆에 닿음("chargeSide") = 작은 번쩍 + 불꽃 · 흔들림(밀쳐진 내 기체 0.6 · 돌진한 내 기체 0.3)
local function sideFx(m, victim, pos)
	burst(pos, FE.CORE, 9, 0.2)
	if typeof(ctx.spark) == "function" then ctx.spark(pos, Vector3.yAxis) end
	local me = ctx.mech()
	if victim == me then ctx.shake(0.6) elseif m == me then ctx.shake(0.3) end
end

-- ================= 손등 작살 그랩 — 전용 동작 · 잠금 · 맞은 쪽 휘청 · 방전 표시 =================
-- 10-30 19:23 유저 "그랩 사용중에는 다른 동작 수행 불가 · 팔과 다리를 뻗는 그랩 전용 모션" · 23:25 레퍼런스(옆으로 튼 몸 + 곧게 뻗은 팔 + 뒤로 당긴 다른 팔 · 다리는 너무 벌리지 않게)
-- 10-31 00:09 유저 동의(손맛): ① 준비 동작 0.2초(팔을 뒤로 당김) → 쏠 때 앞으로 내지름 + 반동 ② 맞으면 팔을 확 잡아챔 → 끌려오는 동안 몸이 점점 뒤로 젖혀지며 줄 떨림 → 도착 쾅
--   ③ 맞은 적 = 끌려오는 동안 앞으로 쏠림 · 행동 불가 동안 고개 숙이고 떨림 + 머리 위 지지직 방전(흰·노랑 — 팀 색과 안 겹치게)
-- 단계 = CFG.grabPhase(서버 속성 GrabWindAt · GrabAt · GrabHitAt · GrabEnd) · 잠금 = CFG.stunned. 내 기체는 누른 순간부터 화면 시계로(준비·내지름), 맞은 뒤는 서버 시각
-- 키 자세 [에디트 FK 10-30 23:3x · 10-31 00:1x, 관절 Transform · E = Ry·Rx·Rz 도 · ShoulderL E(90) = 팔이 몸 정면 · ElbowL + = 팔뚝을 위로 굽힘]
--   WIND 몸을 50° 틀고 팔꿈치를 굽혀 왼주먹을 당김 · FIRE 몸 54° 틀고 앞으로 숙여 왼팔 곧게(어깨 yaw 54 = 팔 ↔ 정면 1.000) · PULL 뒤로 젖혀 팔 굽혀 당김 · DEEP 더 젖힘
--   구간 검사(1/10, 쉼 → WIND → FIRE → PULL → DEEP → 쉼 · WIND → 쉼): 쉼에 없던 겹침 0 · 발이 땅에 묻힘 최대 0.34(섞는 중간) · 뿌리 내림 = 낮은 발이 쉼 바닥과 같게
local I0 = CFrame.new()
FE.GRAB_KEYS = {
	WIND = { Root = CFrame.new(0, -0.05, 0) * E(4, -50, 0), Waist = E(3, -16, 0), Neck = E(0, 62, 0),
		ShoulderL = E(30, 40, 0), ElbowL = E(60), ShoulderR = E(12, 0, 16), ElbowR = E(50),
		HipL = E(18, 0, -4), KneeL = E(-18), AnkleL = E(2), HipR = E(-14, 0, 4), KneeR = E(-24), AnkleR = E(22) },
	fire = function(pd) return { Root = CFrame.new(0, -0.228, 0) * E(-8, -32, 0), Waist = E(2, -22, 0), Neck = E(4, 52, 0),
		ShoulderL = E(95 + pd, 54, 0), ElbowL = I0, ShoulderR = E(-18, 0, 25), ElbowR = E(70),
		HipL = E(32, 0, -4), KneeL = E(-44), AnkleL = E(12), HipR = E(-20, 0, 4), KneeR = E(-6), AnkleR = E(14) } end,
	pull = function(pd, deep) return { Root = CFrame.new(0, deep and -0.53 or -0.512, 0) * E(deep and 15 or 10, -20, 0), Waist = E(4, -15, 0), Neck = E(-4, 32, 0),
		ShoulderL = E(50 + 0.6 * pd, 36, 0), ElbowL = E(70), ShoulderR = E(10, 0, 14), ElbowR = E(45),
		HipL = E(26, 0, -4), KneeL = E(-22), AnkleL = E(0), HipR = E(-22, 0, 4), KneeR = E(-18), AnkleR = E(28) } end,
}
local grabT, busyT, busyWind = nil, nil, nil
function FE.grabPress()   -- 내 기체 C(GR.grab) — 서버 GrabWindAt 이 오기 전부터 자세·잠금
	local me = ctx and ctx.mech()
	grabT, busyT, busyWind = os.clock(), os.clock(), me and me:GetAttribute("GrabWindAt")
end
function FE.grabBusy()
	if not busyT then return false end
	local me = ctx and ctx.mech()
	if os.clock() - busyT > 0.8 or not me or me:GetAttribute("GrabWindAt") ~= busyWind then busyT = nil; return false end
	return true
end
local function bl(A, B, k)
	local o = {}
	for n, c in pairs(A) do o[n] = (k > 0) and c:Lerp(B[n] or c, k) or c end
	if k > 0 then for n, c in pairs(B) do if not A[n] then o[n] = I0:Lerp(c, k) end end end
	return o
end
local function grabFrame(m, pd)   -- → 무게(0~1), 자세 표
	local G = CFG.Grab
	local nowS = workspace:GetServerTimeNow()
	local ph, k = CFG.grabPhase(m, nowS)
	local own = (m == ctx.mech()) and grabT ~= nil
	if not ph and not (own and FE.grabBusy()) then
		if own then grabT = nil end
		return 0
	end
	local at, wa = m:GetAttribute("GrabAt"), m:GetAttribute("GrabWindAt")
	local ew, ef
	if own then
		ew = os.clock() - grabT; ef = ew - G.Windup
	else
		ew = wa and (nowS - wa) or 1
		ef = (at and (not wa or at >= wa)) and (nowS - at) or -1
	end
	local hitAt, eAt = m:GetAttribute("GrabHitAt"), m:GetAttribute("GrabEnd")
	local er, hit = nil, false
	if (ph == "reel" or ph == "recover") and hitAt and eAt then er = nowS - hitAt; hit = (eAt - hitAt) > 0.3 end
	local K = FE.GRAB_KEYS
	local kick = (ef >= 0 and ef < 0.25 and not er) and (1 - ef / 0.25) ^ 2 or 0          -- 쏜 반동(팔이 위로 튀고 몸이 뒤로)
	local T = bl(K.WIND, K.fire(pd + 14 * kick), (ef >= 0) and sm(ef / 0.07) or 0)       -- 0.07초에 내지름
	if er then
		T = bl(T, K.pull(pd, false), sm(er / 0.12) * (hit and 1 or 0.55))                -- 0.12초에 잡아챔(빗나가면 가볍게)
		if hit then T = bl(T, K.pull(pd, true), math.clamp((er - 0.12) / math.max(0.05, G.PullTime - 0.12), 0, 1)) end
		local bump = (er < 0.3) and math.sin(math.pi * er / 0.3) or 0
		T.ElbowL = T.ElbowL * E(18 * bump)                                                -- 잡아챌 때 팔꿈치가 더 굽었다 돌아옴
	end
	local root = T.Root * E(5 * kick, 0, 0)
	if hit and er > 0.12 and er < G.PullTime then root = root * E(1.2 * math.sin(er * 113), 0, 0.8 * math.sin(er * 82)) end   -- 줄 떨림
	if hit and er >= G.PullTime and er < G.PullTime + 0.18 then root = root * E(-7 * (1 - (er - G.PullTime) / 0.18) ^ 2, 0, 0) end   -- 도착 쾅(앞으로 받아냄)
	T.Root = root
	local w = sm(ew / 0.1)
	if ph == "recover" then w = w * (1 - sm(k)) end
	return w, T
end
function FE.grabbing(m) return (grabFrame(m, 0)) > 0 end
function FE.preSpin(m)   -- 맞혀서 끌어오는 동안 + 도착 뒤 1초 = 개틀링 미리 돎(도착하자마자 쏘게)
	local hitAt, eAt = m:GetAttribute("GrabHitAt"), m:GetAttribute("GrabEnd")
	if not (hitAt and eAt and eAt - hitAt > 0.3) then return false end
	local nowS = workspace:GetServerTimeNow()
	return nowS >= hitAt and nowS < eAt + CFG.Grab.Recover + 1.0
end
function grabPose(m, P, pitchDeg)
	local w, T = grabFrame(m, math.clamp(tonumber(pitchDeg) or 0, -35, 35))
	if w <= 0.001 then return end
	for n, c in pairs(T) do P[n] = (P[n] or I0):Lerp(c, w) end
end
-- 맞은 쪽(모든 기체): 끌려오는 동안 끌려오는 쪽으로 몸이 쏠림(얼굴 = FELSEN 쪽) · 행동 불가 동안 고개 숙이고 떨림. 몸통·목만(기체마다 팔 규약이 달라서)
function victimPose(m, P)
	local nowS = workspace:GetServerTimeNow()
	local pa = m:GetAttribute("PullAt")
	if pa and m:GetAttribute("PullEase") == "in" then
		local e = nowS - pa
		if e >= 0 and e < (m:GetAttribute("PullTime") or CFG.Grab.PullTime) then
			local w = sm(e / 0.08)
			P.Root = (P.Root or I0) * E(-16 * w, 0, 0); P.Waist = (P.Waist or I0) * E(-6 * w, 0, 0); P.Neck = (P.Neck or I0) * E(14 * w, 0, 0)
			return
		end
	end
	local su = m:GetAttribute("GrabStunUntil")
	if su and nowS < su then
		local w = math.min(1, (su - nowS) / 0.15)
		local t = os.clock()
		P.Root = (P.Root or I0) * E(-6 * w, 0, 0)
		P.Waist = (P.Waist or I0) * E(0, 2.5 * math.sin(t * 33) * w, 0)
		P.Neck = (P.Neck or I0) * E((-14 + 3 * math.sin(t * 40)) * w, 0, 0)
	end
end
-- 방전 표시(모든 화면): 속성 GrabStunUntil(서버 GRAB.pull) 동안 머리 위 3 에 0.07초마다 지그재그 번개 2줄(흰·노랑, 0.08초) + 몸 둘레 스파크
local STUN_Y, STUN_W = Color3.fromRGB(255, 226, 90), Color3.fromRGB(235, 245, 255)
local stunNext = setmetatable({}, { __mode = "k" })
local function zap(p0, p1, col)
	local pts = { p0 }
	for i = 1, 3 do pts[#pts + 1] = p0:Lerp(p1, i / 4) + Vector3.new((math.random() - 0.5) * 1.6, (math.random() - 0.5) * 1.6, (math.random() - 0.5) * 1.6) end
	pts[#pts + 1] = p1
	for i = 1, #pts - 1 do
		local q0, q1 = pts[i], pts[i + 1]
		local seg = ctx.fxPart(col, Vector3.new(0.2, 0.2, (q1 - q0).Magnitude + 0.1), CFrame.lookAt((q0 + q1) / 2, q1))
		Debris:AddItem(seg, 0.08)
	end
end
local function stepStun()
	local nowS, t = workspace:GetServerTimeNow(), os.clock()
	for _, m in ipairs(CollectionService:GetTagged("Mech")) do
		local su = m:GetAttribute("GrabStunUntil")
		if su and nowS < su and (stunNext[m] or 0) <= t then
			stunNext[m] = t + 0.07
			local head, r = m:FindFirstChild("Head", true), m:FindFirstChild("HumanoidRootPart")
			if head or r then
				local c = (head and head.Position or r.Position + Vector3.new(0, 8, 0)) + Vector3.new(0, 3, 0)
				for i = 1, 2 do
					local a1 = math.random() * 2 * math.pi
					local a2 = a1 + math.pi * (0.6 + math.random() * 0.8)
					local R = 2.5 + math.random() * 1.5
					zap(c + Vector3.new(math.cos(a1) * R, math.random() * 1.5, math.sin(a1) * R), c + Vector3.new(math.cos(a2) * R, math.random() * 1.5, math.sin(a2) * R), (i == 1) and STUN_Y or STUN_W)
				end
				if r and math.random() < 0.5 and typeof(ctx.spark) == "function" then
					ctx.spark(r.Position + Vector3.new((math.random() - 0.5) * 6, math.random() * 8 - 2, (math.random() - 0.5) * 6), Vector3.yAxis)
				end
			end
		end
	end
end

-- ================= MechClient 가 부르는 것(두 궁극기 모두 — 속성이 없으면 nil · false) =================
function FE.melee(m) local a, b = chargeMelee(m); if a then return a, b end; return leapMelee(m) end
function FE.drive(m, root, hum) if chargeDrive(m, root, hum) then return true end; return leapDrive(m, root, hum) end
function FE.faceYaw(m) return chargeYaw(m) or leapYaw(m) end
function FE.reset() leapReset(); CD = nil; FE.cDriving = false end

function FE.init(c)
	ctx = c
	RunService.RenderStepped:Connect(function()
		local ok, err = pcall(stepRings)
		if ok then ok, err = pcall(stepStun) end   -- 10-31 그랩 방전 표시
		if not ok and not FE.errA then FE.errA = true; warn("[MechFelsen] 착지 원 오류(한 번만): " .. tostring(err)) end
	end)
	Remotes.MechFX.OnClientEvent:Connect(function(kind, m, a, b, c2)
		if kind == "leapSlam" and typeof(a) == "Vector3" then slamFx(m, a, b, c2) end
		if kind == "leapAirHit" and typeof(b) == "Vector3" then airFx(m, a, b) end
		if kind == "chargeSlam" and typeof(a) == "Vector3" then slamFx(m, a, b, c2, CFG.Charge.AoeRadius) end
		if kind == "chargeSide" and typeof(b) == "Vector3" then sideFx(m, a, b) end
	end)
end
return FE
