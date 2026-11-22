-- DemonSpearSystem (업그레이드 투창 'Demonspear')
-- 클릭 지점으로 데몬 스피어 투척. 비행 중 경로 바닥에 ds_roadeffect 잔불이 번지고,
-- 착탄 지점에는 hill 경사에 맞춘 가운데가 빈 빨간 링(즉사 범위)을 표시.
-- 창 도착 순간, 그 범위 안의 모든 휴머노이드를 1회 스냅샷으로 즉사(다운) — Mic Bomb 식. 킬은 _G.processHit 사용.

local Players       = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris        = game:GetService("Debris")
local RunService    = game:GetService("RunService")

local taggerItems    = ServerStorage:WaitForChild("TaggerItem")
local SPEAR_TEMPLATE = taggerItems:WaitForChild("Demonspear")
local ROAD_TEMPLATE  = ServerStorage:WaitForChild("ds_roadeffect")  -- 경로 잔불 이펙트(모델)

-- ─── 색조 틴트 헬퍼: 불꽃 VFX를 스킨 색에 맞춤 (원본 채도·명도 유지 + 타겟 hue) ───
-- 흰 불티(S=0)·검은 연기(V=0)는 원본 채도/명도가 보존되어 자동 유지. 타겟이 무채색이면 회색조.
local function tintHue(orig, target)
	local th, ts = target:ToHSV()
	local _, os, ov = orig:ToHSV()
	if ts < 0.05 then return Color3.fromHSV(0, 0, ov) end
	return Color3.fromHSV(th, os, ov)
end
local function tintParticleSeq(cs, target)
	local kps = {}
	for _, kp in ipairs(cs.Keypoints) do
		kps[#kps + 1] = ColorSequenceKeypoint.new(kp.Time, tintHue(kp.Value, target))
	end
	return ColorSequence.new(kps)
end

-- ─── 설정 ───────────────────────────────────────
local DEMON_RANGE    = 1200    -- 최대 사거리
-- ⚠️ [밸런스 2026-08-26] 220 → 130.
--   [문제] 스피어(105)의 2.1배라 반응 창이 절반 이하였다.
--     거리 400 기준 비행 1.82초 vs 스피어 3.81초.
--     상위 아이템이라도 "보고도 못 피하는" 수준은 회피라는 선택지를 없앤다.
--   [지금] 스피어보다 24% 빠르다. 거리 400 기준 3.08초 vs 3.81초.
--     상위템다운 우위는 유지하되 반응은 가능한 구간.
--   ⚠️ [갱신 2026-09-01] 예전 이 자리엔 "착탄 링(0.8초)이 별도로 있어 대응 창은 더 길다"고
--     적혀 있었는데, 두 가지가 틀렸다. ① 링은 착탄 후가 아니라 '던지는 순간' 뜬다.
--     ② 비행 시간이 clamp 상한 0.8초에 막혀 있어 위의 "거리 400 기준 3.08초"가
--     실제로는 나온 적이 없었다(104 stud 초과는 전부 0.8초 고정).
--     지금은 상한을 2.5 로 풀고 BLAST_WARNING 을 0 으로 내려, 대응 창이 온전히
--     '비행 시간 = 링이 떠 있는 시간'이 되도록 일원화했다. travelTime 주석 참조.
-- ⚔️ [밸런스 2026-09-01] 130 → 190.
--   [왜] 위에서 clamp 상한을 풀자 원거리 비행이 실제로 길어졌는데, 그게 과했다.
--     거리 300 기준 비행 2.31초 — 그 사이 러너가 16×2.31 = 37 stud 이동한다.
--     즉사 반경이 22 라, 직선으로만 달려도 착탄점을 벗어난다. 원거리에서는
--     '피할 수 있다'가 아니라 '구조적으로 안 맞는다'가 되어 무기가 죽었다.
--   [190 근거] 스피어(105) 대비 1.81배. 2026-08-26 에 "불공평"으로 판정된 2.1배 아래다.
--     거리 200 → 1.05초(러너 이동 17 < 반경 22, 명중 성립)
--     거리 300 → 1.58초(이동 25, 직선 주행이면 스침)
--     거리 475 이상 → clamp 2.5초
--   ⚠️ 여기서 더 올리지 말 것. 2.1배를 넘으면 2026-08-26 에 되돌린 상태로 회귀한다.
--     원거리 명중률이 여전히 부족하면 탄속이 아니라 '예측 조준'을 넣어야 한다 —
--     지금 봇은 표적의 '현재 위치'를 겨눈다. 비행 시간만큼 앞을 겨누면
--     탄속을 안 올리고도 맞는다(TaggerBotSystem.throwAt 쪽 과제).
--   ⚠️ 발사 잠금(travelTime + TRAIL_DURATION 3.0 + 0.3)은 상한이 그대로라 최대 5.8초.
local DEMON_SPEED    = 190     -- 비행 시각 속도(stud/s). 스피어 105 대비 +81%
local DEMON_SCALE    = 3.2     -- 원본 형태 유지한 채 균일 확대 배율 (그림자 Beam·어태치먼트 포함 보존)
local AIM_PITCH_DEG  = -90     -- A메시(4674913493) 헤드=+Y. Y를 진행방향 정렬(촉 앞). 촉 반대로 날면 90.
local EMBED_DEPTH    = 1.8     -- 직격 시 파고드는 깊이
local EMBED_PITCH    = -55     -- 박힌 창 각도(도). 0=수평, 음수클수록 촉이 아래로+창대 하늘로. -55=창대 꽤 세워짐
local EMBED_LIFT     = 0       -- 지면 위로 띄우는 높이(stud). 0=embedDir 기준 창끝이 착탄점에 닿음(뜨면 음수로)
-- ⚠️ [밸런스 2026-08-25] 착탄 경고. 예전엔 링이 즉사와 동시에 떠
--    사실상 예고가 없었다(총 선딜 0.9초). EnergyBall 은 경고 1.5초를
--    주는데 이쪽은 반경이 2배라 더 불공평했다.
--    → 링을 먼저 띄우고 이 시간 뒤에 범위 즉사가 발동한다.
--    ⚠️ 직격(창에 직접 맞음)은 즉시 유지 — 그건 명중이라 예고가 불필요하다.
-- ⚔️ [밸런스 2026-09-01] 0.8 → 0. 예고를 '착탄 후 대기'에서 '비행 시간'으로 옮겼다.
--   [왜] 링(zone)은 이미 던지는 순간 생성된다(아래 zone.Parent 참조). 즉 예고는
--     비행 내내 떠 있고, BLAST_WARNING 은 그 위에 얹힌 '착탄 후 추가 대기'였다.
--     그런데 비행 시간이 clamp 상한 0.8초에 막혀 있어(아래 travelTime 참조)
--     실전 거리에서는 예고의 대부분을 이 상수가 떠맡는 구조였다.
--   [지금] clamp 상한을 2.5 로 풀어 비행이 실제로 길어졌다. 링은 그 내내 보인다.
--     → "떠 있는 원을 보고 그 전에 빠져나간다"가 성립하므로 착탄 후 대기는 군더더기다.
--   ⚠️ 되돌리려면 이 값과 travelTime 상한을 반드시 함께 볼 것. 한쪽만 되돌리면
--     예고가 통째로 사라지거나(0.8 유지 + clamp 복구는 안전) 과해진다.
local BLAST_WARNING  = 0       -- 착탄 링 표시 후 폭발까지 (0 = 착탄 즉시)

-- 🛡️ 태거 베이스 안의 러너는 태거 아이템에 당하지 않는다.
-- ⚠️ [2026-08-28] 판정을 _G.IsCharInTaggerBase 로 일원화했다. 여기서 복사하지 말 것.
--   원본은 ItemSpawnHandler 에 있다(높이 밴드·캐시 무효화·showBaseImmune 포함).
--   [원래 이유] 태거가 베이스에서 언덕 쪽으로 던지면 잔불 경로가 베이스까지 펼쳐져,
--     2단계에 올라온 러너가 '베이스 안에서' 태거 아이템에 죽었다.
local function isInTaggerBase(model)
	return _G.IsCharInTaggerBase(model)
end
local KILL_RADIUS    = 22      -- 착탄 즉사 범위 반경(stud) = 빨간 링 반경
local RING_SEGMENTS  = 44      -- 범위 링 분절 개수(많을수록 매끈)
local RING_THICKNESS = 1.6     -- 링 테두리 폭(stud)
local ROAD_SCALE     = 0.55    -- 경로 잔불(ds_roadeffect) 크기 배율
local ROAD_LIGHT_DIM = 0.5     -- 경로 잔불 PointLight 밝기 배율
-- ⚠️ [밸런스 2026-08-25] 6 → 3. 잔불이 위협 면적의 절반 이상이었다.
local TRAIL_DURATION = 3       -- 경로 잔불 지속(초)
-- ⚠️ [밸런스 2026-08-25] 8 → 4. 지점당 반경 9 라 8개면 2036 면적이었다.
local FIRE_POINTS    = 4       -- 경로 잔불 개수 상한 (잔불 1개가 크므로 적게)
local FIRE_SPACING   = 16      -- 경로 잔불 간격(stud)
local FIRE_TRAIL_OFFSET = 32   -- 경로 잔불을 진행방향 반대로 민 거리(stud) — 착탄 창과 겹침 방지(잔불이 커서 크게)
local EMBER_RADIUS   = 9       -- 잔불 1개의 지속 데미지 반경(stud) — 보이는 불 크기에 맞춤 (사이 빈 공간은 데미지 X)
local EMBER_SWEEP    = 0.4     -- 잔불 지속 데미지 판정 주기(초)
-- 🔥 [2026-08-26] 잔불 tick 당 데미지. TNT 잔불(BURN_DAMAGE_PER_TICK 8 / 0.5초)과 같은 계열.
-- ⚠️ 값이 6인 이유: 주기가 0.4초로 TNT(0.5초)보다 촘촘해 초당 딜을 맞춘다.
--     TNT   8 ÷ 0.5 = 초당 16
--     데몬  6 ÷ 0.4 = 초당 15
--   다만 지속이 다르다 — TNT 잔불 10초(총 160) vs 데몬 3초(총 45).
--   데몬스피어는 '지나가는 길에 깔리는 불' 이고 TNT 는 '폭심지가 계속 탄다' 이므로
--   총량 차이는 의도된 것이다.
-- ⚠️ 100HP 기준 3초를 다 맞으면 45 — 절반이 안 된다. 잔불만으로는 안 죽고,
--   착탄 즉사(KILL_RADIUS 22)를 피한 러너에게 붙는 추가 압박 역할이다.
local EMBER_DAMAGE_PER_TICK = 6

local TIP_LOCAL = Vector3.new(-2.2415, 2.4415, 0)         -- point1(창끝) 템플릿 로컬 — 이 메시는 대각선으로 놓임
local ROLL_TO_Y = math.atan2(TIP_LOCAL.X, TIP_LOCAL.Y)   -- 대각 창축을 +Y로 정렬하는 Z회전
local FLAT_ROLL = 0      -- 롤 보정 (되돌림). 필요시 90/-90/180
local AIM_ROT = CFrame.Angles(math.rad(AIM_PITCH_DEG), 0, 0) * CFrame.Angles(0, math.rad(FLAT_ROLL), 0) * CFrame.Angles(0, 0, ROLL_TO_Y)
local activeUntil = {}  -- 플레이어별 DS 잠금 만료 시각(os.clock). FX 수명에 의존하지 않는 결정론적 잠금.

local function getOrigin(character)
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if hand then return hand.Position end
	local root = character:FindFirstChild("HumanoidRootPart")
	return root and root.Position or nil
end

-- 착탄한 창이 향할 "베이스(러너 스폰) 방향" — 착탄점에서 가장 가까운 맵의 playerspawn 중심 쪽(수평)
local function getBaseDir(fromPos)
	local nearest, bestD
	for _, mapName in ipairs({"map1", "map2"}) do
		local map = workspace:FindFirstChild(mapName)
		if map then
			for _, d in ipairs(map:GetChildren()) do
				if d:IsA("BasePart") and string.find(string.lower(d.Name), "playerspawn") then
					local dd = (d.Position - fromPos).Magnitude
					if not bestD or dd < bestD then bestD = dd; nearest = d end
				end
			end
		end
	end
	if not nearest then return nil end
	local map = nearest.Parent
	local sum, cnt = Vector3.new(), 0
	for _, d in ipairs(map:GetChildren()) do
		if d:IsA("BasePart") and string.find(string.lower(d.Name), "playerspawn") then
			sum = sum + d.Position; cnt = cnt + 1
		end
	end
	local center = sum / cnt
	local dir = Vector3.new(center.X - fromPos.X, 0, center.Z - fromPos.Z)
	return (dir.Magnitude > 0.01) and dir.Unit or nil
end

-- 🛢️ [버그수정 2026-09-02] 지면 레이에서 '바닥에 놓인 임시 물체'를 제외한다.
--   [증상] 착탄 판정원이 바닥에 눕지 않고 종종 이상한 각도로 기울었다.
--   [원인] 아래 groundHit 이 res.Normal 을 그대로 원 정렬에 쓰는데, 배럴 웅덩이·
--     굴러다니는 태거 아이템·블랙홀이 경로에 있으면 그 '윗면 법선'이 잡힌다.
--     웅덩이가 경사에 깔려 있으면 원도 같이 기운다.
--   [규약] EnergyBallSystem.makeRayParams 와 같은 기준이다. 앞으로 새 물체는
--     생성할 때 GroundRayIgnore 속성만 켜면 여기도 자동으로 커버된다.
--   ⚠️ 캐시하지 않는다. 벽(getWallParts)은 정적이라 캐시하지만 이것들은 매번
--     생겼다 사라진다 — 캐시하면 이미 지워진 인스턴스를 계속 붙들게 된다.
local function transientParts()
	local list = {}
	for _, d in ipairs(workspace:GetChildren()) do
		if d:GetAttribute("TaggerSpawnedItem")
		   or d:GetAttribute("GroundRayIgnore")
		   or d.Name:sub(1, 9) == "FrostIce_"
		   or d.Name == "_BarrelSpill" then
			list[#list + 1] = d
		end
	end
	local pickups = workspace:FindFirstChild("PickupContainer")
	if pickups then list[#list + 1] = pickups end
	return list
end

local function groundAt(pos, ignore)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local list = {}
	for _, v in ipairs(ignore or {}) do list[#list + 1] = v end
	for _, v in ipairs(transientParts()) do list[#list + 1] = v end
	rp.FilterDescendantsInstances = list
	local res = workspace:Raycast(pos + Vector3.new(0, 60, 0), Vector3.new(0, -400, 0), rp)
	return res and res.Position or pos
end

-- 지면 위치 + 노멀(경사) 반환
-- ⚠️ [2026-08-25] 지면 판정에서 바리케이드·성문을 제외한다.
--    예전엔 잔불이 성벽 '위'에 얹혀, 벽을 타고 넘어가는 것처럼 보였다.
--    잔불은 바닥에 깔려야 하므로 벽은 통과시키고 그 아래 지면을 찾는다.
local _wallCache = nil
local function getWallParts()
	if _wallCache then return _wallCache end
	_wallCache = {}
	for _, mf in ipairs(workspace:GetChildren()) do
		if mf.Name == "map1" or mf.Name == "map2" then
			local bf = mf:FindFirstChild("Barricades")
			if bf then _wallCache[#_wallCache + 1] = bf end
			-- 판정 파트의 BarricadeGate 속성이 가리키는 구조물도 제외
			if bf then
				for _, seg in ipairs(bf:GetChildren()) do
					local g = seg:GetAttribute("BarricadeGate")
					if g then
						for _, nm in ipairs(string.split(g, ",")) do
							nm = nm:gsub("^%s+", ""):gsub("%s+$", "")
							for _, d in ipairs(mf:GetDescendants()) do
								if d.Name == nm then _wallCache[#_wallCache + 1] = d end
							end
						end
					end
				end
			end
		end
	end
	return _wallCache
end

local function groundHit(pos, ignore)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local list = {}
	for _, v in ipairs(ignore or {}) do list[#list + 1] = v end
	for _, v in ipairs(getWallParts()) do list[#list + 1] = v end
	for _, v in ipairs(transientParts()) do list[#list + 1] = v end   -- 🛢️ 웅덩이·아이템 제외 (위 주석 참조)
	rp.FilterDescendantsInstances = list
	local res = workspace:Raycast(pos + Vector3.new(0, 60, 0), Vector3.new(0, -400, 0), rp)
	if not res then return pos, Vector3.new(0, 1, 0) end
	-- 🔴 [버그수정 2026-09-02] 법선이 '바닥'이 아니면 위쪽으로 대체한다.
	--   [증상] 착탄 판정원이 가끔 하늘을 향해 수직으로 섰다(제외 목록 추가 후에도 재발).
	--   [원인] 레이가 배럴·픽업상자의 '옆면'을 때리면 법선이 거의 수평(Y≈0)으로 나온다.
	--     그 값이 아래 텔레그래프 정렬로 넘어가는데, 거기서 접선축을 nrm × (0,0,1) 로
	--     만든다. 법선이 Z축과 나란하면 외적이 0 이 되어 폴백 축 (1,0,0) 으로 넘어가고,
	--     그 조합이 원을 수직으로 세운다.
	--   [왜 제외 목록으로 못 막았나] 목록을 늘리는 방식은 '무엇을 맞았나'에 의존한다.
	--     오늘만 세 번 깨졌다(벽 → 아이템 → 웅덩이). 여기서는 '무엇을 맞았든 결과가
	--     바닥이어야 한다'로 뒤집는다 — 새 물체가 추가돼도 안전하다.
	--   ⚠️ 0.4 는 약 66도. 이보다 가파른 면은 지면으로 치지 않는다. hill 경사와 계단
	--     윗면은 이보다 완만하므로 정상 지형은 그대로 통과한다. 계단 '옆면'은 걸러진다.
	--   ⚠️ 이 가드가 있으면 위 접선축의 폴백 분기는 도달 불가능해진다(법선이 Z축과
	--     나란해질 수 없으므로). 폴백은 안전망으로 남겨둔다.
	local n = res.Normal
	if n.Y < 0.4 then n = Vector3.new(0, 1, 0) end
	return res.Position, n
end

local function collectCharacters(exclude)
	local list = {}
	for _, m in ipairs(workspace:GetChildren()) do
		if m ~= exclude and m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") then
			table.insert(list, m)
		end
	end
	return list
end

local function throwDemonSpear(player, clickPosition)
	if not player or typeof(clickPosition) ~= "Vector3" then return false end
	local character = player.Character
	if not character then return false end
	local lockUntil = activeUntil[player]
	if lockUntil and os.clock() < lockUntil then
		-- 현재 DS가 아직 살아있음 → 재발사 금지
		print(("🚫 DemonSpear 잠금: %.1f초 후 재발사 가능"):format(lockUntil - os.clock()))
		return false
	end

	local startPos = getOrigin(character)
	if not startPos then return false end

	local toTarget = clickPosition - startPos
	if toTarget.Magnitude < 1 then return false end
	local rayLen = math.min(toTarget.Magnitude, DEMON_RANGE)
	local direction = toTarget.Unit
	local targetPos = startPos + direction * rayLen

	-- 공중 직격 판정: 휴머노이드만 대상(지형 무시) → 클릭 지점까지 비행, 경로상 러너 명중
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = collectCharacters(character)
	local result = workspace:Raycast(startPos, direction * rayLen, rp)
	local hitPos, hitPart
	if result then hitPos, hitPart = result.Position, result.Instance else hitPos = targetPos end

	-- 발사체
	local spear = SPEAR_TEMPLATE:Clone()
	spear.Name = "ThrownDemonSpear"
	spear.Anchored = true
	spear.CanCollide = false
	spear.CanQuery = false
	spear.CanTouch = false
	spear.Massless = true
	-- 🤖 농민봇 위협 인지용 태그 (SpearSystem 과 동일 사유: Anchored+CFrame 이라 물리속도 0)
	spear:SetAttribute("BotThreat", true)
	-- 원본 형태 유지 균일 확대: Size + 어태치먼트 위치 + Beam 폭을 같은 배율로 → 창끝 감싸는 검은 그림자(Beam) 보존
	spear.Size = spear.Size * DEMON_SCALE
	for _, d in ipairs(spear:GetDescendants()) do
		if d:IsA("Attachment") then
			d.Position = d.Position * DEMON_SCALE
		elseif d:IsA("Beam") then
			d.Width0 = d.Width0 * DEMON_SCALE
			d.Width1 = d.Width1 * DEMON_SCALE
		end
	end

	-- 🎨 스킨 색 적용: Rainbow(장착) 우선 → ITEM COLOR(DemonColor_Body).
	-- 본체(MeshPart Neon) + Beam ColorSequence(유채색 keypoint만 본체색으로, 검정 keypoint는 유지).
	local vfxTint = nil  -- 경로 잔불 VFX 틴트색 (nil=원본 유지, Rainbow는 발사 시점 색으로 고정)
	do
		local beam = spear:FindFirstChildWhichIsA("Beam")
		local function tintBeam(targetColor)
			if not beam then return end
			local kps = {}
			for _, kp in ipairs(beam.Color.Keypoints) do
				local v = kp.Value
				if math.max(v.R, v.G, v.B) < 0.15 then
					kps[#kps + 1] = ColorSequenceKeypoint.new(kp.Time, v)            -- 검정 계열 유지
				else
					kps[#kps + 1] = ColorSequenceKeypoint.new(kp.Time, targetColor)  -- 유채색 → 본체색
				end
			end
			beam.Color = ColorSequence.new(kps)
		end

		local skin = _G.getEquippedSkin and _G.getEquippedSkin(player, "Demonspear")
		if skin == "RainbowDemonSpear" and player:GetAttribute("Has_RainbowDemonSpear") == true then
			-- SurfaceAppearance/텍스처가 있으면 Neon·Color가 안 뜨므로 레인보우는 벗김
			local _sa = spear:FindFirstChildWhichIsA("SurfaceAppearance")
			if _sa then _sa:Destroy() end
			spear.TextureID = ""
			spear.Material = Enum.Material.Neon
			vfxTint = Color3.fromHSV((os.clock() * 0.13) % 1, 1, 1)  -- 잔불은 발사 순간 색으로 고정(본체/Beam만 순환)
			local hue = 0
			local conn
			conn = RunService.Heartbeat:Connect(function(dt)
				if not spear.Parent then if conn then conn:Disconnect() end return end
				hue = (hue + dt * 0.5) % 1
				local col = Color3.fromHSV(hue, 1, 1)
				spear.Color = col
				tintBeam(col)
			end)
		else
			local colorName = player:GetAttribute("DemonColor_Body")
			if colorName then
				local ok, palette = pcall(function()
					return require(ReplicatedStorage:WaitForChild("NoobColorPalette"))
				end)
				if ok and palette and palette.COLORS[colorName] then
					local cfg = palette.getConfig("Demonspear")
					local finishKey = player:GetAttribute("DemonMaterial_Body") or (cfg and cfg.materialDefault)
					local col = palette.COLORS[colorName]
					palette.applyFinish(spear, finishKey, col)
					tintBeam(col)
					vfxTint = col
				end
			end
		end
	end

	local SPEAR_LEN = math.max(spear.Size.X, spear.Size.Y, spear.Size.Z)   -- 장축 길이 (new demon spear3 장축=Z)
	spear.CFrame = CFrame.lookAt(startPos, hitPos) * AIM_ROT
	spear.Parent = workspace
	Debris:AddItem(spear, TRAIL_DURATION + 1)   -- 불꽃(TRAIL_DURATION 동안 점화)과 같이 소멸

	local bounce = spear:FindFirstChild("Bounce")
	if bounce and bounce:IsA("Sound") then bounce:Play() end

	-- FX 컨테이너
	local fxFolder = Instance.new("Folder")
	fxFolder.Name = "DemonSpearFX_" .. player.Name
	fxFolder.Parent = workspace
	Debris:AddItem(fxFolder, TRAIL_DURATION + 4)

	-- 착탄 중심 + 지면 노멀 (hill 경사 반영)
	local impactCenter, impactNormal = groundHit(hitPos, { character, spear, fxFolder })

	-- 🔴 즉사 범위 텔레그래프 (가운데가 빈 빨간 링) — hill 경사면 평면에 정렬
	local zone = Instance.new("Model")
	zone.Name = "DemonZoneTelegraph"
	do
		local nrm = impactNormal.Unit
		local t1 = nrm:Cross(Vector3.new(0, 0, 1))
		if t1.Magnitude < 0.05 then t1 = nrm:Cross(Vector3.new(1, 0, 0)) end
		t1 = t1.Unit
		local t2 = nrm:Cross(t1).Unit              -- 평면의 두 번째 접선축
		local center = impactCenter + nrm * 0.2
		local segAng = (2 * math.pi) / RING_SEGMENTS
		local chord = 2 * KILL_RADIUS * math.sin(segAng / 2)  -- 인접 분절 간 현 길이
		for i = 0, RING_SEGMENTS - 1 do
			local a0, a1 = i * segAng, (i + 1) * segAng
			local p0 = center + (t1 * math.cos(a0) + t2 * math.sin(a0)) * KILL_RADIUS
			local p1 = center + (t1 * math.cos(a1) + t2 * math.sin(a1)) * KILL_RADIUS
			local along = p1 - p0
			if along.Magnitude > 0.001 then
				along = along.Unit
				local seg = Instance.new("Part")
				seg.Anchored = true; seg.CanCollide = false; seg.CanQuery = false; seg.CanTouch = false
				seg.Material = Enum.Material.Neon
				seg.Color = vfxTint and tintHue(Color3.fromRGB(255, 40, 40), vfxTint) or Color3.fromRGB(255, 40, 40)
				seg.Transparency = 0.25
				seg.Size = Vector3.new(chord + 0.3, 0.3, RING_THICKNESS)  -- X=현 길이, Y=두께(노멀), Z=테두리 폭
				seg.CFrame = CFrame.fromMatrix((p0 + p1) * 0.5, along, nrm)  -- X=현 방향, Y=지면 노멀
				seg.Parent = zone
			end
		end
	end
	zone.Parent = fxFolder

	-- ⚔️ [이력] 비행 시간 상한: 0.8 → 2.5 (2026-09-01) → 1.8 (2026-09-02).
	--   [0.8 이 문제였던 이유] 2026-08-26 에 DEMON_SPEED 를 220 → 130 으로 내렸는데,
	--     이 clamp 때문에 그 너프가 거의 걸리지 않았다. 104 stud 를 넘는 순간 전부
	--     0.8초 고정이라 거리 300 이면 실효 375, 거리 600 이면 실효 750 이 된다.
	--     결국 예고를 BLAST_WARNING 이 혼자 떠맡았다.
	--   ⚠️ 하한 0.08 은 유지. 근접 착탄에서 비행이 0 이 되면 CFrame 보간이 깨진다.
	--   ⚠️ 아래 상한 값을 바꿀 때 발사 잠금(travelTime + TRAIL_DURATION 3.0 + 0.3)도
	--     같이 움직인다. 상한을 올리면 봇 쿨 8초를 넘어 "쿨은 찼는데 못 쏘는" 구간이 생긴다.
	local travelTime = math.clamp((hitPos - startPos).Magnitude / DEMON_SPEED, 0.08, 1.8)
	-- ⚔️ [밸런스 2026-09-02] 상한 2.5 → 1.8.
	--   [왜] 2.5초는 실전에서 아무도 안 맞는 값이었다. 유저는 걸어서도 피한다 —
	--     맞아주는 건 회피 로직이 없는 AI 봇뿐이라, 이론상 균형이지 실전 균형이 아니었다.
	--   [1.8 인 이유] 상한 시작 거리 342 stud. 거리 600 실효 속도 333 으로,
	--     2026-08-26 에 폐기된 0.8초(거리 600 → 실효 750)와는 거리가 충분하다.
	--     일반 스피어 상한 1.6초보다 약간 길다 — 광역 즉사기라 그만큼 여유를 남긴다.
	--   [왜 1.5 가 아닌가] 일반 창도 내구도 없으면 즉사지만, 데몬스피어는 거기에
	--     범위 판정이 붙는다. 회피 난이도를 일반 창보다 낮게 두지는 않는다.
	--   ⚠️ 발사 잠금(travelTime + TRAIL_DURATION 3.0 + 0.3)도 5.8 → 5.1 초로 줄어든다.
	--     봇 쿨 8초 대비 여유가 늘어나는 방향이라 안전하다.
	--   ⚠️ 더 내리려면 DEMON_SPEED(190) 를 같이 봐야 한다. 상한만 계속 내리면
	--     08-26 에 되돌린 "탄속 너프가 clamp 에 먹혀 무의미해지는" 상태로 회귀한다.

	-- 🔒 발사 잠금(결정론적): 비행 + 잔불 지속이 끝나야 다음 DS 발사 가능. FX 폴더 수명에 의존하지 않음.
	activeUntil[player] = os.clock() + travelTime + TRAIL_DURATION + 0.3

	-- 🔥 경로 잔불 트레일: 스피어가 지나갈 때 바닥에 ds_roadeffect 잔불이 번짐. 창 뒤로 FIRE_TRAIL_OFFSET만큼 밀어 겹침 방지.
	local pathLen = (hitPos - startPos).Magnitude
	local nFire = math.clamp(math.floor(pathLen / FIRE_SPACING), 1, FIRE_POINTS)
	-- 잔불 지점 미리 계산 (지면 위치 + 노멀 + 점화 시각)
	local embers = {}
	for i = 1, nFire do
		local gpt, gnrm = groundHit(startPos:Lerp(hitPos, i / nFire) - direction * FIRE_TRAIL_OFFSET, { character, spear, fxFolder })
		embers[i] = { pt = gpt, nrm = gnrm, igniteAt = (i / nFire) * travelTime }
	end

	-- 잔불 비주얼 생성 (점화 타이밍에 맞춰)
	for _, e in ipairs(embers) do
		task.delay(e.igniteAt, function()
			if not fxFolder.Parent then return end
			local road = ROAD_TEMPLATE:Clone()
			road:ScaleTo(ROAD_SCALE)
			-- hill 경사에 맞춰 기울이기: 모델 Y축을 지면 노멀에 정렬
			local nrm = e.nrm.Unit
			local look = nrm:Cross(Vector3.new(0, 0, 1))
			if look.Magnitude < 0.05 then look = nrm:Cross(Vector3.new(1, 0, 0)) end
			look = look.Unit
			road:PivotTo(CFrame.fromMatrix(e.pt + nrm * 0.5, look, nrm))
			for _, d in ipairs(road:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false
				elseif d:IsA("ParticleEmitter") then
					d.Enabled = true
					if vfxTint then d.Color = tintParticleSeq(d.Color, vfxTint) end
				elseif d:IsA("PointLight") then
					d.Enabled = true
					d.Brightness = d.Brightness * ROAD_LIGHT_DIM
				end
			end
			road.Parent = fxFolder
			task.delay(TRAIL_DURATION, function()
				if road.Parent then
					for _, d in ipairs(road:GetDescendants()) do
						if d:IsA("ParticleEmitter") or d:IsA("PointLight") then d.Enabled = false end
					end
					Debris:AddItem(road, 3)
				end
			end)
		end)
	end

	-- 🔥 통합 지속 즉사 판정: 단일 루프가 모든 잔불 지점을 검사. 점화된(보이는) 잔불 자리에만, 사이 빈공간은 판정 없음.
	--
	-- 🟥 [2026-08-26] 판정 범위 시각화.
	--   [문제] 불 이펙트는 중심만 진하고 가장자리가 흐려서 4덩이로 띄엄띄엄 보인다.
	--     그런데 실제 판정은 간격 16 < 지름 18 이라 이웃끼리 2 stud 씩 겹쳐,
	--     23~89 구간 66 stud 가 '연속된 띠' 다. 빈틈이 없다.
	--     → 러너는 "불 사이는 안전" 이라고 반대로 오해한다(실제로는 전부 판정 안).
	--   [해결] 각 잔불 자리에 판정 반경(EMBER_RADIUS)과 정확히 같은 바닥 원을 깐다.
	--     원끼리 겹치면 겹친 대로 보이므로 "이어진 띠" 라는 사실이 눈에 들어온다.
	--   ⚠️ 반경은 반드시 EMBER_RADIUS 를 그대로 쓴다. 별도 상수를 두면
	--     판정과 표시가 어긋나고, 그건 지금 문제를 반대 방향으로 재현하는 것이다.
	--   ⚠️ 점화 타이밍(igniteAt)도 판정과 같이 맞춘다. 아직 안 붙은 불의 원이
	--     미리 보이면 러너가 없는 위협을 피하게 된다.
	for _, e in ipairs(embers) do
		task.delay(e.igniteAt, function()
			if not fxFolder.Parent then return end
			local disc = Instance.new("Part")
			disc.Name = "_EmberZone"
			disc.Shape = Enum.PartType.Cylinder
			disc.Size = Vector3.new(0.3, EMBER_RADIUS * 2, EMBER_RADIUS * 2)
			disc.Color = Color3.fromRGB(255, 90, 30)
			disc.Material = Enum.Material.Neon
			disc.Transparency = 0.65
			disc.Anchored = true
			disc.CanCollide = false
			disc.CanTouch = false
			disc.CanQuery = false      -- ⚠️ 태거 조준 레이를 막으면 안 된다
			disc.CastShadow = false
			-- Cylinder 원통축은 로컬 X → 눕혀서 바닥 원으로 만든다
			disc.CFrame = CFrame.new(e.pt) * CFrame.Angles(0, 0, math.rad(90))
			disc.Parent = fxFolder
			-- ⚠️ 지속 시간의 대부분은 선명하게 유지하고, 마지막 0.6초에만 옅어진다.
			--   바로 페이드를 걸면 원이 즉시 사라져 표시 목적을 잃는다.
			task.delay(math.max(TRAIL_DURATION - 0.6, 0), function()
				if not disc.Parent then return end
				game:GetService("TweenService")
					:Create(disc, TweenInfo.new(0.6), { Transparency = 1 }):Play()
			end)
			Debris:AddItem(disc, TRAIL_DURATION)
		end)
	end

	-- 🔥 잔불 지속 데미지 (TNT 잔불과 같은 규약).
	--
	-- ⚠️ [설계 변경 2026-08-26] processHit(다운) → TakeDamage(지속 HP 딜).
	--   [기존] 잔불이 processHit 을 불러 '접촉 즉시 다운' 이었다.
	--     그런데 오늘 "1발사 = 1히트" 를 hitObject 인스턴스 기준 영구 기록으로
	--     바꾸면서, emberHitter 가 투척당 파트 하나라 잔불이 1회 판정이 돼버렸다.
	--     내구도 1칸이 잔불 전체를 막아주는 상태였다(의도치 않은 하향).
	--   [지금] TNT 잔불과 같이 HP 지속 데미지로 바꾼다. 그러면:
	--     · "잔불" 이라는 같은 이름의 장치가 같은 규칙으로 작동한다
	--     · 내구도(1히트 방패)와 무관해진다 — 방패는 '한 방' 을 막는 것이지
	--       '불 위에 서 있는 것' 을 막는 게 아니다
	--     · 지나가면 조금 아프고, 머물면 위험하다 = 지대다운 성격
	--
	-- ⚠️ HP 가 0 에 닿는 순간만 processHit 으로 넘긴다. TakeDamage 로 0 이 되면
	--   다운을 건너뛰고 즉사한다(프로스트드래곤 잔류지대에서 겪은 것과 같은 함정).
	-- ⚠️ 대상당 1회만 다운시킨다. Heartbeat 성 루프라 가드가 없으면 매 틱마다
	--   processHit + Part 생성이 반복된다(잔류지대에서 실제로 터졌던 버그).
	local emberHitter = Instance.new("Part")
	emberHitter.Name = "DemonEmberHitter"; emberHitter.Anchored = true; emberHitter.CanCollide = false
	emberHitter.CanQuery = false; emberHitter.CanTouch = false; emberHitter.Transparency = 1
	emberHitter.Size = Vector3.one; emberHitter.CFrame = CFrame.new(impactCenter); emberHitter.Parent = fxFolder
	local emberDowned = {}   -- [Humanoid] = true. 중복 다운 방지
	task.spawn(function()
		local op = OverlapParams.new()
		op.FilterType = Enum.RaycastFilterType.Exclude
		op.FilterDescendantsInstances = { character, spear, fxFolder }
		local t0 = tick()
		while fxFolder.Parent do
			local elapsed = tick() - t0
			if elapsed > travelTime + TRAIL_DURATION then break end
			local seen = {}
			for _, e in ipairs(embers) do
				if elapsed >= e.igniteAt and elapsed <= e.igniteAt + TRAIL_DURATION then
					for _, p in ipairs(workspace:GetPartBoundsInRadius(e.pt, EMBER_RADIUS, op)) do
						local m = p:FindFirstAncestorOfClass("Model")
						if m and not seen[m] and m:FindFirstChildOfClass("Humanoid") and not isInTaggerBase(m) then
							seen[m] = true
							-- ⚠️ 태거 베이스 안이면 잔불 면역.
							--    베이스에서 언덕으로 던지면 잔불 경로가 베이스까지 펼쳐져
							--    러너가 '안전한 곳에서' 죽는 문제가 있었다.
							local hum = m:FindFirstChildOfClass("Humanoid")
							if hum and hum.Health > 0
							   and not m:GetAttribute("Downed") and not emberDowned[hum] then
								if hum.Health - EMBER_DAMAGE_PER_TICK <= 0 then
									hum.Health = 1   -- 0 직전에서 멈추고 다운 파이프라인으로
									emberDowned[hum] = true
									pcall(function() _G.processHit(m, emberHitter) end)
								else
									hum:TakeDamage(EMBER_DAMAGE_PER_TICK)
								end
							end
						end
					end
				end
			end
			task.wait(EMBER_SWEEP)
		end
	end)

	-- 도착 순간 1회 광역 스냅샷 즉사 (불꽃 없이 범위만)
	local function resolveImpact()
		-- 공중 직격 캐릭터(있으면)
		local directChar = nil
		if hitPart then
			directChar = hitPart.Parent
			if directChar and directChar:IsA("Accessory") then directChar = directChar.Parent end
			if directChar and not directChar:FindFirstChildOfClass("Humanoid") then directChar = nil end
		end

		-- 범위 내 모든 휴머노이드 즉사 (mic bomb 식 스냅샷)
		local hitter = Instance.new("Part")
		hitter.Name = "DemonZoneHitter"; hitter.Anchored = true; hitter.CanCollide = false
		hitter.Transparency = 1; hitter.Size = Vector3.one
		hitter.CFrame = CFrame.new(impactCenter); hitter.Parent = fxFolder
		-- ⚠️ 지연 폭발까지 살아있어야 processHit 의 가해자로 쓰인다.
		Debris:AddItem(hitter, BLAST_WARNING + 2)

		local op = OverlapParams.new()
		op.FilterType = Enum.RaycastFilterType.Exclude
		op.FilterDescendantsInstances = { character, spear, fxFolder }

		local seen = {}
		-- 🚧 [진단 2026-08-26] 명중 결과 추적.
		--   [왜] 데몬스피어는 명중 로그가 아예 없어, 로그로는 "안 맞았는지
		--   맞았는데 내구도가 막았는지" 를 구분할 수 없었다. 프리미엄 라인
		--   밸런스를 재려면 이 구분이 필수다. (EnergyBall 은 반대로 결과를
		--   확인하지 않고 무조건 '즉사' 를 찍어 3명을 죽인 것처럼 보였다)
		-- 🛡️ [2026-08-30] 이 창 한 자루가 방패를 두 번 먹지 않게 한다.
		--   [증상] 창 하나에 방패가 2개 소모됐다(실측 13:41 — 직격에서 하나,
		--     0.8초 뒤 범위에서 또 하나. BLAST_WARNING 간격과 정확히 일치).
		--   [원인] 직격·범위가 각각 hitAndLog 를 부르는데, 둘 다 독립적으로 방패를 조회했다.
		--   ⚠️ 한 번 막았으면 그 창의 나머지 판정은 전부 무효다 — 재조회하지 않고 바로 return.
		--     그래야 "한 공격 = 방패 하나" 가 지켜진다.
		local spearShieldUsed = false

		local function hitAndLog(target, hitterPart, label)
			-- 🛡️ [2026-08-30 개정2] 우든 실드 엄폐 판정. 직격·범위 두 경로가 이 함수를 지난다.
			--   [왜 엄폐형인가] 데몬스피어는 착탄점에서 퍼지는 범위기다. 피격자는 방패에서
			--     수십 stud 떨어져 있을 수 있어, 발사체용 경로 판정(반경 14)으로는 안 걸린다
			--     (실측 13:35 — 피격자·방패 거리 20 이라 조용히 뚫렸다).
			--   [왜 방향인가] 착탄점을 넘기면 그게 피격자와 겹칠 때 방향이 성립하지 않는다.
			--     창이 날아온 방향(direction)이 유일하게 안정적인 기준이다.
			--   ⚠️ 잔불 지대는 이 함수를 안 지난다(processHit 직접 호출) → 그대로 안 막힌다. 의도.
			if spearShieldUsed then
				-- 이미 이 창은 방패에 막혔다. 방패를 또 쓰지 않고 피해만 무효.
				print(string.format("🔥🗡️ [Demonspear/%s] 방패에 차단(동일 창) → %s", label, target.Name))
				return
			end
			if _G.WoodShieldBlocks and _G.WoodShieldBlocks(target, direction) then
				spearShieldUsed = true
				print(string.format("🔥🗡️ [Demonspear/%s] 방패에 차단 → %s", label, target.Name))
				return
			end
			local before = target:GetAttribute("Durability") or 0
			_G.processHit(target, hitterPart)
			local after = target:GetAttribute("Durability") or 0
			if after < before then
				print(string.format("🔥🗡️ [Demonspear/%s] 내구도로 막힘 → %s (남은 %d)",
					label, target.Name, after))
			else
				print(string.format("🔥🗡️ [Demonspear/%s] 명중 → %s", label, target.Name))
			end
		end

		-- ⚠️ 직격은 즉시. 창에 직접 맞은 것이라 예고가 불필요하다.
		if directChar and _G.processHit then
			seen[directChar] = true
			-- ⚠️ 태거 베이스 안이면 면역
			if not isInTaggerBase(directChar) then
				hitAndLog(directChar, spear, "직격")
			elseif _G.showBaseImmune then
				-- 🛡️ [2026-09-01] 막힌 순간을 보여준다.
				--   [왜] 여기엔 표시도 로그도 없어서, 베이스 위 러너에겐 그냥 "판정 안에
				--     있었는데 아무 일도 안 일어남" 으로 읽혔다. ItemSpawnHandler:581 의
				--     "표시가 없으면 양쪽 다 '버그'로 읽는다" 가 그대로 재현된 것이다.
				_G.showBaseImmune(directChar)
			end
		end

		-- ⚠️ [밸런스 2026-08-25 → 2026-09-01 개정] 예고의 위치가 바뀌었다.
		--    [예전] 링과 동시에 터져 러너가 반응할 수 없었다 → 착탄 후 0.8초 대기를 넣었다.
		--    [지금] BLAST_WARNING = 0. 예고는 '비행 시간'이 담당한다 — 링은 던지는 순간
		--      생성되어 창이 날아오는 내내(최대 2.5초) 떠 있고, 착탄과 동시에 터진다.
		--      "원이 떠 있는 동안 빠져나간다"가 대응 방식이다.
		--    ⚠️ 그래서 이 task.delay 는 현재 0 이지만 구조는 남겨둔다 —
		--      다시 착탄 후 대기를 주고 싶으면 상수만 올리면 된다.
		task.delay(BLAST_WARNING, function()
			if not hitter.Parent then return end
			-- 🛡️ [2026-09-01] 베이스 면역으로 걸러진 인원을 센다.
			--   [왜] 2단계 전장이 통째로 태거 베이스 위라, 범위 판정이 전원 면역으로
			--     조용히 사라져도 로그가 한 줄도 안 남았다. 실측(16:30:01): 성문 붕괴
			--     1.4초 뒤 러너 9명이 뭉쳐 있었는데 [범위] 줄이 0건이었다.
			--     "안 맞은 것"과 "면역으로 막힌 것"을 로그로 구분할 수 있어야 한다.
			local immuneCount = 0
			for _, p in ipairs(workspace:GetPartBoundsInRadius(impactCenter, KILL_RADIUS, op)) do
				local m = p:FindFirstAncestorOfClass("Model")
				if m and not seen[m] and m:FindFirstChildOfClass("Humanoid") then
					seen[m] = true
					-- ⚠️ 태거 베이스 안이면 면역
					if _G.processHit and not isInTaggerBase(m) then
						hitAndLog(m, hitter, "범위")
					else
						immuneCount = immuneCount + 1
						if _G.showBaseImmune then _G.showBaseImmune(m) end
					end
				end
			end
			if immuneCount > 0 then
				print(string.format("🛡️ [Demonspear/범위] 태거 베이스 면역으로 제외 %d명", immuneCount))
			end
		end)

		-- 텔레그래프(링): 착탄 플래시 후 제거
		for _, s in ipairs(zone:GetDescendants()) do
			if s:IsA("BasePart") then
				s.Color = vfxTint and tintHue(Color3.fromRGB(255, 130, 60), vfxTint) or Color3.fromRGB(255, 130, 60)
				s.Transparency = 0.1
			end
		end
		-- ⚠️ 링은 폭발까지 남아야 경고 역할을 한다.
		Debris:AddItem(zone, BLAST_WARNING + 0.3)
	end

	-- 비행 애니메이션 → 도착 시 박힘(embed) + resolveImpact
	local t0 = tick()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not spear.Parent then conn:Disconnect() return end
		local alpha = math.min((tick() - t0) / travelTime, 1)
		spear.CFrame = CFrame.lookAt(startPos:Lerp(hitPos, alpha), hitPos) * AIM_ROT
		if alpha >= 1 then
			conn:Disconnect()
			-- 박힘
			-- 착탄한 창은 항상 베이스(러너 스폰) 쪽을 향하게 고정 (못 찾으면 던진 방향)
			local horiz = Vector3.new(direction.X, 0, direction.Z)
			horiz = (horiz.Magnitude > 0.01) and horiz.Unit or direction
			local faceDir = getBaseDir(hitPos) or horiz
			-- faceDir 기준 롤 유지한 채 코(촉=+Y)만 EMBED_PITCH만큼 틸트
			local baseRot = (CFrame.lookAt(Vector3.new(), faceDir) * AIM_ROT * CFrame.Angles(math.rad(EMBED_PITCH), 0, 0)).Rotation
			-- 창끝(A1=point1, 스케일 반영됨)이 착탄점에 오도록 배치
			local tipAtt = spear:FindFirstChild("A1")
			local tipOffLocal = tipAtt and tipAtt.Position or Vector3.new(0, SPEAR_LEN * 0.5, 0)
			local tipOffWorld = baseRot:VectorToWorldSpace(tipOffLocal)   -- 중심→창끝 월드 오프셋
			local tipDir = tipOffWorld.Unit
			local embedCenter = hitPos - tipOffWorld + tipDir * EMBED_DEPTH + Vector3.new(0, EMBED_LIFT, 0)
			spear.CFrame = CFrame.new(embedCenter) * baseRot
			if hitPart then
				spear.Anchored = false
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = spear; weld.Part1 = hitPart; weld.Parent = spear
			end
			resolveImpact()
		end
	end)

	return true   -- 실제로 발사됨 (ItemSpawnHandler가 이 결과로만 로그·쿨다운 적용)
end

_G.throwDemonSpear = throwDemonSpear
print("✅ DemonSpearSystem ready (발사 잠금: DS 소멸 후 재발사 / 착탄 원 즉사 + 잔불 자리 통합 지속 즉사)")
