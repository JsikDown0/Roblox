-- SpearSystem
-- 태거 저가형 가성비 투척 아이템 'Spear'.
-- Ice Bow 투척 로직 참고: 시작점(태거 손)에서 클릭 지점 방향으로 레이캐스트 즉시 히트 +
--   Spear 메시 발사체를 Heartbeat로 비행시키는 시각 연출.
-- 맞은 대상이 러너(또는 NPC)면 _G.processHit로 공통 킬 파이프라인(다운/장착 킬이펙트)을 태움.
-- Ice Bow와 달리 횟수 제한 없음(메뉴 공통 2초 쿨다운 + 내부 연사 방지만).

local Players       = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Debris        = game:GetService("Debris")
local RunService    = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local taggerItems   = ServerStorage:WaitForChild("TaggerItem")
local SPEAR_TEMPLATE = taggerItems:WaitForChild("Spear")
local SPEAR_SOUND   = ReplicatedStorage:WaitForChild("SpearSound")
local NoobColorPalette = require(ReplicatedStorage:WaitForChild("NoobColorPalette"))

-- ─── 설정 ───────────────────────────────────────
local SPEAR_SPEED   = 105     -- stud/sec (비행 시각 속도)
                              -- 판정이 창 전체(Blockcast)로 넓어져 명중률이 크게 올랐으므로
                              -- 러너가 보고 반응할 여지를 주기 위해 하향 (구 180)
local SPEAR_RANGE   = 1200    -- 최대 사거리
local SPEAR_LENGTH  = 12      -- 발사체 길이(stud)
local SPEAR_THICK   = 1.8     -- 발사체 굵기(stud) — 바늘처럼 안 보이게 두껍게
local AIM_YAW_DEG   = -90     -- 메시 장축을 진행방향으로 정렬 (촉이 앞을 향하게 반전)
local STICK_TIME    = 3       -- 박힌 채(땅/몸) 남는 시간(초)
local EMBED_DEPTH   = 1.5     -- 몸에 꽂힐 때 촉이 파고드는 깊이(stud)
local MIN_INTERVAL  = 0.3     -- 내부 연사 방지(초)
-- 🛡️ 방패에 막혔을 때 그 자리에 꽂혀 있다 사라지기까지(초).
--   ⚠️ 에너지볼(0.8)과 맞춘다. 두 발사체가 다른 리듬이면 "왜 얘만 빨리 사라지지"가 된다.
local SPEAR_STALL_TIME = 0.8
local HIT_RADIUS   = 1.6   -- 판정 박스의 반폭(stud). Blockcast 로 "창 전체"를 쓸므로
                           -- 구체 시절처럼 크게 잡을 필요가 없다.
                           -- 실제 판정 크기 = (HIT_RADIUS*2) × (HIT_RADIUS*2) × SPEAR_LENGTH
                           -- 즉 3.2×3.2×12 박스가 경로를 쓴다.
                           -- ⚠️ 3.0 이었을 때: 단면 6×6 → 캐릭터 폭(2.0)의 3배, 창 실제
                           --    두께(1.8)의 3.3배. 중심선에서 4.0 스터드 벗어나도 맞아
                           --    "피했는데 죽는다"는 체감이 나왔다(실측 후 하향).
                           -- 이력: 2.5→4.5→6.0→9.0→박스전환(3.0)→1.6
-- ⚠️ 출시 전 false 로 변경 — 판정 구체를 실제로 그려 보여주는 디버그 표시
local DEBUG_HITBOX = false
local Debris = game:GetService("Debris")

local AIM_ROT = CFrame.Angles(0, math.rad(AIM_YAW_DEG), 0)
local lastThrow = {}

local function getOrigin(character)
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if hand then return hand.Position end
	local root = character:FindFirstChild("HumanoidRootPart")
	return root and root.Position or nil
end

local function throwSpear(player, clickPosition)
	if not player or typeof(clickPosition) ~= "Vector3" then return end
	local character = player.Character
	if not character then return end

	local now = tick()
	if lastThrow[player] and now - lastThrow[player] < MIN_INTERVAL then return end
	lastThrow[player] = now

	local startPos = getOrigin(character)
	if not startPos then return end


	-- 목표 지점: 클릭 위치, 사거리(SPEAR_RANGE)로 클램프
	local toTarget = clickPosition - startPos
	if toTarget.Magnitude < 1 then return end
	local rayLen = math.min(toTarget.Magnitude, SPEAR_RANGE)
	local direction = toTarget.Unit
	local targetPos = startPos + direction * rayLen

	-- 히트 판정: 지형은 무시하고 "휴머노이드 캐릭터"만 대상으로 Spherecast
	-- → 가는 레이 대신 반경 HIT_RADIUS 구체를 진행방향으로 쓸어 경로상 러너/더미 명중.
	--   (메시 굵기는 시각용일 뿐 판정과 무관하므로, 살짝 빗나가도 구체가 몸을 스치면 적중)
	-- ⚠️ GetDescendants 로 훑는다 — GetChildren 만 보면 폴더 안에 든 캐릭터가 통째로
	--    판정 대상에서 빠져 "분명 조준했는데 안 맞는" 상황이 된다 (2026-08 실측).
	-- ⚠️ 조준점은 캐릭터 뒤 지면에 잡히는 경우가 많다(몸통이 R6 기준 2×2×1 로 작아
	--    마우스가 살짝만 빗나가도 뒤가 잡힘). 그래서 "클릭 지점"이 아니라
	--    "발사 경로 전체"에서 캐릭터를 찾아야 체감이 맞는다.
	local include = {}
	for _, m in ipairs(workspace:GetDescendants()) do
		if m ~= character and m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") then
			-- 태거 본인 제외 + 이미 죽은 캐릭터 제외
			-- ⚠️ NoTarget 표식이 있는 모델도 제외 — 로비 상점 NPC 처럼 "Humanoid 는 있지만
			--    전투 대상이 아닌" 오브젝트가 표적이 되지 않게 한다.
			local h = m:FindFirstChildOfClass("Humanoid")
			if h.Health > 0 and m:GetAttribute("NoTarget") ~= true then
				table.insert(include, m)
			end
		end
	end
	-- ⚠️ 발사 시점의 즉시 캐릭터 판정은 제거했다.
	--    창이 도착하는 데 최대 1.6초 걸리는데 판정이 0초에 끝나면
	--    "피했는데 죽음 / 맞았는데 안 죽음"이 동시에 나와 규칙을 배울 수 없다.
	--    → 캐릭터 명중은 비행 루프의 flightScan 이 매 프레임 담당한다.
	--    여기서는 "창이 어디까지 날아갈지"(지형 착탄점)만 정한다.
	local sweepLen = math.min(SPEAR_RANGE, 1000)
	local result = nil



	local hitPos, hitPart
	if result then
		hitPos, hitPart = result.Position, result.Instance
		print("🗡️ Spear 명중 판정:", hitPart.Parent and hitPart.Parent.Name or hitPart.Name)
	else
		hitPos = targetPos   -- 경로상 캐릭터 없음 → 클릭 지점(사거리 한도)까지 비행
		print("🗡️ Spear 빗나감 (경로상 캐릭터 없음)")
	end

	-- 시각 발사체 (Spear 메시) — 장착 스킨: 색 스킨은 베이스+색칠, 이펙트 스킨(Rainbow)은 모델교체
	local template = SPEAR_TEMPLATE
	local skinData = nil
	if _G.getEquippedSkin then
		local skin = _G.getEquippedSkin(player, "Spear")
		if skin and player:GetAttribute("Has_" .. skin) == true then
			local data = _G.getSwordSkinData and _G.getSwordSkinData("Spear", skin)
			if data and data.color then
				skinData = data  -- 색 스킨: 베이스 메시 유지 + material/color
			else
				local skinTemplate = taggerItems:FindFirstChild(skin)
				if skinTemplate then template = skinTemplate end  -- 이펙트 스킨(Rainbow 등): 모델교체 폴백
			end
		end
	end
	-- _Custom: 스킨 없을 때(effect/색스킨 아님) SpearColor/SpearMaterial 속성으로 색칠
	local customColor, customMat
	if not skinData and template == SPEAR_TEMPLATE then
		local cfg = NoobColorPalette.getConfig("Spear")
		local colorName = player:GetAttribute("SpearColor_Blade") or cfg.zoneDefault.Blade
		if colorName and NoobColorPalette.COLORS[colorName] then
			customColor = NoobColorPalette.COLORS[colorName]
			customMat = player:GetAttribute("SpearMaterial_Blade") or cfg.materialDefault
		end
	end
	local spear = template:Clone()
	-- 색 스킨: 베이스 텍스처 제거 후 색칠 (기존 색 스킨 모델과 동일한 결과)
	if skinData then
		spear.TextureID = ""
		spear.Material = Enum.Material[skinData.material] or Enum.Material.Neon
		spear.Color = skinData.color
	elseif customColor then
		NoobColorPalette.applyFinish(spear, customMat, customColor)
	end
	spear.Name = "ThrownSpear"
	spear.Anchored = true
	spear.CanCollide = false
	spear.CanQuery = false
	spear.CanTouch = false
	spear.Massless = true
	-- 🤖 농민봇 위협 인지용 태그.
	--    Anchored + CFrame 보간으로 날아가므로 AssemblyLinearVelocity 가 항상 0 이다.
	--    RunnerBotDriveController 가 이 태그를 보고 위치 차분으로 실속도를 역산한다.
	--    (CG 를 "TaggerItems" 로 바꾸지 않는 이유: 러너 마커가 붙어버림 — 별도 결정사항)
	spear:SetAttribute("BotThreat", true)
	-- 🗡️ [밸런스 2026-09-19] 적중 시 2히트 판정 — 내구도 1칸을 뚫고 다운시킨다.
	--   [왜] Spear 는 직선 투사체라 봇 회피에 가장 약하다. 실측 명중률 18%
	--     (11회 투척 → 2회 명중). 다른 태거 아이템 평균은 34%.
	--   [왜 쿨을 안 내렸나] 태거 아이템은 전부 한 방에 다운시킨다 —
	--     연사를 주면 곧 '다운 연사'가 되어 Spear 하나가 다른 세 칸을 무의미하게 만든다.
	--     그래서 명중 **빈도** 대신 명중 **1회의 가치**를 올렸다.
	--   [규약] ItemDamageSystem.processHit 이 이 속성을 읽어
	--     DurabilitySystem.absorb(char, src, count) 로 넘긴다.
	--     내구도가 count 보다 적으면 가진 만큼 깎이고 히트가 그대로 진행된다(= 다운).
	--   ⚠️ processHit 을 두 번 부르는 방식은 성립하지 않는다 — absorb 의 무적 가드가
	--     "같은 아이템의 연속 판정"으로 보고 두 번째를 또 흡수한다. 그래서 count 방식이다.
	--   ⚠️ 되돌리려면 이 줄만 지운다. 속성이 없으면 count 가 1로 떨어져 기존 동작이다.
	--   💡 아머 상품(DurabilitySystem grant n칸)이 생기면 2칸 러너는 이 한 방을 견딘다.
	--     "관통 무기 vs 방어 강화" 축이 자동으로 성립한다.
	spear:SetAttribute("HitCount", 2)
	spear.Size = Vector3.new(SPEAR_LENGTH, SPEAR_THICK, SPEAR_THICK)
	spear.CFrame = CFrame.lookAt(startPos, hitPos) * AIM_ROT
	spear.Parent = workspace
	Debris:AddItem(spear, 0.6 + STICK_TIME + 0.3)

	-- 가시성: 발광 + 비행 트레일
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(190, 225, 255)
	light.Brightness = 3
	light.Range = 12
	light.Parent = spear

	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0,  SPEAR_THICK, 0)
	a0.Parent = spear
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -SPEAR_THICK, 0)
	a1.Parent = spear
	-- ⚠️ 시인성 강화 (2026-08): 속도 180 + 얇은 몸체라 "언제 날아왔는지 모르고 죽는다"는
	--    피드백이 있었다. EnergyBall/BlackHole 은 발광·파티클로 예고가 되는데 창은 없었음.
	--    Trail 을 길고 굵게 + 발광체를 붙여 접근을 미리 인지할 수 있게 한다.
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.6                    -- 0.25 → 0.6 (꼬리를 길게 남겨 궤적이 보이게)
	trail.Color = ColorSequence.new(Color3.fromRGB(120, 200, 255))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),   -- 0.1 → 0 (시작부 완전 불투명)
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2.2), -- 1 → 2.2 (굵게)
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Parent = spear

	-- 창 끝 발광 코어: 멀리서도 "무언가 날아온다"가 읽히도록
	local glow = Instance.new("Part")
	glow.Name = "SpearGlow"
	glow.Shape = Enum.PartType.Ball
	glow.Size = Vector3.new(2.6, 2.6, 2.6)
	glow.Material = Enum.Material.Neon
	glow.Color = Color3.fromRGB(150, 215, 255)
	glow.Transparency = 0.25
	glow.CanCollide = false
	glow.Anchored = true
	glow.CastShadow = false
	glow.CFrame = spear.CFrame
	glow.Parent = spear

	local gl = Instance.new("PointLight")
	gl.Color = Color3.fromRGB(150, 215, 255)
	gl.Brightness = 2.5
	gl.Range = 18
	gl.Parent = glow

	-- 발사 사운드: 태거는 2D로 반드시 들리게, 러너/관전자는 큰 범위 3D로 (클라 분기)
	SPEAR_SOUND:FireAllClients(startPos, player.UserId)

	-- 비행 (Heartbeat lerp)
	-- ⚠️ 상한 0.6초로는 원거리에서 사실상 순간이동이라 회피가 불가능했다.
	--    속도(SPEAR_SPEED)를 낮춰도 이 clamp 에 걸리면 의미가 없으므로 상한도 함께 완화.
	local travelTime = math.clamp(rayLen / SPEAR_SPEED, 0.12, 1.6)
	local t0 = tick()
	local conn

	-- ── 비행 중 판정 ────────────────────────────────────
	-- ⚠️ 이전에는 발사 순간 Blockcast 로 1000스터드 전 구간을 한 번에 판정했다.
	--   창이 도착하는 데 최대 1.6초 걸리는데 판정은 0초에 끝나므로:
	--     · 조준선에 스친 러너는 이후 어디로 도망쳐도 죽음
	--     · 발사 후 경로에 들어온 러너는 정면 관통에도 안 맞음
	--   회피 시스템(봇/사람 모두)이 무의미해지는 근본 원인이었다.
	--   → 창이 "이번 프레임에 실제로 지나간 구간"만 매 프레임 검사한다. 보이는 대로 맞는다.
	local flightHit = nil       -- 비행 중 명중한 캐릭터
	local flightHitPart = nil
	local lastFlightPos = startPos

	-- ⚠️ [SPEAR-BASE] 태거베이스 안의 러너는 판정 대상에서 뺀다.
	--    창은 taggerbase 를 '관통 허용'으로 처리하는데(아래 차폐 검사),
	--    그 탓에 각도에 따라 베이스를 경유하며 안쪽 러너까지 맞혔다
	--    (실측 2026-08-21). 태거 아이템은 베이스 안에서 작동하면 안 된다 —
	--    2단계에서도 즉사 무기를 쓰는 셈이 되어 안전지대 원칙이 깨진다.
	-- ⚠️ [버그수정 2026-09-01] 자체 복사본 폐기 → _G.IsCharInTaggerBase 로 위임.
	--   [증상] 2단계(map2)에서 러너가 베이스 위에 서 있는데도 창에 맞아 다운→사망했다
	--     (실측 16:41:14 melonberrystrong. 성문은 16:40:45 에 이미 붕괴).
	--   [원인] 여기 있던 복사본이 Y 까지 엄격한 AABB 였다. 베이스는 바닥 슬래브라
	--     (map2 castle.taggerbase2 두께 2.98) 그 위에 선 캐릭터의 HRP 는 박스 '밖'이다
	--     → 밴드가 없으면 아무도 면역을 못 받는다.
	--   [경위] ItemSpawnHandler 의 _G.IsCharInTaggerBase 는 바로 이 문제 때문에 만들어진
	--     통합 판정이다(높이 밴드 +12 · 캐시 무효화 · showBaseImmune 포함). 그 주석에
	--     "5벌 중 Spear 만 높이 밴드가 빠져 실제로 갈라졌다"고 적혀 있는데,
	--     Bomb·EnergyBall·DemonSpear·FrostDragon 은 이관됐고 정작 원인이던 Spear 만 남아 있었다.
	--   ⚠️ 다시 복사하지 말 것. 여기서 하던 showBaseImmune 호출도 통합본 안에 들어 있다.
	local function isInTaggerBase(model)
		if not _G.IsCharInTaggerBase then return false end
		return _G.IsCharInTaggerBase(model)
	end

	local function flightScan(fromPos, toPos)
		local seg = toPos - fromPos
		local dist = seg.Magnitude
		if dist < 0.01 then return nil end
		-- 살아있는 러너/더미만 대상 (발사 시점 include 재사용은 위험 — 매번 갱신)
		-- NoTarget 모델(로비 상점 NPC 등)은 제외
		local targets = {}
		for _, m in ipairs(workspace:GetDescendants()) do
			if m ~= character and m:IsA("Model") and m:GetAttribute("NoTarget") ~= true then
				local h = m:FindFirstChildOfClass("Humanoid")
				if h and h.Health > 0 and not isInTaggerBase(m) then
					targets[#targets + 1] = m
				end
			end
		end
		if #targets == 0 then return nil end
		local prm = RaycastParams.new()
		prm.FilterType = Enum.RaycastFilterType.Include
		prm.FilterDescendantsInstances = targets
		local cf = CFrame.lookAt(fromPos, toPos)
		local size = Vector3.new(HIT_RADIUS * 2, HIT_RADIUS * 2, SPEAR_LENGTH)
		local r = workspace:Blockcast(cf, size, seg.Unit * dist, prm)
		if not r then return nil end

		-- 차폐: 이 구간에서 창과 대상 사이에 막는 구조물이 있으면 무효.
		-- (Include 필터라 캐릭터만 보므로 벽을 그냥 관통한다 — 별도 확인 필요)
		-- 통과로 치는 것: 산·태거아이템·비충돌 파트·바리케이드·태거 발판
		local bp = RaycastParams.new()
		bp.FilterType = Enum.RaycastFilterType.Exclude
		bp.FilterDescendantsInstances = { character, spear }
		bp.IgnoreWater = true
		local toHit = r.Position - fromPos
		local hitDist = toHit.Magnitude
		if hitDist > 1 then
			local d2 = toHit.Unit
			local o, remain = fromPos, hitDist - 0.5
			for _ = 1, 8 do
				local b = workspace:Raycast(o, d2 * remain, bp)
				if not b then break end
				local inst = b.Instance
				local n = inst.Name:lower()
				local pass = inst.CollisionGroup == "Mountains" or inst.CollisionGroup == "TaggerItems"
					or inst.CanCollide == false
					or (inst.Parent and inst.Parent.Name == "Barricades")
					or n:find("taggerbase") or n:find("itemspawnplate") or n:find("taggerspawn")
				if not pass then
					if DEBUG_HITBOX then
						print(string.format("🧱 [Spear] 차폐: %s → 관통 무효", inst.Name))
					end
					return nil
				end
				local adv = (b.Position - o).Magnitude + 0.5
				remain -= adv
				if remain <= 0 then break end
				o = b.Position + d2 * 0.5
			end
		end
		return r
	end

	-- 🛡️ 방패에 막혔는가. ⚠️ conn 콜백보다 앞에 선언해야 보인다(선언 ≺ 사용).
	local spearBlocked = false

	conn = RunService.Heartbeat:Connect(function()
		if not spear.Parent then conn:Disconnect() return end
		local alpha = math.min((tick() - t0) / travelTime, 1)
		local nowPos = startPos:Lerp(hitPos, alpha)

		-- 🛡️ [2026-08-30] 우든 실드 경로 차단. 명중 판정보다 먼저 본다.
		--   [왜 먼저인가] 방패는 창과 표적 사이에 있다. 명중 뒤에 보면 이미 지나친 뒤라
		--     판정이 뒤집힌다(에너지볼에서 실제로 그랬다 — 방패 X=632, 피격 X=610).
		--   ⚠️ 막히면 그 자리에 꽂힌 뒤 사라진다. 발사체는 '방패에 막혀 소멸'이 자연스럽다
		--     (굴리기는 튕겨 나가고, 쓰나미는 광역이라 계속 흐른다 — 규칙이 다른 건 의도).
		--   ⚠️ 뒤에 러너가 없어도 막힌다. 방패는 엄폐물이지 특정인의 보호막이 아니다.
		if not flightHit and not spearBlocked
		   and _G.WoodShieldBlockAt and _G.WoodShieldBlockAt(nowPos, direction) then
			spearBlocked = true
			print("🗡️ Spear → 방패에 막힘")
			spear.Anchored = true
			task.delay(SPEAR_STALL_TIME, function()
				if spear and spear.Parent then
					local tw = game:GetService("TweenService"):Create(spear,
						TweenInfo.new(0.3), { Transparency = 1 })
					tw:Play()
					game:GetService("Debris"):AddItem(spear, 0.4)
				end
			end)
			conn:Disconnect()
			return
		end

		-- 이번 프레임 이동 구간 판정 (아직 안 맞았을 때만)
		if not flightHit then
			local r = flightScan(lastFlightPos, nowPos)
			if r then
				local node = r.Instance
				while node and node ~= workspace do
					if node:IsA("Model") and node:FindFirstChildOfClass("Humanoid") then
						flightHit = node
						flightHitPart = r.Instance
						break
					end
					node = node.Parent
				end
				if flightHit then
					-- 명중 지점에서 즉시 착탄 처리 (남은 비행 취소)
					hitPos = r.Position
					hitPart = r.Instance
					alpha = 1
					nowPos = hitPos
				end
			end
		end
		lastFlightPos = nowPos

		spear.CFrame = CFrame.lookAt(nowPos, nowPos + direction) * AIM_ROT
		-- 발광체는 Anchored 라 웰드가 안 먹는다 → 매 프레임 창 위치로 따라가게 갱신
		if glow.Parent then glow.CFrame = CFrame.new(spear.Position) end
		if alpha >= 1 then
			conn:Disconnect()
			-- 명중/착탄 시 발광체 제거 (박힌 창이 계속 빛나면 지저분함)
			if glow.Parent then glow:Destroy() end

			-- 명중 대상 캐릭터 해석
			-- ⚠️ hitPart.Parent 가 곧 캐릭터인 경우는 오히려 드물다.
			--    실측: 농민봇의 액세서리(Farmer's_Revenge)에 맞으면
			--      hitPart = Handle → Parent = Accessory → Parent = 캐릭터
			--    한 단계만 올라가는 기존 처리로는 Humanoid 를 못 찾아 char = nil 이 되고,
			--    processHit 이 아예 호출되지 않아 "명중 로그는 뜨는데 다운이 안 되는" 상태가 됐다.
			--    → 조상 방향으로 Humanoid 를 가진 Model 을 찾을 때까지 거슬러 올라간다.
			local char = nil
			if hitPart then
				local node = hitPart
				while node and node ~= workspace do
					if node:IsA("Model") and node:FindFirstChildOfClass("Humanoid") then
						char = node
						break
					end
					node = node.Parent
				end
			end

			if hitPart and not char then
				warn(string.format("[Spear] 캐릭터 해석 실패 — hitPart=%s parent=%s (processHit 미호출)",
					hitPart.Name, tostring(hitPart.Parent and hitPart.Parent.Name)))
			end
			if char and _G.processHit then
				print("🗡️ Spear → processHit:", char.Name)
				_G.processHit(char, spear)

				-- 2) 몸에 꽂힌 채 부착: 촉이 EMBED_DEPTH만큼 파고든 형태로 맞은 파트에 용접 → 몸을 따라감
				trail.Enabled = false
				local embedCenter = hitPos - direction * (SPEAR_LENGTH * 0.5 - EMBED_DEPTH)
				spear.CFrame = CFrame.lookAt(embedCenter, embedCenter + direction) * AIM_ROT
				spear.Anchored = false
				spear.CanCollide = false
				spear.Massless = true
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = spear
				weld.Part1 = hitPart
				weld.Parent = spear
			else
				-- 빗나감: 땅/벽에 박힌 채 고정
				local embedCenter = hitPos - direction * (SPEAR_LENGTH * 0.5 - EMBED_DEPTH)
				spear.CFrame = CFrame.lookAt(embedCenter, embedCenter + direction) * AIM_ROT
			end
		end
	end)
end

_G.throwSpear = throwSpear
print("✅ SpearSystem ready (투척 + _G.processHit, 무제한)")
