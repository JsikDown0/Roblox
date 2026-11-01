-- SoundManager (2026-10-25) — 메카 프로토의 모든 소리 주인
-- ■ 규칙: Sound 인스턴스는 이 모듈만 만든다. 기능은 이름으로 M.play 만 부른다.
--   새 소리를 넣을 때: 아래 SOUNDS 에 한 줄 추가 → grep "Instance.new(\"Sound\")" 가 이 모듈 밖에서 0 인지 확인.
-- ■ 서버에서 play = 모든 클라에 "이 소리 내라" 알림(Remotes.MechFX 의 "sfx"). 소리는 언제나 각 클라가 만든다
--   → 나중에 설정창(분류별 크기)을 만들면 각자 화면에서 바로 먹는다.
-- ■ 최종 크기 = 소리 vol × 부를 때 opts.vol × 분류(GROUPS) × 전체(MASTER).
--   분류·전체는 SoundService 의 SoundGroup(클라에만 만듦)이라 재생 중인 소리에도 즉시 걸린다.
-- ■ 겹침 방지: gap = 같은 소리를 이 시간 안에 또 부르면 무시(한 번에 여러 대상 적중 → 소리가 겹쳐 커지는 것)
--              max  = 동시에 울리는 최대 개수(넘으면 무시)
--              slot = 같은 파트에서 같은 slot 끼리 Sound 하나를 돌려 씀(새로 울리면 앞 소리가 끊김. 옛 발소리 thud 방식)

local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local Remotes = script.Parent:WaitForChild("Remotes")
local IS_SERVER = RunService:IsServer()

local M = {}

-- 분류 크기(0~1). 설정창이 생기면 이 단위로 조절한다
M.GROUPS = {
	Gun = 1,      -- 라이플 발사·적중
	Saber = 1,    -- 빔사벨 휘두름·적중
	Impact = 1,   -- 기체 파괴
	Move = 1,     -- 발소리·착지·몸 부딪힘
	Missile = 1,  -- 미사일 사출·터짐
	Launch = 1,   -- 캐터펄트 사출(10-25): 셔틀 고정·발진 패널 삑·사출 굉음·출구 이탈
}
M.MASTER = 1

-- 소리 목록. 지금은 전부 로블록스 내장 소리(rbxasset://sounds, 올릴 필요 없음)인 임시본. 진짜 소리로 바꿀 땐 id 만 교체
--   id = 소리 · speed = 재생 속도(낮을수록 굵고 길다) · vol = 크기 · group = 분류 · jitter = 재생 속도 흔들기(±비율)
--   near / far = 이 거리(스터드)까지 원래 크기 / 여기서 0 · gap · max · slot = 위 설명
M.SOUNDS = {
	SaberSwing  = { id = "rbxasset://sounds/swordslash.wav", speed = 0.7, vol = 0.6, group = "Saber", jitter = 0.06, near = 25, far = 500, gap = 0.05, max = 6 },   -- 10-25 1.3 → 0.6
	SaberHit    = { id = "rbxasset://sounds/hit.wav", speed = 0.75, vol = 0.8, group = "Saber", jitter = 0.06, near = 25, far = 500, gap = 0.06, max = 6 },          -- 10-25 1.6 → 0.8
	GunFire     = { id = "rbxasset://sounds/paintball.wav", speed = 0.85, vol = 0.9, group = "Gun", jitter = 0.06, near = 25, far = 500, max = 12 },
	SniperFire  = { id = "rbxasset://sounds/paintball.wav", speed = 0.5, vol = 1.5, group = "Gun", jitter = 0.04, near = 40, far = 1000, max = 4 },   -- 10-25 저격총(임시: 같은 소리를 낮고 크게)
	GunHit      = { id = "rbxasset://sounds/snap.wav", speed = 1.15, vol = 1.0, group = "Gun", jitter = 0.06, near = 25, far = 500, gap = 0.03, max = 8 },
	MechDestroy = { id = "rbxasset://sounds/collide.wav", speed = 0.55, vol = 1.2, group = "Impact", jitter = 0.04, near = 30, far = 700, gap = 0.1, max = 3 }, -- 10-25 3 → 1.2
	-- 발: 옛 MechClient thud 그대로(같은 발에서 새로 디디면 앞 소리 끊김 — 발소리 원본이 2.48초짜리라 끊지 않으면 쌓인다 [실측])
	Step        = { id = "rbxasset://sounds/action_footsteps_plastic.mp3", speed = 0.42, vol = 0.9, group = "Move", jitter = 0.08, near = 20, far = 260, slot = "thud" },
	Land        = { id = "rbxasset://sounds/action_jump_land.mp3", speed = 0.5, vol = 0.9, group = "Move", jitter = 0.08, near = 20, far = 260, slot = "thud" },
	BodyHit     = { id = "rbxasset://sounds/action_jump_land.mp3", speed = 0.9, vol = 1.1, group = "Move", jitter = 0.08, near = 20, far = 260, slot = "thud" },   -- 근접에 맞은 몸 쿵
	-- 미사일 컨테이너(10-25, 임시 내장 소리)
	MissileLaunch = { id = "rbxasset://sounds/Rocket shot.wav", speed = 1.1, vol = 0.7, group = "Missile", jitter = 0.08, near = 25, far = 500, gap = 0.03, max = 8 },   -- 한 발 사출
	MissileBoom   = { id = "rbxasset://sounds/collide.wav", speed = 0.85, vol = 0.9, group = "Missile", jitter = 0.08, near = 30, far = 600, gap = 0.04, max = 6 },     -- 터짐
	PodDrop       = { id = "rbxasset://sounds/action_jump_land.mp3", speed = 0.7, vol = 0.8, group = "Move", jitter = 0.05, near = 20, far = 260, gap = 0.2 },          -- 포드 떨어뜨림
	-- 캐터펄트 사출(10-25, 임시 내장 소리). 부르는 곳: MechClient 캐터펄트 연출(각 화면이 LaunchAt 시각표로 직접 냄)
	CatapultLock  = { id = "rbxasset://sounds/metal.ogg", speed = 0.55, vol = 1.3, group = "Launch", jitter = 0.03, near = 30, far = 400, gap = 0.3 },            -- 셔틀이 발을 물음(탈 때)
	LaunchBeep    = { id = "rbxasset://sounds/electronicpingshort.wav", speed = 1.0, vol = 0.45, group = "Launch", near = 40, far = 200, gap = 0.1 },          -- 발진 패널 CLEAR(조종자 화면만)
	LaunchGo      = { id = "rbxasset://sounds/electronicpingshort.wav", speed = 1.45, vol = 0.6, group = "Launch", near = 40, far = 200, gap = 0.1 },          -- 발진 패널 LAUNCH
	CatapultFire  = { id = "rbxasset://sounds/Launching rocket.wav", speed = 0.6, vol = 2.0, group = "Launch", jitter = 0.03, near = 50, far = 900, gap = 0.5 }, -- 사출 순간 쾅
	CatapultRoar  = { id = "rbxasset://sounds/Rocket whoosh 01.wav", speed = 0.85, vol = 1.4, group = "Launch", jitter = 0.03, near = 50, far = 900, gap = 0.5 },-- 가속 내내 굉음(약 7초짜리, 이탈 뒤 서서히 멀어짐)
	CatapultExit  = { id = "rbxasset://sounds/Shoulder fired rocket.wav", speed = 0.75, vol = 1.3, group = "Launch", jitter = 0.04, near = 40, far = 700, gap = 0.5 }, -- 출구 이탈 + 부스터 점화
	-- 지하 땅굴 사출(10-25 16:24)
	HangarDoor    = { id = "rbxasset://sounds/metal.ogg", speed = 0.3, vol = 1.8, group = "Launch", near = 40, far = 600, gap = 0.5 },                         -- 격납고 철문 열림(쿵)
	LaunchSkid    = { id = "rbxasset://sounds/collide.wav", speed = 0.45, vol = 1.3, group = "Launch", jitter = 0.04, near = 40, far = 600, gap = 0.5 },       -- 문 밖 착지 · 땅 긁으며 미끄러짐
	-- 조종사 제트팩(10-29, 임시 내장 소리). 부르는 곳: PilotJetpackServer — Shift 부스트를 켤 때 한 번(치익)
	JetIgnite     = { id = "rbxasset://sounds/Rocket shot.wav", speed = 1.5, vol = 0.45, group = "Move", jitter = 0.06, near = 15, far = 200, gap = 0.25 },
	-- 10-30 SKADI 센서 지뢰(임시 내장 소리). 부르는 곳: MechServer MINE — 땅에 닿음 · 켜짐 · 감지(예고 깜빡임 시작) · 폭발
	MineDrop      = { id = "rbxasset://sounds/metal.ogg", speed = 1.3, vol = 0.7, group = "Missile", jitter = 0.05, near = 20, far = 260, gap = 0.1 },
	MineArm       = { id = "rbxasset://sounds/electronicpingshort.wav", speed = 0.8, vol = 0.35, group = "Missile", near = 20, far = 200, gap = 0.1 },
	MineBeep      = { id = "rbxasset://sounds/electronicpingshort.wav", speed = 1.9, vol = 0.8, group = "Missile", near = 30, far = 400, gap = 0.1 },
	MineBoom      = { id = "rbxasset://sounds/collide.wav", speed = 0.7, vol = 1.3, group = "Missile", jitter = 0.06, near = 35, far = 700, gap = 0.04, max = 4 },
	-- 10-30 궁극기 발동(임시 내장 소리, 모든 기체 공용). 부르는 곳: MechServer MechUlt
	UltActivate   = { id = "rbxasset://sounds/electronicpingshort.wav", speed = 0.5, vol = 1.2, group = "Gun", near = 40, far = 600, gap = 0.3 },
}

-- ---------- 분류 SoundGroup (클라 전용. 서버는 만들지 않아 복제 중복이 없다) ----------
local groups = {}
local function groupOf(name)
	if IS_SERVER then return nil end
	if groups[name] then return groups[name] end
	local master = SoundService:FindFirstChild("MechSfx")
	if not master then
		master = Instance.new("SoundGroup"); master.Name = "MechSfx"; master.Volume = M.MASTER; master.Parent = SoundService
	end
	if not name then return master end
	local g = master:FindFirstChild(name)
	if not g then
		g = Instance.new("SoundGroup"); g.Name = name; g.Volume = M.GROUPS[name] or 1; g.Parent = master   -- 겹친 SoundGroup 은 크기가 곱해진다
	end
	groups[name] = g
	return g
end

-- 분류 크기 바꾸기(클라). group = nil 또는 "Master" 면 전체
function M.setVolume(group, v)
	v = math.clamp(v, 0, 2)
	if group == nil or group == "Master" then
		M.MASTER = v
		local g = groupOf(nil); if g then g.Volume = v end
	else
		M.GROUPS[group] = v
		local g = groupOf(group); if g then g.Volume = v end
	end
end

-- ---------- 재생 ----------
local lastAt = {}    -- 이름 → 마지막으로 낸 시각(gap)
local live = {}      -- 이름 → { 끝나는 시각, ... }(max)
local warned = {}

local function countLive(name, now)
	local list = live[name]
	if not list then list = {}; live[name] = list end
	local n = 0
	for i = #list, 1, -1 do
		if list[i] <= now then table.remove(list, i) else n += 1 end
	end
	return list, n
end

-- name = SOUNDS 의 이름 / at = 파트·어태치먼트(따라다님) 또는 Vector3(그 자리) / opts = { vol = 곱, speed = 곱 }
-- 서버에서 부르면 모든 클라에 보낸다(돌려주는 값 없음). 클라에선 만든 Sound 를 돌려준다(안 냈으면 nil)
function M.play(name, at, opts)
	local spec = M.SOUNDS[name]
	if not spec then
		if not warned[name] then warned[name] = true; warn("[SoundManager] 없는 소리 이름: " .. tostring(name)) end
		return nil
	end
	if at == nil then return nil end
	if IS_SERVER then
		Remotes.MechFX:FireAllClients("sfx", name, at, opts)
		return nil
	end
	if typeof(at) == "Instance" and not at:IsDescendantOf(workspace) then return nil end
	local now = os.clock()
	if spec.gap and now - (lastAt[name] or -99) < spec.gap then return nil end
	local list, n = countLive(name, now)
	if spec.max and n >= spec.max then return nil end
	lastAt[name] = now

	local speed = (spec.speed or 1) * (opts and opts.speed or 1)
	local j = spec.jitter or 0
	if j > 0 then speed *= (1 - j) + math.random() * 2 * j end

	local s
	local reuse = spec.slot and typeof(at) == "Instance"
	if reuse then
		local key = "SM_" .. spec.slot
		s = at:FindFirstChild(key)
		if not (s and s:IsA("Sound")) then
			s = Instance.new("Sound"); s.Name = key; s.Parent = at
		end
	else
		s = Instance.new("Sound"); s.Name = "SM_" .. name
	end
	s.SoundId = spec.id
	s.PlaybackSpeed = speed
	s.Volume = (spec.vol or 1) * (opts and opts.vol or 1)
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = spec.near or 25
	s.RollOffMaxDistance = spec.far or 500
	s.SoundGroup = groupOf(spec.group)
	if not reuse then
		local holder = s
		if typeof(at) == "Vector3" then
			local a = Instance.new("Attachment"); a.Name = "SM_At"; a.Parent = workspace.Terrain; a.WorldPosition = at
			s.Parent = a; holder = a
		else
			s.Parent = at
		end
		s.Ended:Once(function() holder:Destroy() end)
		Debris:AddItem(holder, 8)   -- 안 끝나는 경우(로드 실패 등) 안전망
	end
	s:Play()
	local len = s.TimeLength > 0 and s.TimeLength / speed or 1
	table.insert(list, now + len)
	return s
end

-- 지금 상태 한 줄: "전체 1.00 · Gun 1.00 … | 울리는 중 GunFire 2 · Step 1"
function M.describe()
	local now = os.clock()
	local g = {}
	for k, v in pairs(M.GROUPS) do table.insert(g, string.format("%s %.2f", k, v)) end
	table.sort(g)
	local l = {}
	for k in pairs(live) do
		local _, n = countLive(k, now)
		if n > 0 then table.insert(l, k .. " " .. n) end
	end
	table.sort(l)
	return string.format("전체 %.2f · %s | 울리는 중 %s", M.MASTER, table.concat(g, " · "), #l > 0 and table.concat(l, " · ") or "없음")
end

-- 클라: 서버가 보낸 소리
if not IS_SERVER then
	Remotes.MechFX.OnClientEvent:Connect(function(kind, name, at, opts)
		if kind == "sfx" then M.play(name, at, opts) end
	end)
end

return M
