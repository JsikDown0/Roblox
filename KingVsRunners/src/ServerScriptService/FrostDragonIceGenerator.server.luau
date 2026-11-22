-- Frost Dragon 얼음 브레스 강하 (활공 + 브레스 + 얼음 라인 + 즉사 + 슬로우 + 장기지속/쿨타임)
-- 드래곤이 시작점에서 러너 방향으로 활공하며 지면에 얼음 라인을 뿌림. 활공 후 페이드아웃, 얼음은 장기 지속.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local frostDragon = script.Parent
if not frostDragon.PrimaryPart then return end
local startPos = frostDragon.PrimaryPart.Position

local dir = frostDragon:GetAttribute("FireDirection")
if not dir or dir.Magnitude < 0.01 then warn("[FrostDragon] FireDirection 없음"); return end
dir = Vector3.new(dir.X, 0, dir.Z).Unit
local ownerId = frostDragon:GetAttribute("FrostOwner")

-- ── 튜닝값 ──
local LINE_LENGTH   = 800   -- 사거리(stud)
local SPIKE_SPACING = 24    -- 기둥 간격(레인당)
local DURATION      = 15    -- 활공 완료 후 얼음 지속(초) = 쿨타임
local GLIDE_HEIGHT  = 22    -- 드래곤 활공 높이
local ADVANCE       = 0.135 -- 기둥/활공 간격 → 속도 = SPACING/ADVANCE = 178 stud/s
local SLOW_MULT     = 0.5   -- 슬로우 배율
-- [판정 = 시각 원칙] 아래 두 반경은 '눈에 보이는 얼음' 범위와 반드시 일치시킬 것.
--   측면: 레인 최대 ±16 + 반경 ≤ 빙판 반폭 29  → 반경 ≤ 13
--   진행: 반경 × 2 ≥ SPIKE_SPACING(24) 이어야 기둥 사이로 빠져나가지 못함 → 반경 ≥ 12
local SLOW_RADIUS   = 13    -- 슬로우+지속딜 반경 (±29 = 빙판 폭과 정확히 일치)
local KILL_RADIUS   = 12.5  -- 즉사 반경(레인별). ×2=25 ≥ 간격24 → 진행방향 연속
local ZONE_TTK      = 3.5   -- 잔류 지대 안에서 사망까지(초, 슬로우 감안)
-- 다중 레인: 중심선 좌우로 얼음 줄을 늘려 '폭'을 확보.
-- [주의] 반경만 키우면 안 보이는 얼음에 죽으므로 시각(기둥)과 판정을 함께 넓힘.
-- [주의] LANES 는 홀수 권장 — 중앙(k=0) 레인이 드래곤 활공/빔의 기준.
-- 기둥을 지면에 얼마나 박을지(stud). 0이면 딱 얹힘(경사에서 떠 보임), 클수록 파묻힘.
-- [원인] 기존엔 PrimaryPart 중심을 지면에 뒀는데 pivot이 bbox 바닥보다 8 위라 절반이 묻혔음.
local SPIKE_BURY  = 4.0
-- 태거베이스 '위'에는 얼음(기둥/빙판)과 판정을 생성하지 않음.
-- [거리 대신 이름으로 판정하는 이유] 맵마다 태거베이스 크기/위치가 달라 매직넘버(거리)는 위험.
--   map1 "taggerbase" / map2 "taggerbase2" 둘 다 prefix 매칭으로 자동 대응.
--   ItemSpawnPlate·Hill 은 그대로 생성 → 비스듬한 빙판길 보존됨.
-- [주의] 시각(기둥)과 판정(즉사/슬로우)을 반드시 함께 빼야 함 — 안 보이는 얼음에 죽으면 안 됨.
local SKIP_ON_TAGGERBASE = true
local function isTaggerBase(inst)
	if inst == nil then return false end
	if inst.Name:lower():sub(1, 10) == "taggerbase" then return true end
	-- 🧱 [BARRICADE-SKIP 2026-08-27] 바리케이드(성문) 위에도 얼음을 만들지 않는다.
	--   [증상] 얼음 지대가 바리케이드에 걸쳐 생성돼 태거 시야를 가렸다(실측 2회).
	--   [왜 페이드로 못 고쳤나] BarricadeFadeClient 에 얼음을 추가해봤지만,
	--     그건 '이미 생긴 얼음'을 흐리게 할 뿐이다. 성문 위에 얹힌 얼음은 성문이
	--     부서질 때 공중에 뜨고, 판정도 남는다. 생성 자체를 막는 게 맞다.
	--   [왜 이 함수인가] 시각(기둥·빙판)과 판정(즉사·슬로우)이 이 한 함수를 같이 본다.
	--     여기서 막으면 "안 보이는 얼음에 죽는" 불일치가 생기지 않는다.
	--
	-- ⚠️ [2026-08-28 수정] 예전 구현은 인스턴스와 그 조상에서 BarricadeGate 속성을
	--   찾았는데, 그 속성은 성문이 아니라 '바리케이드 세그먼트'에 이름 목록으로 붙어 있다.
	--   그래서 Gatehouse·GateWing1/2·Middle Wall 1~7(map2 는 Gatehouse2·GateBlocker2·
	--   Gate2·GatePocketFill2)이 전부 미검출이었고, 게이트하우스 위에 얼음이 그대로
	--   생성됐다(실측 2026-08-28 map1 스크린샷 + 15개 구조물 조회로 확인).
	--   → 판정을 _G.IsGateStructure 로 일원화했다. 원본은 BarricadeSystem 에 있고,
	--     BlackHoleSystem.rejectLanding 도 같은 함수를 쓴다. 여기서 복사하지 말 것.
	if _G.IsGateStructure and _G.IsGateStructure(inst) then return true end
	return false
end

-- 🛡️ 캐릭터가 태거 베이스 '안'에 있는지 (살상 면역용)
-- ⚠️ [2026-08-28] 판정을 _G.IsCharInTaggerBase 로 일원화했다. 여기서 복사하지 말 것.
--   [왜] Bomb·EnergyBall·DemonSpear·Spear 가 같은 로직을 각자 갖고 있었고(5벌),
--     그중 Spear 만 높이 밴드가 빠져 map2 성 바닥에서 면역이 안 걸렸다.
--   ⚠️ 원본은 ItemSpawnHandler 에 있다. 높이 밴드·캐시 무효화·showBaseImmune 포함.
local function isInTaggerBase(model)
	return _G.IsCharInTaggerBase(model)
end
-- 빙판길: 판정 없는 외형 전용. 경사를 따라가야 해서 스텝마다 슬래브를 깔고 지면 법선에 정렬.
local PATH_WIDTH  = 58     -- 통짜 1장 폭 (레인 ±16 + 기둥 ±11.5 커버)
local PATH_THICK  = 0.4
local PATH_SUBDIV = 8      -- 스텝(24)당 샘플 수 → 3 stud 간격 (묻힘 0.09까지 감소)
-- 인접 구간이 이 값 이상으로 같은 방향이면 한 장으로 병합.
-- 8등분을 그대로 만들면 264장(모바일 부담) → 평지/등경사는 1장으로 합쳐 30~60장 수준 유지.
local PATH_MERGE_COS = 0.999   -- ≈2.5도 이내면 일직선으로 간주
local PATH_LIFT   = 0.30   -- 지면과 z-fighting 방지용 살짝 띄우기
local PATH_TRANSP = 0.35
local LANES       = 3     -- 레인 수 (좌/중/우)
local LANE_OFFSET = 16    -- 레인 간 측면 간격
-- 조명/연기는 중앙 레인 + 이 간격마다만. 로블록스 동시 렌더 조명 한계가 ~30개라
-- 전 기둥에 넣으면 깜빡임+렉 (기존 57개도 이미 초과였음)
local LIGHT_EVERY = 3
local SHOW_RANGE    = false -- [디버그] 판정 범위 원판 표시

local spikeCount = math.floor(LINE_LENGTH / SPIKE_SPACING)

local iceSpikeTemplate = ServerStorage:WaitForChild("TaggerItem"):FindFirstChild("IceSpike")
if not iceSpikeTemplate then warn("[FrostDragon] IceSpike 템플릿 없음"); return end

local iceFolder = Instance.new("Folder")
iceFolder.Name = "FrostIce_" .. tostring(ownerId or "x")
iceFolder.Parent = workspace   -- 드래곤과 독립 → 드래곤 페이드 후에도 얼음 지속

-- [중요] 이 스크립트는 드래곤 안에 클론되지만, 드래곤은 엔딩 후 Destroy 됨.
-- 그대로 두면 스크립트가 같이 죽어 아래 task.delay(DURATION) 정리 스레드가 취소되고
-- 얼음이 영구히 남는다. → 얼음 폴더로 옮겨 '얼음과 수명을 같이함'.
-- (frostDragon 참조는 위에서 이미 캐시했으므로 안전)
script.Parent = iceFolder

-- ── 얼음 브레스 빔 (입 → 지면 착탄점) ──
local BEAM_LEAD = 18          -- 착탄점을 드래곤보다 얼마나 앞에 둘지(stud)
local beamModel, beamP1, beamP2 = nil, nil, nil
do
	local tpl = ServerStorage:WaitForChild("TaggerItem"):FindFirstChild("IceBeam")
	if tpl then
		beamModel = tpl:Clone()
		beamP1 = beamModel:FindFirstChild("BeamPart1")
		beamP2 = beamModel:FindFirstChild("BeamPart2")
		for _, p in ipairs(beamModel:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
				p.Transparency = 1
			end
		end
		beamModel.Parent = frostDragon   -- 드래곤과 함께 정리됨
	else
		warn("[FrostDragon] IceBeam 템플릿 없음 — 빔 생략")
	end
end
-- 입 위치 소스(모델과 함께 이동). 없으면 pivot 기준 오프셋으로 폴백.
local mouthPart = frostDragon:FindFirstChild("MouthParticles")
local function mouthPos()
	if mouthPart then return mouthPart.Position end
	return frostDragon:GetPivot():PointToWorldSpace(Vector3.new(0, 11.1, -10.4))
end
local function updateBeam(groundPos)
	if not (beamP1 and beamP2) then return end
	beamP1.CFrame = CFrame.new(mouthPos())
	beamP2.CFrame = CFrame.new(groundPos + dir * BEAM_LEAD)
end

-- 브레스 파티클 ON + 드래곤 충돌/터치 끄기 + 다운 방지 (다른 태거 아이템에 안 걸리게)
local dragonHum = frostDragon:FindFirstChildOfClass("Humanoid")
if dragonHum then
	dragonHum.MaxHealth = math.huge
	dragonHum.Health = math.huge
	dragonHum.BreakJointsOnDeath = false
	pcall(function() dragonHum:SetStateEnabled(Enum.HumanoidStateType.Dead, false) end)
	pcall(function() dragonHum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false) end)
	pcall(function() dragonHum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false) end)
	pcall(function() dragonHum:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, false) end)
end
for _, d in ipairs(frostDragon:GetDescendants()) do
	if d:IsA("ParticleEmitter") then
		-- Breath* 는 켜지 않음: 브레스 줄기는 IceBeam이 담당 (이중 분사 방지)
		-- 켜지는 것: Idle*(입가 김), icefx_point(몸 오라), IceBeam Sparks(양끝 스파크)
		d.Enabled = (d.Name:find("Breath") == nil)
	elseif d:IsA("BasePart") then d.CanCollide = false; d.CanTouch = false end
end

local slowed = {}
-- 🚧 [2026-08-26] 지대가 이미 다운시킨 대상. 중복 처리 방지.
--   Heartbeat 루프라 가드가 없으면 매 프레임 processHit + Part 생성이 반복된다.
local zoneDowned = {}
local function applySlow(hum) if not slowed[hum] then slowed[hum] = hum.WalkSpeed; hum.WalkSpeed = hum.WalkSpeed * SLOW_MULT end end

-- 대상 수집: 플레이어 러너 + NPC(더미). 태거/드래곤 제외. (블랙홀 방식 — NPC도 잡음)
local function collectTargets()
	local out = {}
	for _, child in ipairs(workspace:GetChildren()) do
		if child ~= frostDragon then
			local hum = child:FindFirstChildOfClass("Humanoid")
			local hrp = hum and hum.RootPart
			if hum and hrp and hum.Health > 0 then
				local plr = Players:GetPlayerFromCharacter(child)
				local isTarget
				if plr then
					isTarget = (plr.UserId ~= ownerId) and (plr:GetAttribute("Role") == "Runner")
				else
					isTarget = true   -- NPC (더미 등)
				end
				-- ⚠️ char 도 담는다. 태거베이스 판정에 쓴다.
				if isTarget then out[#out + 1] = { hum = hum, hrp = hrp, char = child } end
			end
		end
	end
	return out
end

-- 원판을 지면 경사(normal)에 눕히는 CFrame (local X축 = normal)
local function discCFrame(centerPos, normal)
	local up = normal.Unit
	local arb = math.abs(up.Y) < 0.99 and Vector3.new(0, 1, 0) or Vector3.new(1, 0, 0)
	local right = up:Cross(arb).Unit
	local fwd = up:Cross(right).Unit
	return CFrame.fromMatrix(centerPos, up, right, fwd)
end

-- ── 등장 연출: 상공 뒤편에서 강하 → 활공 시작점 ──
-- (280 stud/초로 스쳐 지나가 연출이 안 보이던 문제 → 느린 등장 페이즈로 보여줌)
-- 얼음/킬 판정은 뒤의 활공 루프가 담당 → 밸런스 무영향. 텔레그래프(예고) 효과도 겸함.
-- ── 사운드 ──
-- [주의] 드래곤이 800 stud를 가로지르므로 기본 롤오프(MinDistance=10)면 100 stud만 떨어져도
--        볼륨 10% = 사실상 안 들림. 아래 값들은 이동체 기준으로 크게 잡음.
local SND_HOWL = "rbxassetid://117046970320317"   -- 드래곤 하울링 (원샷, 강하 시작)
local SND_WIND = "rbxassetid://120314305298413"   -- 겨울바람 (루프, 돌진 중)
local SND_ICE  = "rbxassetid://82245763898123"    -- 얼음 생성 (원샷, 듬성듬성)
local ICE_SOUND_EVERY = 7    -- N기둥마다 1회 (57기둥/2.85초 = 초당 20개 → 전부 재생 시 소음)
local WIND_FADE = 0.4        -- 돌진 종료 시 바람 페이드아웃(초)

local sndRoot = frostDragon.PrimaryPart

local howl = Instance.new("Sound")
howl.Name = "FrostHowl"
howl.SoundId = SND_HOWL
howl.Volume = 1
howl.RollOffMode = Enum.RollOffMode.InverseTapered
howl.RollOffMinDistance = 150   -- 텔레그래프 → 맵 전역에서 들려야 함
howl.RollOffMaxDistance = 900
howl.Parent = sndRoot

local wind = Instance.new("Sound")
wind.Name = "FrostWind"
wind.SoundId = SND_WIND
wind.Volume = 0.8
wind.Looped = true
wind.RollOffMode = Enum.RollOffMode.InverseTapered
wind.RollOffMinDistance = 60    -- 드래곤 근처에서만
wind.RollOffMaxDistance = 400
wind.Parent = sndRoot

local ENTRANCE_TIME   = 2.0   -- 강하 소요(초)
local HOVER_TIME      = 1.5   -- 돌진 직전 체공(정지 비행) 시간 — 날갯짓 보여주는 구간
local HOVER_BOB       = 1.6   -- 체공 중 미세 상하 진폭(얼어붙은 듯 보이지 않게)
local ENTRANCE_HEIGHT = 90    -- 활공 시작점보다 위
local ENTRANCE_BACK   = 70    -- 활공 시작점보다 뒤(태거 쪽)

-- 등장 중엔 빔 숨김 (아직 얼음 착탄점이 없어 엉뚱한 곳에 그려짐)
local function setBeamEnabled(on)
	if not beamModel then return end
	for _, d in ipairs(beamModel:GetDescendants()) do
		if d:IsA("Beam") or d:IsA("ParticleEmitter") then d.Enabled = on end
	end
end
setBeamEnabled(false)

do
	-- 활공 1번째 기둥의 비행 지점 = 등장 도착점
	local firstH = startPos + (dir * SPIKE_SPACING)
	local rp0 = RaycastParams.new()
	rp0.FilterDescendantsInstances = { frostDragon }
	local rr0 = workspace:Raycast(firstH + Vector3.new(0, 200, 0), Vector3.new(0, -600, 0), rp0)
	local firstGround = rr0 and rr0.Position or Vector3.new(firstH.X, startPos.Y - 30, firstH.Z)
	local firstFly = firstGround + Vector3.new(0, GLIDE_HEIGHT, 0)
	local entryStart = firstFly - dir * ENTRANCE_BACK + Vector3.new(0, ENTRANCE_HEIGHT, 0)

	-- 1) 강하: 느리게 시작(잘 보임) → 급강하 → 체공으로 부드럽게 감속
	pcall(function() howl:Play() end)   -- 하울링: 등장을 알림(텔레그래프)
	-- [기수 스냅 방지] 프레임 델타(pos-prevPos)로 기수를 정하면 smoothstep 특성상
	--   시작/끝에서 속도가 0으로 수렴 → 임계값(0.01)을 깨는 순간 52도가 한 프레임에 튐.
	--   RootPart(피벗)가 모델 중심보다 9.6 아래/8.6 앞이라 그 각도 스냅이 몸통을 11 stud
	--   스윙시켜 '뒤로 밀린 것처럼' 보였음(호버 직전/직후에 발생).
	--   → 델타 대신 '고정 강하 방향'을 쓰고, 착지 구간(60~100%)에서 수평으로 서서히 정렬.
	local diveDir = firstFly - entryStart
	diveDir = (diveDir.Magnitude > 0.01) and diveDir.Unit or dir

	local t0 = os.clock()
	while true do
		local a = (os.clock() - t0) / ENTRANCE_TIME
		if a >= 1 then break end
		local e = a * a * (3 - 2 * a)      -- smoothstep (ease-in-out)
		local pos = entryStart:Lerp(firstFly, e)
		local levelBlend = math.clamp((a - 0.6) / 0.4, 0, 1)
		local look = diveDir:Lerp(dir, levelBlend)
		look = (look.Magnitude > 0.01) and look.Unit or dir
		pcall(function() frostDragon:PivotTo(CFrame.lookAt(pos, pos + look)) end)
		task.wait()
	end

	-- 2) 체공: 제자리 정지 비행 → 여기서 날갯짓이 제대로 보임. 이후 돌진이 '도약'처럼 읽힘
	local h0 = os.clock()
	while os.clock() - h0 < HOVER_TIME do
		local t = os.clock() - h0
		local pos = firstFly + Vector3.new(0, math.sin(t * 2.2) * HOVER_BOB, 0)
		pcall(function() frostDragon:PivotTo(CFrame.lookAt(pos, pos + dir)) end)
		task.wait()
	end
	pcall(function() frostDragon:PivotTo(CFrame.lookAt(firstFly, firstFly + dir)) end)
	print(string.format("[FrostDragon] 등장 완료 (강하 %.1fs + 체공 %.1fs) -> 브레스 돌진", ENTRANCE_TIME, HOVER_TIME))
end

wind:Play()   -- 겨울바람: 돌진 내내 루프
local beamOn = false   -- 빔은 얼음이 실제로 생성되는 지점부터 (태거베이스 구간엔 브레스 없음)

-- ── 활공 + 순차 얼음 생성 ──
-- 측면 벡터(수평 수직) — 레인 배치용
local rightV = dir:Cross(Vector3.new(0, 1, 0))
rightV = (rightV.Magnitude > 0.01) and rightV.Unit or Vector3.new(0, 0, 1)
local laneHalf = (LANES - 1) / 2

-- 조명/연기 제거용 (중앙 레인 + LIGHT_EVERY 마다만 남김)
local function stripFx(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("SpotLight") or d:IsA("PointLight") or d:IsA("SurfaceLight") or d:IsA("Smoke") then
			d:Destroy()
		end
	end
end

local spikePositions = {}
local lastGroundY = {}                       -- 레인별 직전 지면 높이(경사에서 레인마다 다름)
for k = -laneHalf, laneHalf do lastGroundY[k] = startPos.Y - 30 end

-- 🧊 [2026-09-16] 지면 레이를 Exclude → Include 로 뒤집는다.
--   [증상] 얼음이 바닥이 아니라 공중에 수직으로 솟았다(실측, 쓰나미 위).
--   [원인] 제외 목록이 { iceFolder, frostDragon } 뿐이라 쓰나미 파도·스폰 아이템·
--     배럴 웅덩이·픽업상자·캐릭터의 '윗면'을 전부 지면으로 읽었다.
--     EnergyBallSystem:152 가 같은 증상을 이미 적어뒀다 —
--     "통나무·배럴·얼음기둥에 맞으면 그 윗면을 지면으로 착각해 공중에 뜬다".
--   [왜 목록을 안 늘리나] 2026-08-27 바리케이드 수정이 이미 '제외 목록' 축이었고,
--     쓰나미가 등장하자 그대로 뚫렸다. GroundRayIgnore 속성을 세우는 곳도
--     BlackHoleSystem 3곳뿐이라(전수 grep) 그 규약을 복사해와도 쓰나미는 못 막는다.
--   [결과 보장] "얼음은 맵 폴더 안 지오메트리 위에만 놓인다"로 뒤집는다.
--     구조적 근거: 얼음을 띄우는 것들은 전부 workspace 최상위에 생성된다
--     (스폰 아이템·쓰나미·웅덩이·픽업·블랙홀·캐릭터). 지면은 전부 맵 폴더 안이다.
--     → 앞으로 아이템이 몇 개 늘어도 여기를 고칠 일이 없다.
--   ⚠️ 이 변경은 현재 동작의 '부분집합'이다. 맞는 대상이 줄기만 하고 늘지 않는다.
--   ⚠️ 새 맵은 폴더 이름이 map* 이어야 한다. 아니면 얼음이 바닥을 뚫는다 —
--     조용히 틀리는 게 아니라 눈에 즉시 보이는 실패라 의도한 방향이다.
--   ⚠️ Include 목록이 비면 '아무것도 안 맞음'이 되어 전부 폴백 높이로 깔린다.
--     그건 조용한 대형 사고라 폴백을 따로 둔다.
local groundTargets = {}
for _, d in ipairs(workspace:GetChildren()) do
	if d.Name:lower():sub(1, 3) == "map" then groundTargets[#groundTargets + 1] = d end
end
local useInclude = (#groundTargets > 0)
if not useInclude then
	warn("[FrostDragon] map* 폴더를 못 찾음 — 지면 레이가 옛 방식(제외)으로 동작한다")
end
local function groundRay(fromPos)
	local rp = RaycastParams.new()
	if useInclude then
		rp.FilterType = Enum.RaycastFilterType.Include
		rp.FilterDescendantsInstances = groundTargets
	else
		rp.FilterDescendantsInstances = { iceFolder, frostDragon }
	end
	return workspace:Raycast(fromPos + Vector3.new(0, 200, 0), Vector3.new(0, -600, 0), rp)
end

for i = 1, spikeCount do
	local centerH = startPos + (dir * SPIKE_SPACING * i)
	-- 태거베이스 위면 얼음/판정 생략 (드래곤 비행은 유지)
	local makeIce = true
	if SKIP_ON_TAGGERBASE then
		local rrC = groundRay(centerH)
		makeIce = not (rrC and isTaggerBase(rrC.Instance))
	end
	if makeIce and not beamOn then setBeamEnabled(true); beamOn = true end
	local centerPos, centerNormal

	for k = -laneHalf, laneHalf do
		local horizontalPos = centerH + rightV * (k * LANE_OFFSET)
		local prevY = lastGroundY[k]          -- 직전 스텝 지면 높이 (빙판 단차 판정용)
		-- 레인마다 따로 레이 — 경사에서 옆 레인이 공중에 뜨거나 파묻히는 것 방지
		local rr = groundRay(horizontalPos)
		-- 🧊 [2026-09-16] 성문·태거베이스 윗면은 '지면'이 아니다.
		--   [왜 여기에도] 2026-08-27 수정은 makeIce 를 중앙 레인(rrC) 하나로만 정했다.
		--     그래서 옆 레인이 성문에 얹히는 건 그대로 남아 있었다 — 반쪽이었다.
		--   ⚠️ 이 판정을 통과 못 하면 높이를 '기억하지도' 않는다. 아래 lastGroundY
		--     갱신이 이 분기 안에 있는 게 핵심이다(오염 전파 차단, 아래 주석 참조).
		local onStructure = (rr ~= nil) and isTaggerBase(rr.Instance)
		if onStructure then rr = nil end
		local finalPos, groundNormal
		if rr then
			finalPos = rr.Position
			groundNormal = rr.Normal
			-- 🧊 [2026-09-16] 오염 전파 차단.
			--   [증상] 기둥 하나가 아니라 '구간 전체'가 벽처럼 떠 있었다.
			--   [원인] 예전엔 이 갱신이 makeIce/구조물 판정보다 위에 있어서,
			--     성문이나 파도 윗면을 한 번 잡으면 그 높이가 뒤 스텝의 폴백으로
			--     계속 끌려갔다. 한 번의 오판이 한 구간을 통째로 띄웠다.
			--   ⚠️ 그래서 '진짜 지면을 맞힌 경우에만' 기억한다. 못 맞힌 스텝은
			--     마지막으로 확인된 실제 지면 높이를 그대로 유지한다.
			lastGroundY[k] = rr.Position.Y
		else
			finalPos = Vector3.new(horizontalPos.X, lastGroundY[k], horizontalPos.Z)
			groundNormal = Vector3.new(0, 1, 0)
		end
		if makeIce and not onStructure then spikePositions[#spikePositions + 1] = finalPos end
		if k == 0 then centerPos = finalPos; centerNormal = groundNormal end
		if not makeIce or onStructure then continue end   -- 이 레인의 기둥 생성 생략

		-- 얼음 기둥
		local spike = iceSpikeTemplate:Clone()
		if not spike.PrimaryPart then
			local big, bv = nil, 0
			for _, p in ipairs(spike:GetDescendants()) do
				if p:IsA("BasePart") then local v = p.Size.X*p.Size.Y*p.Size.Z; if v > bv then bv=v; big=p end end
			end
			if big then spike.PrimaryPart = big end
		end
		-- bbox 바닥이 지면에 오도록 배치 (pivot 기준으로 놓으면 절반이 묻힘)
		do
			local bcf, bsz = spike:GetBoundingBox()
			local pv = spike:GetPivot()
			local pivotToBottom = pv.Position.Y - (bcf.Position.Y - bsz.Y / 2)
			spike:PivotTo(CFrame.new(finalPos + Vector3.new(0, pivotToBottom - SPIKE_BURY, 0)))
		end
		for _, p in ipairs(spike:GetDescendants()) do if p:IsA("BasePart") then p.Anchored=true; p.CanCollide=false end end
		if not (k == 0 and (i % LIGHT_EVERY) == 0) then stripFx(spike) end

		spike.Parent = iceFolder

		-- 얼음 생성음: 중앙 레인, N기둥마다 1회
		if k == 0 and (i % ICE_SOUND_EVERY) == 0 and spike.PrimaryPart then
			local cs = Instance.new("Sound")
			cs.Name = "FrostIceCrack"
			cs.SoundId = SND_ICE
			cs.Volume = 0.7
			cs.RollOffMode = Enum.RollOffMode.InverseTapered
			cs.RollOffMinDistance = 30
			cs.RollOffMaxDistance = 250
			cs.Parent = spike.PrimaryPart
			cs:Play()
			cs.Ended:Once(function() cs:Destroy() end)
		end

		-- 판정 범위 시각화 (디버그)
		if SHOW_RANGE then
			local disc = Instance.new("Part")
			disc.Shape = Enum.PartType.Cylinder
			disc.Size = Vector3.new(0.3, KILL_RADIUS * 2, KILL_RADIUS * 2)
			disc.CFrame = discCFrame(finalPos + groundNormal * 0.3, groundNormal)
			disc.Anchored = true
			disc.CanCollide = false
			disc.CanTouch = false
			disc.CastShadow = false
			disc.Material = Enum.Material.Neon
			disc.Color = Color3.fromRGB(90, 180, 255)
			disc.Transparency = 0.75
			disc.Parent = iceFolder
		end
	end

	centerPos = centerPos or Vector3.new(centerH.X, lastGroundY[0] or (startPos.Y - 30), centerH.Z)
	centerNormal = centerNormal or Vector3.new(0, 1, 0)

	-- 빙판길: 스텝(24)을 PATH_SUBDIV 등분해 지면을 촘촘히 따라가는 리본.
	-- [묻힘 원인] 24 간격만 샘플링하면 그 사이 지형을 모른 채 직선으로 이어버림.
	--   실측: taggerbase 는 거리 42까지 137.8 로 평평하다가 ItemSpawnPlate 경계에서 2.3 급락.
	--   24→48 을 한 판으로 이으면 평평한 구간에서 판만 비스듬히 내려가 최대 1.8 묻힘(두께 0.4라 완전 매몰).
	-- [해결] 등분 샘플링 → 평평한 구간은 평평하게, 낙차는 낙차대로.
	-- [이음새] 각 판의 끝점 = 다음 판의 시작점(같은 지면 샘플) → 구조적으로 어긋나지 않음.
	do
		-- 🧊 [2026-09-16] 빙판 샘플러도 같은 지면 규칙을 쓴다(위 groundRay).
		--   ⚠️ 기둥만 고치고 여기를 놔두면 반쪽이 된다 — 빙판이 파도 위에 깔린다.
		--     게다가 이 슬래브(IcePath)에 BotDangerZone 이 붙으므로, 여기가 뜨면
		--     봇이 '허공의 지대'를 피해 돌아간다(RunnerBotDriveController rescanThreats).
		--   [선례] "같은 구조의 형제가 있으면 한꺼번에 고친다" —
		--     코핀만 고치고 5종이 안 따라온 이력이 두 번 있다.
		local sub = SPIKE_SPACING / PATH_SUBDIV
		local function gAt(off)
			local q = centerH + dir * off
			local rr = groundRay(q)
			local p = rr and rr.Position or Vector3.new(q.X, centerPos.Y, q.Z)
			local onB = SKIP_ON_TAGGERBASE and rr ~= nil and isTaggerBase(rr.Instance)
			return p, onB
		end

		-- 촘촘히 샘플 → 일직선 구간은 병합해서 판 수 최소화
		-- [중요] 태거베이스 스킵을 스텝(24) 단위로 하면 경계(거리 44)와 어긋나 계단 윗부분이 빔.
		--        여기선 서브샘플(3 stud) 단위로 판정해 계단을 끝까지 덮음.
		local pts, onBase = {}, {}
		for k = 0, PATH_SUBDIV do
			local p, onB = gAt(sub * k)
			pts[#pts + 1] = p
			onBase[#onBase + 1] = onB
		end

		local startI = 1
		for pi = 2, #pts do
			local merge = false
			if pi < #pts then
				-- 태거베이스 경계를 넘어 병합하면 스킵 판정이 뭉개짐 → 같은 구역일 때만 병합
				local sameZone = (onBase[pi] == onBase[startI]) and (onBase[pi + 1] == onBase[pi])
				if sameZone then
					local d1, d2 = pts[pi] - pts[startI], pts[pi + 1] - pts[pi]
					if d1.Magnitude > 0.01 and d2.Magnitude > 0.01 then
						merge = (d1.Unit:Dot(d2.Unit) >= PATH_MERGE_COS)
					end
				end
			end
			if not merge then
				local prevP, curP = pts[startI], pts[pi]
				local seg = curP - prevP
				-- 양 끝이 모두 태거베이스면 생략. 경계를 걸친 판은 만들어서 틈이 안 생기게 함.
				local skipSlab = (onBase[startI] and onBase[pi])
				if seg.Magnitude > 0.05 and not skipSlab then
				local f = seg.Unit                                -- Y 포함 → 경사/낙차 반영
				local rv = f:Cross(Vector3.new(0, 1, 0))
				rv = (rv.Magnitude > 0.01) and rv.Unit or Vector3.new(1, 0, 0)
				local up = rv:Cross(f).Unit
				local path = Instance.new("Part")
				path.Name = "IcePath"
				path.Size = Vector3.new(PATH_WIDTH, PATH_THICK, seg.Magnitude * 1.08)   -- 살짝 겹쳐 각도차 틈 메움
				path.CFrame = CFrame.fromMatrix((prevP + curP) / 2 + up * PATH_LIFT, rv, up, -f)
				path.Anchored = true
				path.CanCollide = false      -- 외형만 — 실제 빙판 판정 없음
				path.CanQuery = false
				path.CanTouch = false
				path.CastShadow = false
				path.Material = Enum.Material.Ice
				path.Color = Color3.fromRGB(175, 221, 255)
				path.Transparency = PATH_TRANSP
				-- 🤖 [2026-09-15] 농민봇 위험지대 등록.
				--   [증상] 봇이 즉사 지대를 그대로 걸어 들어갔다(실측 제보).
				--   [원인] RunnerBotDriveController 의 지대 목록이 '이름'이라 FrostIce_* 가 빠져 있었고,
				--     얼음은 Anchored(속도 0)라 위협 회피(minSpeed 8)에서도 걸러졌다. 두 경로 모두 누락.
				--   [왜 기둥이 아니라 이 슬래브인가]
				--     · 폭 58 이 레인 ±16 + 기둥 반경을 그대로 덮는다 → 판정=시각 원칙 유지
				--     · 이미 병합돼 30~60장. 기둥(~100개)을 등록하는 것보다 순회가 싸다
				--     · 외형 전용이라 데미지 판정과 섞이지 않는다
				-- ⚠️ lane 규약 = 로컬 X 가 폭, 로컬 Z 가 길이. 위 Size/CFrame 이 이미 그 형태다.
				--   Size 축이나 fromMatrix 인자 순서를 바꾸면 이 등록도 같이 깨진다.
				path:SetAttribute("BotDangerZone", "lane")
					path.Parent = iceFolder
				end
				startI = pi
			end
		end
	end

	-- 드래곤 활공: 중앙 레인 기준
	if frostDragon.PrimaryPart then
		local flyPos = centerPos + Vector3.new(0, GLIDE_HEIGHT, 0)
		pcall(function() frostDragon:PivotTo(CFrame.lookAt(flyPos, flyPos + dir)) end)
	end

	-- 빔 갱신 (PivotTo 이후에 해야 함)
	updateBeam(centerPos)

	-- 이 구간 솟는 순간 타격 — 레인 전 폭 커버 (XZ 평면 판정)
	-- 얼음을 안 만든 구간은 판정도 없음 (시각 = 히트박스 일치)
	--
	-- ⚠️ [수정 2026-08-26] `c.hum.Health = 0` 직접 대입 → processHit 파이프라인으로.
	--   [문제] HP 를 직접 0 으로 만들어 내구도·다운 시스템을 통째로 건너뛰었다.
	--     즉 프로스트 드래곤만 유일하게 '한 방 즉사' 였다.
	--     프리미엄 아이템이 다운을 건너뛰면 내구도(1칸)도 부활도 무의미해지고,
	--     사실상 돈으로 사는 즉사기가 된다.
	--   [해결] 다른 태거 아이템과 같은 경로를 탄다. 내구도가 있으면 흡수되고,
	--     없으면 다운(10초) → 부활 기회. 규칙이 아이템마다 다르면 안 된다.
	-- ⚠️ hitter 파트가 필요하다(processHit 이 원인 표기에 쓴다). 얼음 기둥 대신
	--   임시 파트를 만들어 넘긴다 — 로그에 "FrostDragonIce" 로 남는다.
	for _, c in ipairs(makeIce and collectTargets() or {}) do
		for k = -laneHalf, laneHalf do
			local lp = centerH + rightV * (k * LANE_OFFSET)
			local flat = Vector3.new(c.hrp.Position.X - lp.X, 0, c.hrp.Position.Z - lp.Z)
			-- ⚠️ 태거 베이스 안이면 면역
			if flat.Magnitude <= KILL_RADIUS and not isInTaggerBase(c.char) then
				-- 🛡️ [2026-08-30] 우든 실드로 막지 않는다 — 의도된 제외다.
				--   [왜] 방패는 지면에 세우는 '한 방향 엄폐물'이다. 그런데 프드는
				--     드래곤이 상공에서 돌진하며 넓은 폭으로 얼음을 까는 공격이라,
				--     나무판 하나가 가려준다는 그림이 성립하지 않는다.
				--   [일관성] 이미 같은 기준으로 제외한 것들이 있다 —
				--     잔불 지대·얼음 잔류지대·폭격·블랙홀. 전부 "한 방향에서 오는 게 아닌 것".
				--     프드가 그 분류에 들어간다.
				--   [밸런스] 프리미엄 아이템이 방패 하나에 무력화되면 값어치가 사라진다.
				--   ⚠️ 한때 붙였다가 뺐다. 다시 붙이려면 위 세 근거를 먼저 뒤집을 것.
				--     (구현이 어려워서 뺀 게 아니다 — 경로형·엄폐형 둘 다 시도해봤다)
				if _G.processHit then
					local hitter = Instance.new("Part")
					hitter.Name = "FrostDragonIce"
					hitter.Anchored = true
					hitter.CanCollide = false
					hitter.Transparency = 1
					hitter.Position = lp
					hitter.Parent = workspace
					game:GetService("Debris"):AddItem(hitter, 1)

					local before = c.char:GetAttribute("Durability") or 0
					pcall(function() _G.processHit(c.char, hitter) end)
					local after = c.char:GetAttribute("Durability") or 0
					if after < before then
						print(string.format("❄️ [FrostDragon] 내구도로 막힘 → %s (남은 %d)",
							c.char.Name, after))
					else
						print(string.format("❄️ [FrostDragon] 명중 → %s", c.char.Name))
					end
				else
					-- 파이프라인이 없으면(부팅 순서 문제 등) 최소한 다운은 되게
					c.hum.Health = 0
				end
				break
			end
		end
	end
	task.wait(ADVANCE)
end

-- 겨울바람 페이드아웃 (뚝 끊기지 않게)
task.spawn(function()
	local v0 = wind.Volume
	for k = 1, 10 do
		wind.Volume = v0 * (1 - k / 10)
		task.wait(WIND_FADE / 10)
	end
	wind:Stop()
end)

-- ── 브레스 종료: 빔·브레스 파티클 즉시 정리 (얼음 생성이 끝났으니) ──
if beamModel then
	for _, d in ipairs(beamModel:GetDescendants()) do
		if d:IsA("Beam") then
			d.Enabled = false
		elseif d:IsA("ParticleEmitter") then
			d.Enabled = false
			pcall(function() d:Clear() end)   -- 이미 나온 파티클도 즉시 제거(잔상 방지)
		end
	end
end
-- 입에서 뿜던 브레스도 같이 정지 (Idle* 는 드래곤 페이드까지 유지)
if mouthPart then
	for _, e in ipairs(mouthPart:GetChildren()) do
		if e:IsA("ParticleEmitter") and e.Name:find("Breath") then
			e.Enabled = false
			pcall(function() e:Clear() end)
		end
	end
end

-- ── 활공 끝: 엔딩 애니 재생 → 드래곤 페이드아웃 (얼음은 남음) ──
local ENDING_MAX = 8   -- 엔딩 애니 대기 상한(안전장치). 실제로는 DragonAnimDriver 신호로 끝남
task.spawn(function()
	-- DragonAnimDriver에 엔딩 신호 (구간 루프 해제 → 끝까지 재생)
	frostDragon:SetAttribute("FrostEnding", true)
	-- 애니가 실제로 끝날 때까지 대기 (드라이버가 FrostEndingDone 을 세움)
	local t0 = os.clock()
	while not frostDragon:GetAttribute("FrostEndingDone") and os.clock() - t0 < ENDING_MAX do
		task.wait(0.05)
	end
	print(string.format("[FrostDragon] 엔딩 애니 완료 (%.2fs) → 페이드", os.clock() - t0))

	for _, d in ipairs(frostDragon:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			d.Enabled = false
			pcall(function() d:Clear() end)   -- 페이드 후 파티클 잔상 방지
		end
	end
	-- 원래 투명도 기준으로 페이드 (RootPart·VFX 앵커처럼 원래 안 보이던 파트는 계속 안 보이게)
	local origT = {}
	for _, p in ipairs(frostDragon:GetDescendants()) do
		if p:IsA("BasePart") then origT[p] = p.Transparency end
	end
	for t = 0, 1, 0.1 do
		for p, t0 in pairs(origT) do
			pcall(function() p.Transparency = t0 + (1 - t0) * t end)
		end
		task.wait(0.04)
	end
	-- 엔딩 완료 → 드래곤 즉시 제거 (얼음은 iceFolder에 독립 보관되어 DURATION까지 유지)
	if frostDragon and frostDragon.Parent then
		frostDragon:Destroy()
		print("[FrostDragon] 드래곤 제거 완료 (얼음은 유지)")
	end
end)

-- ── 슬로우 지대 (매 프레임 근접 판정) ──
local active = true
local conn
conn = RunService.Heartbeat:Connect(function(dt)
	if not active then return end
	for _, c in ipairs(collectTargets()) do
		local hum, hrp = c.hum, c.hrp
		local inZone = false
		for _, sp in ipairs(spikePositions) do
			local flat = Vector3.new(hrp.Position.X - sp.X, 0, hrp.Position.Z - sp.Z)
			if flat.Magnitude <= SLOW_RADIUS then inZone = true; break end
		end
		-- ⚠️ 태거 베이스 안이면 지대 면역
		if inZone and isInTaggerBase(hum.Parent) then inZone = false end
		if inZone then
			applySlow(hum)
			-- ⚠️ [수정 2026-08-26] 잔류 지대는 '지속 데미지' 라 즉사기와 성격이 다르다.
			--   그대로 두되, HP 가 0 에 닿는 순간만 processHit 으로 넘긴다.
			--   TakeDamage 로 0 이 되면 다운을 건너뛰고 바로 사망하기 때문이다.
			--   (얼음 기둥 직격과 규칙을 맞춘다 — 러너는 어느 경로로도 다운을 거친다)
			--
			-- ⚠️ [버그 수정 2026-08-26] 다운 처리는 대상당 1회만.
			--   [증상] Health=1 로 멈춰놓고 processHit 을 불렀는데, 다음 프레임에도
			--     `1 - dmg <= 0` 이 참이라 무한 반복됐다. 50ms 마다 로그가 찍히고
			--     매번 Instance.new("Part") 를 만들었다(실측 15:23 판, 10초간 수백 줄).
			--   [원인] 이미 다운된 대상인지 확인하지 않았다.
			--   [해결] 다운 상태면 지대 판정 자체를 건너뛴다. 누워 있는 러너를
			--     지대가 계속 때릴 이유도 없다(다운 타이머가 이미 돌고 있다).
			local downedNow = hum.Parent and hum.Parent:GetAttribute("Downed")
			-- ☠️ [2026-08-28] 처형 연출 중인 대상은 지대 판정에서 통째로 제외한다.
			--   [증상] 코핀이 중간에 멎고 관이 맵에 영구히 남았다.
			--     (실측 09:58 판 — 미완료 7건 전부 얼음 활성 구간, 성공 3건은 얼음 없음)
			--   [원인] 아래 650행이 processHit 보다 '먼저' hum.Health = 1 을 쓴다.
			--     processHit 은 frozenCharacters 로 막지만 체력은 이미 바뀐 뒤다.
			--     ItemDamageSystem 의 HealthChanged 훅이 처형 중엔 Health 를
			--     MaxHealth 로 되돌리므로, 체력이 매 프레임 흔들리며
			--     코핀 시퀀스·19초 안전망이 함께 사라졌다.
			--   ⚠️ Downed 로는 못 잡는다. killDowned 가 다운을 해제하고 처형으로
			--     넘기므로, 코핀 중인 캐릭터는 Downed 가 아니다.
			--   ⚠️ 판정은 _G.IsInKillSequence 를 쓴다. 속성(CoffinSequence 등)을
			--     직접 검사하지 말 것 — 처형 이펙트가 늘 때마다 갈라진다.
			local inKillSeq = _G.IsInKillSequence and _G.IsInKillSequence(hum.Parent)
			if downedNow or zoneDowned[hum] or inKillSeq then
				-- 이미 다운/처형 중: 감속만 유지하고 데미지·판정은 건너뛴다
			else
				local dmg = (hum.MaxHealth / ZONE_TTK) * dt
				if hum.Health - dmg <= 0 then
					hum.Health = 1   -- 0 직전에서 멈추고
					if _G.processHit then
						zoneDowned[hum] = true
						local hitter = Instance.new("Part")
						hitter.Name = "FrostDragonZone"
						hitter.Anchored = true
						hitter.CanCollide = false
						hitter.Transparency = 1
						hitter.Position = hrp.Position
						hitter.Parent = workspace
						game:GetService("Debris"):AddItem(hitter, 1)
						pcall(function() _G.processHit(hum.Parent, hitter) end)
						print(string.format("❄️ [FrostDragon/잔류지대] 다운 → %s", hum.Parent.Name))
					else
						hum.Health = 0
					end
				else
					hum:TakeDamage(dmg)
				end
			end
		elseif slowed[hum] then
			if hum.Parent then hum.WalkSpeed = slowed[hum] end
			slowed[hum] = nil
		end
	end
end)

-- ── DURATION 후 정리 + 쿨타임 해제 ──
-- ── 얼음 파쇄 연출 ──
-- 진짜 물리 파편은 금지(99개 × 파편 = 모바일 사망). 파티클 버스트 + 빠른 페이드로 위장.
-- 천천히 줄면 '녹는' 느낌이 나므로 페이드는 짧게 → 파편은 파티클이 담당.
local SHATTER_TIME = 0.18   -- 기둥 하나가 사라지는 시간
local SHATTER_STEP = 0.03   -- 웨이브 진행 간격(태거 → 러너)
local SHARD_TEX    = "rbxassetid://85698671947685"

-- Model(기둥) / Part(빙판) 둘 다 받음
local function shatterOne(m)
	local isPath = m:IsA("BasePart")
	local pp = isPath and m or (m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true))
	if not pp then m:Destroy(); return end

	-- 파편 파티클 (기둥이 사라져도 남도록 별도 파트에서 방출)
	local fx = Instance.new("Part")
	fx.Anchored = true; fx.CanCollide = false; fx.CanQuery = false; fx.CanTouch = false
	fx.Transparency = 1; fx.Size = Vector3.new(1, 1, 1); fx.CFrame = CFrame.new(pp.Position)
	fx.Parent = iceFolder
	local e = Instance.new("ParticleEmitter")
	e.Texture = SHARD_TEX
	e.Color = ColorSequence.new(Color3.fromRGB(175, 225, 255))
	e.LightEmission = 0.6
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3.5), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.4, 0.8)
	e.Speed = NumberRange.new(12, 28)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, -60, 0)   -- 파편이 흩어졌다 떨어짐
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-220, 220)
	e.Rate = 0
	e.Enabled = false
	e.Parent = fx
	if isPath then e:Emit(3) else e:Emit(10) end   -- 빙판은 평평해서 버스트 최소

	-- 빠른 페이드
	local parts = {}
	if isPath then
		parts[1] = { m, m.Transparency }
	else
		for _, p in ipairs(m:GetDescendants()) do
			if p:IsA("BasePart") then parts[#parts + 1] = { p, p.Transparency } end
		end
	end
	local t0 = os.clock()
	while true do
		local a = (os.clock() - t0) / SHATTER_TIME
		if a >= 1 then break end
		for _, ent in ipairs(parts) do
			local p, t = ent[1], ent[2]
			if p.Parent then p.Transparency = t + (1 - t) * a end
		end
		task.wait()
	end
	m:Destroy()
end

local function shatterIce()
	local spikes = {}
	for _, m in ipairs(iceFolder:GetChildren()) do
		-- 기둥(Model) + 빙판(IcePath) 둘 다 같은 웨이브로 사라져야 함
		if m:IsA("Model") or (m:IsA("BasePart") and m.Name == "IcePath") then
			spikes[#spikes + 1] = m
		end
	end
	-- 태거 쪽 → 러너 쪽 정렬: 생성 방향과 같은 웨이브 = 자연스럽고 부하도 분산됨
	table.sort(spikes, function(a, b)
		local pa = a:IsA("BasePart") and a.Position or ((a.PrimaryPart and a.PrimaryPart.Position) or a:GetPivot().Position)
		local pb = b:IsA("BasePart") and b.Position or ((b.PrimaryPart and b.PrimaryPart.Position) or b:GetPivot().Position)
		return (pa - startPos):Dot(dir) < (pb - startPos):Dot(dir)
	end)

	for idx, m in ipairs(spikes) do
		task.spawn(function() shatterOne(m) end)
		-- 파쇄음도 듬성듬성
		if (idx % (LANES * 6)) == 0 then
			local pp = m:IsA("BasePart") and m or (m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true))
			if pp then
				local cs = Instance.new("Sound")
				cs.SoundId = SND_ICE
				cs.Volume = 0.55
				cs.PlaybackSpeed = 1.25          -- 살짝 높여 '깨짐'에 가깝게
				cs.RollOffMode = Enum.RollOffMode.InverseTapered
				cs.RollOffMinDistance = 30
				cs.RollOffMaxDistance = 250
				cs.Parent = iceFolder
				cs:Play()
			end
		end
		if (idx % (LANES + 1)) == 0 then task.wait(SHATTER_STEP) end   -- 스텝당 기둥3 + 빙판1
	end
	return #spikes
end

-- ── DURATION 후: 파쇄 → 정리 + 쿨타임 해제 ──
task.delay(DURATION, function()
	-- 파쇄가 시작되면 더 이상 위험하지 않음 → 판정부터 해제 (시각과 판정 일치)
	active = false
	if conn then conn:Disconnect() end
	for hum, ws in pairs(slowed) do if hum and hum.Parent then hum.WalkSpeed = ws end end
	slowed = {}

	local n = shatterIce()
	task.wait(0.9)   -- 파편 파티클 여운

	-- [순서 주의] iceFolder 안에 이 스크립트가 있으므로 iceFolder:Destroy() 는 반드시 마지막.
	-- 먼저 지우면 아래 쿨타임 해제가 실행되지 않아 아이템이 영구 잠김.
	if ownerId and _G.FrostCooldown then _G.FrostCooldown[ownerId] = nil end
	-- 🔓 [2026-08-27] UI 잠금 해제. 세우는 쪽은 ItemSpawnHandler(_G.FrostCooldown 세팅부).
	--   ⚠️ 이 줄이 iceFolder:Destroy() 보다 뒤로 가면 실행되지 않아 영구 잠김이 된다.
	do
		local plr = ownerId and game:GetService("Players"):GetPlayerByUserId(ownerId)
		if plr and _G.SetItemLock then _G.SetItemLock(plr, "Frost Dragon", false) end
	end
	if frostDragon and frostDragon.Parent then frostDragon:Destroy() end
	print("[FrostDragon] 얼음 파쇄 완료 (" .. tostring(n) .. "기둥) + 쿨타임 해제")
	if iceFolder and iceFolder.Parent then iceFolder:Destroy() end
end)

print("[FrostDragon] 브레스 강하 (" .. spikeCount .. "기둥, 지속 " .. DURATION .. "초)")
