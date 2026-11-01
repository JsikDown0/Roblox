-- MechFalco (ModuleScript, MechClient 의 자식) — 10-30 LF-01 FALCO(MechType "Aero") 시그니처 라이더킥(C) · 궁극기 마비 덫(X) 의 화면 쪽
-- 유저 10-30 "컨셉으로만 남겨뒀던 팔코 스킬들을 구현하자. 라이더킥과 마비 덫" · "라이더킥 자세는 이걸 참고해줘"(가면라이더 V3 킥 피규어 · 빨간 기체 날아차기)
-- MechClient Source 20만 자 한도(17.8만) 때문에 따로 둠. 규칙·수치 = MechConfig CFG.RiderKick / CFG.Trap · 판정 = MechServer RK / TRAP
-- MechClient 가 init(ctx) 로 넘기는 것만 씀: mech() · aimPoint() · fxPart(색, 크기, CFrame, 모양) · exclude(목록) · spark(자리, 법선) · shake(세기)
-- ⚠️ require 만으로는 아무것도 안 돎(RenderStepped·이벤트 연결은 init 에서) — 에디트에서 순수 함수만 시험할 수 있게
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Proto = RS:WaitForChild("MechProto")
local CFG = require(Proto:WaitForChild("MechConfig"))
local Remotes = Proto:WaitForChild("Remotes")
local SM = require(Proto:WaitForChild("SoundManager"))

local F = {}
local ctx = nil
local function E(x, y, z)   -- MechPoses E 와 같은 식(Y · X · Z, 도)
	return CFrame.fromAxisAngle(Vector3.yAxis, math.rad(y or 0)) * CFrame.fromAxisAngle(Vector3.xAxis, math.rad(x or 0)) * CFrame.fromAxisAngle(Vector3.zAxis, math.rad(z or 0))
end
local function sm(x) x = math.clamp(x, 0, 1); return x * x * (3 - 2 * x) end

-- ================= 라이더킥 자세 =================
-- 10-30 15:2x 유저 "날아 옆차기로 가고 싶다"(그 전 자세 = 몸 정면으로 다리를 앞쪽 아래로 뻗어 내려찍기처럼 보임) · "왼발 · 가장 가파른 각 45도"
-- 왼발 날아 옆차기: 몸을 옆으로 90° 돌려(Root 비틀기 −90 → 왼쪽 옆구리가 차는 쪽) 왼다리를 엉덩이 옆으로 곧게 뻗고(발바닥이 앞장섬) ·
--   오른다리는 접어 당기고 · 상체는 차는 반대쪽으로 젖힘(Root + 허리) · 왼팔은 차는 쪽 위로 · 라이플 든 오른팔은 위·옆으로(뒤로 뻗으면 내 카메라를 가림)
-- 관절 Transform(관절 틀 = 템플릿 축, E = Y·X·Z 도) [에디트 FK 10-30 — AeroTemplate 복제, 충돌 모양 정밀: 급강하 20~60° 전부 쉬는 자세 대비 새로 닿는 짝 0.
--   단 옆 스커트가 엉덩이 옆으로 든 각을 0.8 배 따라가야(MechPoses SHAPES.Heavy.skirt.sideZ — 안 따라가면 왼 옆 스커트가 허벅지에 박힘) ·
--   오른다리 앞 65 넘게 들면 앞 스커트에 닿음 · 다리(엉덩이→발바닥)와 급강하 방향 어긋남 4.4°]
--   몸 젖힘 φ = Alpha − 급강하 각(Alpha 55 = 90 − 다리 옆으로 35) → 다리가 늘 급강하 방향과 한 줄: 20° 35 젖힘(전형적 날아 옆차기) · 45° 10
--   시안 = Mecha Battle/FALCO_20261030/sidekick_compare.jpg — 60° 는 다리가 서서 다시 내려찍기처럼 보여 가장 가파른 각 45°(CFG MaxDown)
--   뒤(내 카메라)에서는 몸이 옆으로 돌아 차는 다리가 몸에 가림(앞 자세도 같았음 — 방향은 혜성이 보여 줌). ¾(65°)만 돌리는 안도 다리가 가려 버림
F.POSE = {
	Waist = E(0, 0, -20), HipL = E(0, 0, -35), KneeL = E(0), AnkleL = E(0), HipR = E(60, 0, 10), KneeR = E(-115), AnkleR = E(-20),
	ShoulderL = E(15, 0, -50), ElbowL = E(70), ShoulderR = E(30, 0, 140), ElbowR = E(10),
}
F.TIP = Vector3.new(0, -1.7, 0)   -- 왼발(FootL) 로컬 발바닥 가운데 = 맞음 판정·혜성 머리 자리(옆차기는 발바닥 면이 급강하 방향을 정면으로 봄 [에디트 FK 0°])

-- ================= 내 킥(조종 화면) =================
-- S = { t0(os.clock) · from · dir · flat · hitT · stopT · bFrom · bTo · lastTip · lastPos } — 속성을 기다리지 않고 바로 시작(서버 속성은 남의 화면·잠금용)
local S = nil
F.driving, F.sentAt, F.readyAt = false, -99, 0
local function localPhase()
	local K = CFG.RiderKick
	local now = os.clock()
	if S.hitT then   -- 튕김(끌고 간 뒤 · 안 끌면 닿자마자)
		local eb = now - S.hitT
		if eb < K.Bounce.Time then return "bounce", eb / K.Bounce.Time end
		return nil
	end
	if S.cT0 then return "carry", math.clamp((now - S.cT0) / K.Carry.Time, 0, 1) end   -- 끌고 감(끝은 F.drive 가 정함)
	local e = now - S.t0
	if e < K.Ready then return "ready", e / K.Ready end
	local diveT = K.Range / K.Speed
	local endT = S.stopT or (S.t0 + K.Ready + diveT)
	if now < endT then return "dive", math.clamp((e - K.Ready) / diveT, 0, 1) end
	local er = now - endT
	if er < K.Recover then return "recover", er / K.Recover end
	return nil
end
-- 자세·혜성용 단계: 내 기체 = 내 킥(S, 끝나면 nil — 서버 속성은 지연만큼 늦게 끝나서 안 씀) · 남의 기체 = 서버 속성(CFG.riderPhase)
function F.phase(m)
	if ctx and m == ctx.mech() then
		if not S then return nil end
		local ph, k = localPhase()
		if ph then return ph, k, S.dir end
		return nil
	end
	local ph, k = CFG.riderPhase(m)
	if ph then return ph, k, m:GetAttribute("RKDir") end
	return nil
end
function F.active(m) return F.phase(m) ~= nil end
function F.busy() return S ~= nil and localPhase() ~= nil end   -- 내 킥이 아직 안 끝남(GR.locked 가 서버 속성보다 먼저 잠그게)
function F.reset() S = nil; F.driving = false end
function F.faceYaw()   -- 킥 중 몸 방향(faceAlign 이 카메라 쪽으로 비틀지 않게)
	if not (S and localPhase()) then return nil end
	return math.atan2(-S.flat.X, -S.flat.Z)
end

function F.riderKick()
	local m = ctx.mech()
	if not m or m:GetAttribute("Signature") ~= "RiderKick" then return end
	local hum, root = m:FindFirstChildOfClass("Humanoid"), m:FindFirstChild("HumanoidRootPart")
	if not (hum and root) or hum.Health <= 0 then return end
	if F.busy() or CFG.stunned(m) or CFG.anchorPhase(m) then return end
	local now = os.clock()
	if now - F.sentAt < 0.5 or now < F.readyAt then return end
	if (m:GetAttribute("RKReadyAt") or 0) > workspace:GetServerTimeNow() then return end
	-- 공중에서만: 발밑(뿌리 높이 + 2 안)에 아무것도 없어야(서버와 같은 검사)
	if workspace:Raycast(root.Position, Vector3.new(0, -((m:GetAttribute("RootHeight") or 10) + 2), 0), ctx.exclude({ m })) then return end
	local dir = CFG.riderDir(ctx.aimPoint() - root.Position)
	local fl = Vector3.new(dir.X, 0, dir.Z)
	F.sentAt, F.readyAt = now, now + CFG.RiderKick.Cooldown
	for _, c in ipairs(root:GetChildren()) do if c:IsA("LinearVelocity") then c:Destroy() end end   -- 대시·지속 부스트·관성 속도 제약을 걷어 냄(근접 tryMelee 와 같음 — 몸을 직접 놓는 동안 싸우지 않게)
	S = { t0 = now, st0 = workspace:GetServerTimeNow(), from = root.Position, dir = dir, flat = fl.Magnitude > 0.05 and fl.Unit or Vector3.new(0, 0, -1) }
	S.lastPos = S.from
	Remotes.MechRiderKick:FireServer("start", root.Position, dir)
end

local function release(hum, root, vel)
	if F.driving then
		F.driving = false
		hum.PlatformStand = false
		root.AssemblyLinearVelocity = vel or Vector3.zero
	end
end
-- 튕김: 착지 자리 = 뒤로 Back(출발 높이·꼭대기 두 줄로 벽 재기, 앞차기 공중제비와 같은 규칙) 아래 땅 위 서 있는 높이
local function startBounce(m, root, hum, pos)
	local K = CFG.RiderKick
	S.hitT = os.clock()
	S.bFrom = pos
	local back = -S.flat
	local ex = ctx.exclude({ m, S.victim })
	local dist = K.Bounce.Back
	for _, up in ipairs({ 0, K.Bounce.Height }) do
		local o = pos + Vector3.new(0, up, 0)
		local h = workspace:Raycast(o, back * (K.Bounce.Back + 4), ex)
		if h then dist = math.min(dist, math.max(0, (h.Position - o):Dot(back) - 4)) end
	end
	local to = pos + back * dist
	local g = workspace:Raycast(to + Vector3.new(0, 20, 0), Vector3.new(0, -300, 0), ex)
	local y = g and (g.Position.Y + hum.HipHeight + root.Size.Y / 2) or to.Y
	S.bTo = Vector3.new(to.X, math.max(y, pos.Y - K.Bounce.Drop), to.Z)
end
-- 닿음: 서버에 알리고 끌고 가기 시작(10-30 유저 "상대를 밀고 가다 마지막에 크게 날림") — 상대가 끌려가는 걸(내 화면에 보이는 자리) 따라가 발끝을 붙임.
--   서버가 안 끌기로 하면(RKCarry 없음 — 아군·슈퍼아머·기체 아님) · 0.4초 넘게 답이 없으면(거절) · 상대가 날아가기 시작하면 → 그 자리에서 튕김
local function onHit(m, root, hum, pos, tip, victim)
	local vr = victim:FindFirstChild("HumanoidRootPart")
	S.cT0, S.victim = os.clock(), victim
	S.cFrom, S.vFrom, S.cBest = pos, vr and vr.Position or tip, 0
	Remotes.MechRiderKick:FireServer("hit", victim, tip)
	ctx.shake(0.5)
end
-- 끌고 가는 동안 내 자리: 상대 뿌리가 움직인 만큼(뒤로는 안 감 · Carry.Dist + 2 까지 · 벽·땅에 막히면 그 자리에서 기다림). 끝나면 튕김 시작
local function carryPos(m, root, hum, now)
	local K = CFG.RiderKick
	local v = S.victim
	local vr = v and v.Parent and v:FindFirstChild("HumanoidRootPart")
	local vh = v and v:FindFirstChildOfClass("Humanoid")
	local e = now - S.cT0
	local done = not (vr and vh and vh.Health > 0) or e > K.Carry.Time + 0.6
	local at, hit = m:GetAttribute("RKAt"), m:GetAttribute("RKHitAt")
	if at and hit and hit >= at and at >= S.st0 - 1 then   -- 이번 킥의 서버 판정이 옴
		if not m:GetAttribute("RKCarry") then done = true
		elseif vr then
			local pa = v:GetAttribute("PullAt")
			if pa and pa > hit + K.Carry.Time * 0.8 then done = true end   -- 날림(새 끌림)이 시작됨 → 놓음
		end
	elseif e > 0.4 then done = true end
	local pos = S.lastPos
	if not done then
		local d = vr.Position - S.vFrom
		local along = d:Dot(S.flat)
		if along > S.cBest and along <= K.Carry.Dist + 2 then
			local to = S.cFrom + d
			local seg = to - S.lastPos
			if seg.Magnitude < 0.01 or not workspace:Raycast(S.lastPos, seg, ctx.exclude({ m, v })) then S.cBest = along; pos = to end
		end
	end
	if done then startBounce(m, root, hum, pos) end
	return pos
end
-- 매 프레임(카메라 단계, GR.drive · GR.flipDrive 다음): 내 킥이면 몸을 직접 놓음(PlatformStand). 놓는 중이면 true
function F.drive(m, root, hum)
	if not S then release(hum, root); return false end
	local K = CFG.RiderKick
	local ph = localPhase()
	if ph == nil or ph == "recover" then
		release(hum, root, (ph == "recover" and not S.ground) and S.dir * 25 or nil)
		if ph == nil then S = nil end
		return false
	end
	F.driving = true
	hum.PlatformStand = true
	local now = os.clock()
	local pos
	if ph == "bounce" then
		local u = math.clamp((now - S.hitT) / K.Bounce.Time, 0, 1)
		pos = S.bFrom:Lerp(S.bTo, u * (2 - u)) + Vector3.new(0, 4 * K.Bounce.Height * u * (1 - u), 0)
	elseif ph == "ready" then
		pos = S.from
	elseif ph == "carry" then
		pos = carryPos(m, root, hum, now)
		S.lastPos = pos
	else
		local d = math.min(K.Range, K.Speed * (now - S.t0 - K.Ready))
		pos = S.from + S.dir * d
		-- 발끝 = 지난 프레임 자세의 발끝(뿌리 기준)을 새 자리로 옮김
		local foot = m:FindFirstChild("FootL")
		local off = foot and root.CFrame:PointToObjectSpace(foot.CFrame * F.TIP) or Vector3.new(1, -11, -15)
		local tip = CFrame.lookAlong(pos, S.flat) * off
		local last = S.lastTip or tip
		-- ① 기체 몸(세로 막대)에 발끝이 닿음 → 맞음(아군이어도 — 피해·끌고 감은 서버가 가름)
		local victim
		for _, o in ipairs(CollectionService:GetTagged("Mech")) do
			if o ~= m and o:IsDescendantOf(workspace) then
				local h = o:FindFirstChildOfClass("Humanoid")
				if h and h.Health > 0 and CFG.bodyDist(o, tip) <= K.HitRadius then victim = o; break end
			end
		end
		local stopAt = nil
		if not victim then
			-- ② 땅·벽: 지난 발끝 → 새 발끝 · 지난 뿌리 → 새 뿌리. 기체 몸 파트에 막히면 그 기체를 맞힌 것으로
			local ex = ctx.exclude({ m })
			for _, seg in ipairs({ { last, tip }, { S.lastPos, pos } }) do
				local v = seg[2] - seg[1]
				if v.Magnitude > 0.01 then
					local r = workspace:Raycast(seg[1], v, ex)
					if r then
						local o = r.Instance:FindFirstAncestorWhichIsA("Model")
						while o and not CollectionService:HasTag(o, "Mech") do o = o:FindFirstAncestorWhichIsA("Model") end
						if o and o ~= m then victim = o
						else stopAt = (seg[2] - r.Position).Magnitude + 0.5 end   -- 넘어간 만큼 되돌림
						break
					end
				end
			end
		end
		if victim then
			onHit(m, root, hum, pos, tip, victim)
		elseif stopAt then
			pos = pos - S.dir * stopAt
			S.stopT, S.ground = now, true
			Remotes.MechRiderKick:FireServer("stop")
		elseif d >= K.Range then
			S.stopT = now
			Remotes.MechRiderKick:FireServer("stop")
		end
		S.lastTip, S.lastPos = tip, pos
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.CFrame = CFrame.lookAlong(pos, S.flat)
	if S.stopT then release(hum, root, (not S.ground) and S.dir * 25 or nil) end
	return true
end

-- 자세(모든 화면, animOne 에서 앞차기 공중제비 다음 · 어깨 장갑·스커트 앞): 키 자세를 w 만큼 섞고 몸을 Root 관절 둘레로 옆으로 90° 돌린 뒤 φ 젖힘
--   φ = Alpha − 급강하 각 → 차는 다리가 급강하 방향과 한 줄(발바닥이 앞장섬). 머리는 차는 쪽으로 돌리고 젖힌 만큼 반쯤 바로 세움
--   끌고 가는 동안(carry)도 급강하 자세 그대로(유저 "추가 동작은 없이")
function F.pose(m, P)
	local ph, k, dir = F.phase(m)
	if not ph then return end
	local w
	if ph == "ready" then w = sm(k)
	elseif ph == "dive" or ph == "carry" then w = 1
	elseif ph == "bounce" then w = 1 - sm(k / 0.6)
	else w = 1 - sm(k) end
	if w <= 0.001 then return end
	local K = CFG.RiderKick
	local beta = K.MinDown
	if typeof(dir) == "Vector3" then beta = math.deg(math.asin(math.clamp(-dir.Y, -1, 1))) end
	local phi = K.Alpha - beta
	for n, cf in pairs(F.POSE) do P[n] = (P[n] or CFrame.new()):Lerp(cf, w) end
	P.Neck = (P.Neck or CFrame.new()):Lerp(E(0, 80, 0.5 * phi), w)
	P.Root = (P.Root or CFrame.new()):Lerp(E(0, -90, 0) * E(0, 0, -phi), w)
end

-- ================= 혜성(모든 화면) =================
-- 10-30 유저 "반짝임은 제외, 혜성으로 바꾸고" — 발끝 결정 조각 대신 몸 전체를 감싸는 빛 + 뒤로 넓어지며 옅어지는 꼬리
--   머리 = 차는 발끝(가장 밝은 흰 심 + 노란 무리) · 몸 감쌈 = 발끝 → 머리(Head) 축의 길쭉한 주황 빛 · 꼬리 = 몸 뒤 끝에서 움직이는 반대쪽으로
--   (급강하 = 급강하 반대 · 끌고 감 = 수평 반대 — 몸은 급강하 자세 그대로라 꼬리만 꺾임)
--   자세 잡는 동안(ready) 발끝에서 자라남(번쩍임 없음) · 급강하·끌고 감 동안 일렁 + 속도선 · 튕김·풀림에 약 0.15초에 사라짐
--   카메라가 빛 조각 안(가까이)에 들어가면 그 조각은 투명하게 — 내 화면은 카메라가 뒤(꼬리 속)에 있어서 주황으로 덮이지 않게
-- 몸 크기 [에디트 FK 10-30, 급강하 각과 무관]: 발끝 → 몸 뒤 끝(머리·날개) 약 30 · 몸통 반지름 약 9(팔·라이플·날개는 삐져나옴)
-- 색 [제안]: FALCO 주황(덫 경계선 F.LINE 과 같은 계열) — 심 흰빛 · 무리 노랑 · 몸 주황 · 꼬리 끝 붉은 주황
F.COMET = {
	Core = Color3.fromRGB(255, 248, 225), Head = Color3.fromRGB(255, 200, 90),
	Body = Color3.fromRGB(255, 140, 40), Tail = Color3.fromRGB(255, 80, 30),
	Width = 20, TailN = 8, TailStep = 4.5, TailLen = 3.2, TailGrow = 0.07,   -- 꼬리 조각 8개를 길게 겹쳐야 한 줄기로 보임(6개·짧게는 원판이 줄지어 보임) [10-30 미리보기 렌더]
}
local comets = {}   -- [기체] = { core, halo, shell, tail = {}, light, base = { [파트] = 기본 투명도 }, mdir, nextLine } — 강한 키 + 기체가 사라지면 정리
local function buildComet()
	local C = F.COMET
	local c = { tail = {}, base = {} }
	local function ball(col, tr)
		local p = ctx.fxPart(col, Vector3.one, CFrame.new(), Enum.PartType.Ball)
		p.Transparency = 1
		c.base[p] = tr
		return p
	end
	c.core = ball(C.Core, 0.05)
	c.halo = ball(C.Head, 0.45)
	c.shell = ball(C.Body, 0.72)
	for i = 1, C.TailN do c.tail[i] = ball(C.Body:Lerp(C.Tail, i / C.TailN), 0.8 + 0.022 * i) end
	c.light = Instance.new("PointLight")
	c.light.Color, c.light.Range, c.light.Brightness, c.light.Shadows = C.Head, 22, 0, false
	c.light.Parent = c.core
	return c
end
local function dropComet(m)
	local c = comets[m]
	if not c then return end
	for p in pairs(c.base) do p:Destroy() end
	comets[m] = nil
end
local function setBall(c, p, cf, size, s, cam)
	p.Size = Vector3.new(math.max(0.05, size.X), math.max(0.05, size.Y), math.max(0.05, size.Z))
	p.CFrame = cf
	local tr = s > 0.02 and c.base[p] or 1
	if cam and tr < 1 then   -- 카메라가 이 조각 안·가까이(타원 반지름 1.5배 안)면 옅게 → 안이면 투명
		local e = (cf:PointToObjectSpace(cam) / (p.Size * 0.5)).Magnitude
		if e < 1.5 then tr += (1 - tr) * math.clamp((1.5 - e) / 0.5, 0, 1) end
	end
	p.Transparency = tr
end
-- 발끝 tip · 몸 뒤 끝 back(머리) · 움직이는 방향 mdir(단위) · 크기 s(0~1) · 일렁 시각 t · 카메라 자리 cam(없으면 안 옅게) — 에디트 시험용으로 따로
function F.placeComet(c, tip, back, mdir, s, t, cam)
	local C = F.COMET
	local axis = tip - back
	local L = math.max(4, axis.Magnitude)
	local ax = axis.Unit
	local W = C.Width
	local fl = 1 + 0.05 * math.sin(t * 37)   -- 일렁
	setBall(c, c.core, CFrame.new(tip + ax * 0.6), Vector3.one * 4.5 * s * fl, s, cam)
	setBall(c, c.halo, CFrame.lookAlong(tip - ax * 2.5, ax), Vector3.new(10, 10, 15) * s * fl, s, cam)
	-- 몸 감쌈: 발끝 앞 2 ~ 머리 뒤 4 — 자세 잡는 동안 발끝에서부터 늘어남
	local len = (L + 6) * s
	local ws = W * math.sqrt(s) * (1 + 0.03 * math.sin(t * 29))
	setBall(c, c.shell, CFrame.lookAlong(tip + ax * (2 - len / 2), ax), Vector3.new(ws, ws, len), s, cam)
	-- 꼬리: 몸 감쌈 뒤 끝에서 움직이는 반대쪽으로 TailN 개(겹침) — 뒤로 갈수록 넓어지고 옅어짐 · 몸이 다 감싸진 뒤(s > 0.5)부터 자람
	local st = math.clamp((s - 0.5) * 2, 0, 1)
	local base = tip + ax * (2 - len)
	for i, p in ipairs(c.tail) do
		local w = W * (1 + C.TailGrow * i) * (1 + 0.03 * math.sin(t * 23 + i * 1.7)) * st
		setBall(c, p, CFrame.lookAlong(base - mdir * (C.TailStep * (i - 0.4) * st), mdir), Vector3.new(w, w, C.TailStep * C.TailLen * st), st, cam)
	end
	c.light.Brightness = 4 * s
end
local function speedLine(tip, back, mdir)   -- 몸 둘레에서 뒤로 휙 빠지는 가는 빛줄(0.18초)
	local C = F.COMET
	local ax = (tip - back).Unit
	local u = ax:Cross(Vector3.yAxis)
	if u.Magnitude < 0.1 then u = ax:Cross(Vector3.xAxis) end
	u = u.Unit
	local v = ax:Cross(u)
	local a = math.random() * 2 * math.pi
	local p0 = back:Lerp(tip, math.random()) + (u * math.cos(a) + v * math.sin(a)) * C.Width * 0.5 * (0.6 + 0.5 * math.random())
	local ln = ctx.fxPart(C.Head, Vector3.new(0.3, 0.3, 5 + math.random() * 5), CFrame.lookAlong(p0, mdir))
	ln.Transparency = 0.3
	TweenService:Create(ln, TweenInfo.new(0.18, Enum.EasingStyle.Linear), { CFrame = CFrame.lookAlong(p0 - mdir * 16, mdir), Transparency = 1 }):Play()
	Debris:AddItem(ln, 0.2)
end
local function stepComets(dt)
	local seen = {}
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position
	local t = os.clock()
	for _, m in ipairs(CollectionService:GetTagged("Mech")) do
		local ph, k, dir = F.phase(m)
		local foot = ph and m:FindFirstChild("FootL")
		local head = foot and (m:FindFirstChild("Head") or m:FindFirstChild("Torso"))
		if head and typeof(dir) == "Vector3" then
			seen[m] = true
			local s = (ph == "ready") and sm(k) or (ph == "dive" or ph == "carry") and 1 or math.max(0, 1 - k * 3)
			local c = comets[m]
			if not c then c = buildComet(); comets[m] = c end
			local want = dir.Unit
			if ph == "carry" or ph == "bounce" then   -- 끌고 감 = 수평으로 움직임 → 꼬리만 수평 반대로
				local fl = Vector3.new(dir.X, 0, dir.Z)
				if fl.Magnitude > 0.05 then want = fl.Unit end
			end
			c.mdir = c.mdir and c.mdir:Lerp(want, math.clamp(dt * 12, 0, 1)).Unit or want
			local tip = foot.CFrame * F.TIP
			F.placeComet(c, tip, head.Position, c.mdir, s, t, camPos)
			if (ph == "dive" or ph == "carry") and t >= (c.nextLine or 0) then
				c.nextLine = t + 0.025
				speedLine(tip, head.Position, c.mdir)
			end
		end
	end
	for m in pairs(comets) do
		if not seen[m] then dropComet(m) end
	end
end

-- 끌고 가는 동안 한 대(서버 MechFX "riderTick", n = 몇 번째): 작은 흰빛 + 짧은 불티 — 대마다 조금씩 커짐(만화식으로 쌓이는 느낌)
local function tickFx(m, victim, pos, n)
	local C = F.COMET
	n = typeof(n) == "number" and n or 1
	local ball = ctx.fxPart(C.Core, Vector3.one * 2, CFrame.new(pos), Enum.PartType.Ball)
	ball.Transparency = 0.15
	TweenService:Create(ball, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * (6 + n), Transparency = 1 }):Play()
	Debris:AddItem(ball, 0.14)
	for i = 1, 5 do
		local d = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
		d = d.Magnitude > 0.05 and d.Unit or Vector3.yAxis
		local p = ctx.fxPart(C.Head, Vector3.new(0.35, 0.35, 2 + math.random() * 1.5), CFrame.lookAlong(pos, d))
		TweenService:Create(p, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.lookAlong(pos + d * (4 + n), d), Transparency = 1 }):Play()
		Debris:AddItem(p, 0.17)
	end
	local me = ctx.mech()
	if victim == me then ctx.shake(0.35) elseif m == me then ctx.shake(0.3) end
end
-- 날림(서버 MechFX "riderHit" — 끌고 간 끝 · 안 끌면 닿는 순간): 흰빛 구가 크게 퍼지고 · 찬 방향을 마주한 고리 · 조각이 사방으로
local function hitFx(m, victim, pos, dealt)
	local C = F.COMET
	local big = dealt and 1 or 0.5
	local ball = ctx.fxPart(C.Core, Vector3.one * 2, CFrame.new(pos), Enum.PartType.Ball)
	ball.Transparency = 0.05
	TweenService:Create(ball, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * 22 * big, Transparency = 1 }):Play()
	Debris:AddItem(ball, 0.32)
	if dealt then
		local dir = m and m:GetAttribute("RKDir")
		local fl = typeof(dir) == "Vector3" and Vector3.new(dir.X, 0, dir.Z) or Vector3.zAxis
		fl = fl.Magnitude > 0.05 and fl.Unit or Vector3.zAxis
		-- 원기둥 축(X) = 찬 방향 → 납작한 원판이 찬 방향을 마주봄
		local ring = ctx.fxPart(C.Head, Vector3.new(0.6, 6, 6), CFrame.lookAlong(pos, fl) * CFrame.Angles(0, math.rad(90), 0), Enum.PartType.Cylinder)
		ring.Transparency = 0.3
		TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.3, 34, 34), Transparency = 1 }):Play()
		Debris:AddItem(ring, 0.37)
	end
	for i = 1, dealt and 16 or 8 do
		local d = Vector3.new(math.random() - 0.5, math.random() - 0.3, math.random() - 0.5)
		d = d.Magnitude > 0.05 and d.Unit or Vector3.yAxis
		local p = ctx.fxPart(i % 2 == 0 and C.Head or C.Body, Vector3.new(0.6, 0.6, 3 + math.random() * 2.5), CFrame.lookAlong(pos, d))
		local life = 0.28 + math.random() * 0.15
		TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.lookAlong(pos + d * (10 + math.random() * 8) * big, d), Transparency = 1 }):Play()
		Debris:AddItem(p, life + 0.02)
	end
	if typeof(ctx.spark) == "function" then ctx.spark(pos, Vector3.yAxis) end
	local me = ctx.mech()
	if victim == me then ctx.shake(dealt and 1.0 or 0.4) end
	if m == me and dealt then ctx.shake(0.8) end
end

-- ================= 마비 덫(모든 화면) =================
-- 쏜 기체 속성 TrapAt · TrapPos · TrapYaw → 단계 CFG.trapPhase:
--   fly  = 등 못 4개(SpikeL1/L2/R1/R2 — 판넬처럼 따로 디자인한 부품)를 복제해 사각형 네 귀로 포물선(촉이 앞) · 진짜 등 못은 이 화면에서만 숨김
--   arm  = 박힘(촉 1 묻힘, 똑바로) · 머리 발광이 깜빡임
--   on   = 머리끼리 전기(빔 · 매 프레임 흔들림) + 바닥 주황 경계선·옅은 면 = 판정 사각형(보이는 선 = 판정 경계)
--   끝   = 0.3초에 사라지고 등 못이 다시 보임. 쏜 기체가 없어지면 바로 정리
-- 귀 = 쏜 쪽 기준 왼앞(L1) · 왼뒤(L2) · 오른앞(R1) · 오른뒤(R2) — 등에서 같은 쪽 못이 같은 쪽 귀로
F.SPIKES = { { "SpikeL1", -1, -1 }, { "SpikeL2", -1, 1 }, { "SpikeR2", 1, 1 }, { "SpikeR1", 1, -1 } }   -- 둘레 순서(전기선 이음)
F.ELEC, F.ELEC_CORE, F.LINE = Color3.fromRGB(255, 215, 95), Color3.fromRGB(255, 250, 225), Color3.fromRGB(255, 140, 40)
F.SPIKE_LEN, F.SPIKE_SINK, F.SPIKE_HEAD = 6.5, 1.0, 2.4   -- 못 길이(Y) · 땅에 묻히는 깊이 · 머리 발광 고리 높이(가운데 기준) [템플릿 1.3×6.5×1.3 · aero_spikes.py 고리 = 촉에서 87%]
local traps = {}   -- [쏜 기체] = { at, spikes = { { part, head, glow, from, to, landed } }, beams, lines, ended }
local function trapFolder()
	local cam = workspace.CurrentCamera
	local fd = cam:FindFirstChild("FalcoTrapFx")
	if not fd then fd = Instance.new("Folder"); fd.Name = "FalcoTrapFx"; fd.Parent = cam end
	return fd
end
-- 등 못 숨김 = 이 화면에서만 Transparency(서버가 안 바꾸는 값 — LocalTransparencyModifier 는 기본 카메라 스크립트가 캐릭터 파트에 덮어쓸 수 있음). 원래 값은 T.hidden 에 기억
local function hideBack(m, T)
	T.hidden = {}
	for _, s in ipairs(F.SPIKES) do
		local p = m:FindFirstChild(s[1], true)
		if p and p:IsA("BasePart") then T.hidden[p] = p.Transparency; p.Transparency = 1 end
	end
end
local function showBack(T)
	for p, tr in pairs(T.hidden or {}) do
		if p.Parent then p.Transparency = tr end
	end
	T.hidden = nil
end
local function groundAt(pos, ignore)
	local r = workspace:Raycast(pos + Vector3.new(0, 40, 0), Vector3.new(0, -200, 0), ctx.exclude(ignore))
	return r and r.Position.Y or pos.Y
end
-- 네 귀 땅 자리(가운데 · 방향) — 에디트 시험용으로 따로
function F.trapCorners(center, yaw, ignore)
	local h = CFG.Trap.Side / 2
	local cf = CFrame.new(center) * CFrame.Angles(0, yaw, 0)
	local out = {}
	for i, s in ipairs(F.SPIKES) do
		local p = cf * Vector3.new(s[2] * h, 0, s[3] * h)
		out[i] = Vector3.new(p.X, groundAt(p, ignore), p.Z)
	end
	return out, cf
end
local function buildTrap(m, at)
	local center, yaw = m:GetAttribute("TrapPos"), m:GetAttribute("TrapYaw") or 0
	if typeof(center) ~= "Vector3" then return nil end
	local ignore = CollectionService:GetTagged("Mech")
	table.insert(ignore, workspace.CurrentCamera)
	local corners, cf = F.trapCorners(center, yaw, ignore)
	local T = { at = at, spikes = {}, cf = cf, center = center }
	local fd = trapFolder()
	for i, s in ipairs(F.SPIKES) do
		local src = m:FindFirstChild(s[1], true)
		local part
		if src and src:IsA("BasePart") then
			part = src:Clone()
			for _, c in ipairs(part:GetChildren()) do if not c:IsA("SurfaceAppearance") then c:Destroy() end end
		else   -- 등 못이 없으면(스트리밍 등) 같은 크기 막대
			part = Instance.new("Part"); part.Size = Vector3.new(1.3, F.SPIKE_LEN, 1.3); part.Color = Color3.fromRGB(200, 205, 210)
		end
		part.Name = "TrapSpike"; part.Anchored = true; part.CanCollide = false; part.CanQuery = false; part.CanTouch = false
		part.Transparency = 0
		part.CFrame = (src and src:IsA("BasePart")) and src.CFrame or CFrame.new(center + Vector3.new(0, 20, 0))
		part.Parent = fd
		local head = Instance.new("Attachment"); head.Name = "Head"; head.Position = Vector3.new(0, F.SPIKE_HEAD, 0); head.Parent = part
		local glow = ctx.fxPart(F.ELEC, Vector3.one * 0.9, CFrame.new(), Enum.PartType.Ball)
		glow.Transparency = 1; glow.Parent = part
		local c = corners[i]
		T.spikes[i] = { part = part, head = head, glow = glow, from = part.CFrame.Position,
			to = CFrame.new(c.X, c.Y + F.SPIKE_LEN / 2 - F.SPIKE_SINK, c.Z) * CFrame.Angles(0, yaw, 0), landed = false }
	end
	hideBack(m, T)
	return T
end
local function makeEdges(T)
	local fd = trapFolder()
	T.beams, T.lines = {}, {}
	local n = #T.spikes
	for i = 1, n do
		local a, b = T.spikes[i], T.spikes[i % n + 1]
		for _, spec in ipairs({ { F.ELEC, 1.1, 0.25 }, { F.ELEC_CORE, 0.35, 0 } }) do
			local bm = Instance.new("Beam")
			bm.Attachment0, bm.Attachment1 = a.head, b.head
			bm.Color = ColorSequence.new(spec[1]); bm.Width0, bm.Width1 = spec[2], spec[2]
			bm.Transparency = NumberSequence.new(spec[3]); bm.LightEmission = 1; bm.LightInfluence = 0
			bm.FaceCamera = true; bm.Segments = 14
			bm.Parent = a.part
			T.beams[#T.beams + 1] = bm
		end
	end
	-- 바닥: 경계선 4 + 옅은 면(가운데 땅 높이 — 판정 사각형 그대로)
	local S2 = CFG.Trap.Side
	local h = S2 / 2
	for _, e in ipairs({ { 0, -h, S2, 0.5 }, { 0, h, S2, 0.5 }, { -h, 0, 0.5, S2 }, { h, 0, 0.5, S2 } }) do
		local ln = ctx.fxPart(F.LINE, Vector3.new(e[3], 0.12, e[4]), T.cf * CFrame.new(e[1], 0.08, e[2]))
		ln.Transparency = 0.1; ln.Parent = fd
		T.lines[#T.lines + 1] = ln
	end
	local fill = ctx.fxPart(F.LINE, Vector3.new(S2, 0.05, S2), T.cf * CFrame.new(0, 0.05, 0))
	fill.Transparency = 0.9; fill.Parent = fd
	T.lines[#T.lines + 1] = fill
	T.fill = fill
	-- 10-30 14:2x 전기 벽(유저 "전기선을 벽으로"): 가운데 땅에서 WallHeight 까지 네 면 = 서버 판정 벽 그대로(MechServer TRAP.step — 발이 이 위면 넘어감)
	--   옅은 면 4장 + 높이별 전기줄(네 귀 안 보이는 기둥의 부착점끼리 빔, 매 프레임 휨)
	local H = CFG.Trap.WallHeight
	T.walls = {}
	for _, e in ipairs({ { 0, -h, S2, 0.15 }, { 0, h, S2, 0.15 }, { -h, 0, 0.15, S2 }, { h, 0, 0.15, S2 } }) do
		local w = ctx.fxPart(F.ELEC, Vector3.new(e[3], H, e[4]), T.cf * CFrame.new(e[1], H / 2, e[2]))
		w.Transparency = 0.9; w.Parent = fd
		T.lines[#T.lines + 1] = w
		T.walls[#T.walls + 1] = w
	end
	local posts = {}
	for i, s in ipairs(F.SPIKES) do
		local p = ctx.fxPart(F.ELEC, Vector3.one * 0.2, T.cf * CFrame.new(s[2] * h, 0, s[3] * h))
		p.Transparency = 1; p.Parent = fd
		T.lines[#T.lines + 1] = p
		posts[i] = {}
		for _, y in ipairs({ 10, 18, 26, H }) do
			local a = Instance.new("Attachment"); a.Position = Vector3.new(0, y, 0); a.Parent = p
			posts[i][#posts[i] + 1] = a
		end
	end
	for i = 1, #posts do
		local A, B = posts[i], posts[i % #posts + 1]
		for k = 1, #A do
			local bm = Instance.new("Beam")
			bm.Attachment0, bm.Attachment1 = A[k], B[k]
			bm.Color = ColorSequence.new(F.ELEC); bm.Width0, bm.Width1 = 0.5, 0.5
			bm.Transparency = NumberSequence.new(0.35); bm.LightEmission = 1; bm.LightInfluence = 0
			bm.FaceCamera = true; bm.Segments = 12
			bm.Parent = A[k].Parent
			T.beams[#T.beams + 1] = bm
		end
	end
	SM.play("MineArm", T.center)   -- 임시: 전기가 이어지는 소리(지뢰 켜짐 소리)
end
-- 감전(서버 MechFX "trapShock" — 벽을 넘으려다 막힘): 벽 자리에 노란 번쩍 + 전기 조각 · 맞은 게 나면 화면 흔들림
local function shockFx(m, victim, pos)
	local ball = ctx.fxPart(F.ELEC_CORE, Vector3.one * 2, CFrame.new(pos), Enum.PartType.Ball)
	ball.Transparency = 0.1
	TweenService:Create(ball, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * 10, Transparency = 1 }):Play()
	Debris:AddItem(ball, 0.27)
	for _ = 1, 8 do
		local d = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
		d = d.Magnitude > 0.05 and d.Unit or Vector3.yAxis
		local L = 2 + math.random() * 3
		local p = ctx.fxPart(F.ELEC, Vector3.new(0.25, 0.25, L), CFrame.lookAlong(pos + d * L / 2, d))
		p.Transparency = 0.1
		TweenService:Create(p, TweenInfo.new(0.18), { Transparency = 1 }):Play()
		Debris:AddItem(p, 0.2)
	end
	if typeof(ctx.spark) == "function" then ctx.spark(pos, Vector3.yAxis) end
	if victim == ctx.mech() then ctx.shake(0.8) end
end
local function endTrap(m, T, now)
	if T.ended then return end
	T.ended = now
	for _, bm in ipairs(T.beams or {}) do bm.Enabled = false end
	for _, s in ipairs(T.spikes) do
		TweenService:Create(s.part, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		s.glow.Transparency = 1
	end
	for _, ln in ipairs(T.lines or {}) do TweenService:Create(ln, TweenInfo.new(0.3), { Transparency = 1 }):Play() end
end
local function dropTrap(m, T)
	for _, s in ipairs(T.spikes) do s.part:Destroy() end
	for _, ln in ipairs(T.lines or {}) do ln:Destroy() end
	showBack(T)
	traps[m] = nil
end
-- 날아가는 못 자리: 수평은 곧게 · 높이 = 직선 + 포물선 혹(먼 귀일수록 높이) · 촉(−Y)이 날아가는 쪽 → 끝 15% 에 똑바로 섬
function F.spikeFly(s, u)
	local from, to = s.from, s.to.Position
	local flatD = Vector3.new(to.X - from.X, 0, to.Z - from.Z).Magnitude
	local H = math.clamp(8 + flatD * 0.18, 8, 30)
	local pos = from:Lerp(to, u) + Vector3.new(0, 4 * H * u * (1 - u), 0)
	local vel = (to - from) + Vector3.new(0, 4 * H * (1 - 2 * u), 0)
	if vel.Magnitude < 0.01 then vel = -Vector3.yAxis end
	local cf = CFrame.lookAlong(pos, vel.Unit) * CFrame.Angles(math.rad(90), 0, 0)
	if u > 0.85 then cf = cf:Lerp(s.to.Rotation + pos, sm((u - 0.85) / 0.15)) end
	return cf
end
local function stepTraps()
	local nowS = workspace:GetServerTimeNow()
	local t = os.clock()
	for _, m in ipairs(CollectionService:GetTagged("Mech")) do
		local at = m:GetAttribute("TrapAt")
		local T = traps[m]
		if T and T.at ~= at then dropTrap(m, T); T = nil end
		local ph, k = CFG.trapPhase(m, nowS)
		if at and ph and not T then
			T = buildTrap(m, at)
			traps[m] = T
		end
		if T then
			if not ph and not T.ended then endTrap(m, T, t) end
			if T.ended then
				if t - T.ended > 0.35 then dropTrap(m, T) end
			elseif ph == "fly" then
				for _, s in ipairs(T.spikes) do s.part.CFrame = F.spikeFly(s, k) end
			else
				for _, s in ipairs(T.spikes) do
					if not s.landed then
						s.landed = true
						s.part.CFrame = s.to
						local base = s.to.Position - Vector3.new(0, F.SPIKE_LEN / 2 - F.SPIKE_SINK, 0)
						if typeof(ctx.spark) == "function" then ctx.spark(base, Vector3.yAxis) end
						SM.play("PodDrop", base)
					end
					s.glow.CFrame = s.part.CFrame * CFrame.new(0, F.SPIKE_HEAD, 0)
					s.glow.Transparency = (ph == "arm") and ((math.floor(t * 12) % 2 == 0) and 0.2 or 0.8) or (0.15 + 0.2 * math.random())
				end
				if ph == "on" then
					if not T.beams then makeEdges(T) end
					for _, bm in ipairs(T.beams) do   -- 전기: 휘는 정도를 매 프레임 바꿈
						bm.CurveSize0 = (math.random() - 0.5) * 5
						bm.CurveSize1 = (math.random() - 0.5) * 5
					end
					if T.fill then T.fill.Transparency = 0.86 + 0.06 * math.sin(t * 8) end
					for i, w in ipairs(T.walls or {}) do w.Transparency = 0.88 + 0.05 * math.sin(t * 9 + i) + 0.03 * math.random() end
				end
			end
		end
	end
	for m, T in pairs(traps) do
		if not m.Parent then dropTrap(m, T) end
	end
end

function F.init(c)
	ctx = c
	RunService.RenderStepped:Connect(function(dt)
		local ok, err = pcall(stepComets, dt)
		if not ok and not F.errA then F.errA = true; warn("[MechFalco] 라이더킥 혜성 오류(한 번만): " .. tostring(err)) end
		ok, err = pcall(stepTraps)
		if not ok and not F.errB then F.errB = true; warn("[MechFalco] 마비 덫 화면 오류(한 번만): " .. tostring(err)) end
	end)
	Remotes.MechFX.OnClientEvent:Connect(function(kind, m, victim, pos, dealt)
		if kind == "riderHit" and typeof(pos) == "Vector3" then hitFx(m, victim, pos, dealt == true) end
		if kind == "riderTick" and typeof(pos) == "Vector3" then tickFx(m, victim, pos, dealt) end   -- dealt 자리 = 몇 번째 대
		if kind == "trapShock" and typeof(pos) == "Vector3" then shockFx(m, victim, pos) end
	end)
end
return F
