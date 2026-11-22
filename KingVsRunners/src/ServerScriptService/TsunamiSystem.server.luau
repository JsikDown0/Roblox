-- TsunamiSystem
-- 태거 아이템 'tsunami': Kinematic + Ground Raycast 방식 (Option 3).
-- 메쉬가 평평한 바닥이라 물리엔진만으론 계단/언덕을 못 넘어감.
-- → Anchored=true로 직접 제어, 앞·뒤 두 지점 raycast로 지면 추적.
-- Y·Pitch 모두 Lerp로 부드럽게 변화시켜 계단의 순간 점프 완화.
-- OverlapParams로 러너 push & ragdoll.

local ServerStorage  = game:GetService("ServerStorage")
local PhysicsService = game:GetService("PhysicsService")
local RunService     = game:GetService("RunService")
local TweenService   = game:GetService("TweenService")
local Debris         = game:GetService("Debris")
local Players        = game:GetService("Players")

local taggerItems     = ServerStorage:WaitForChild("TaggerItem")
local tsunamiFolder   = taggerItems:WaitForChild("tsunami")
local tsunamiTemplate = tsunamiFolder:WaitForChild("tsunami_tagger")

-- 템플릿 내부 waterflowconnectpart 오프셋 (wave 로컬 프레임 기준, 한 번만 계산)
-- 실제 connectpart는 wave 자식이지만 Anchored면 따라가지 않으므로
-- 이 오프셋을 매 프레임 wave.CFrame에 곱해서 expected world position을 얻음
local connectPartLocalCF = nil
do
	local connect = tsunamiTemplate:FindFirstChild("waterflowconnectpart")
	if connect then
		connectPartLocalCF = tsunamiTemplate.CFrame:ToObjectSpace(connect.CFrame)
		print(string.format("[Tsunami] waterflowconnectpart offset 캐싱: 로컬 (%.1f, %.1f, %.1f)",
			connectPartLocalCF.Position.X, connectPartLocalCF.Position.Y, connectPartLocalCF.Position.Z))
	else
		warn("[Tsunami] waterflowconnectpart가 템플릿에 없음 - wave 중심에 spawn")
	end
end

-- ─── WaterfallUpper 원본 BoundingBox 중심 캐싱 ────────────────
-- 모델의 Pivot이 잘못 설정돼 있어서(Pivot Y=106, 실제 파트는 Y=170+) GetPivot 사용 시
-- 클론 위치가 어긋남. 실제 파트들의 BoundingBox 중심을 사용해야 정확.
local upperBBoxCenter = nil
do
	local rs = game:GetService("ReplicatedStorage")
	local folder = rs:FindFirstChild("waterflow vfx")
	local ref = folder and folder:FindFirstChild("WaterfallUpper")
	if ref then
		local minP, maxP
		for _, d in ipairs(ref:GetDescendants()) do
			if d:IsA("BasePart") then
				local p1 = d.Position - d.Size/2
				local p2 = d.Position + d.Size/2
				if not minP then minP, maxP = p1, p2 else
					minP = Vector3.new(math.min(minP.X,p1.X), math.min(minP.Y,p1.Y), math.min(minP.Z,p1.Z))
					maxP = Vector3.new(math.max(maxP.X,p2.X), math.max(maxP.Y,p2.Y), math.max(maxP.Z,p2.Z))
				end
			end
		end
		if minP then
			upperBBoxCenter = (minP + maxP) / 2
			print(string.format("[Tsunami] WaterfallUpper BBox 중심 캐싱: (%.0f, %.0f, %.0f)",
				upperBBoxCenter.X, upperBBoxCenter.Y, upperBBoxCenter.Z))
		end
	end
end

-- ─── Tunables ────────────────────────────────────────────────
local WAVE_SPEED       = 60   -- 진행 속도 (stud/sec)
local LIFETIME_BUFFER  = 2    -- playerbase 도착 예상시간에 더할 여유 (초)
local MIN_LIFETIME     = 5    -- 최소 지속 시간
local MAX_LIFETIME     = 20   -- 최대 지속 시간 (안전상한)
local ARRIVAL_RADIUS   = 20   -- playerbase 도달 판정 반경 (stud, 수평)
local HOVER_OFFSET       = 0    -- 메쉬 바닥이 지면에서 떠있는 정도 (0=딱 붙음)
local Y_LERP_RATE_DOWN   = 18   -- 내려갈 때 (빠르게 따라가야 hill에 붙어 흐름)
local Y_LERP_RATE_UP     = 3    -- 올라갈 때 (느려야 장애물/통나무에 안 튕김)
local TILT_LERP_RATE   = 18   -- 기울기(pitch) 추적 부드러움 (높을수록 슬로프 변화에 즉각 반응)
local MAX_TILT_DEG     = 55   -- 최대 기울기 제한 (가파른 hill에서도 자연스럽게 붙도록 완화)
local BASE_FORWARD_TILT_DEG = 15 -- 평지에서도 항상 적용되는 기본 앞쪽 기울기 (양수=앞으로 기울임)
local YAW_OFFSET_DEG   = -90  -- 메쉬 본연의 정면이 LookVector 컨벤션(-Z)과 어긋난 만큼 보정 (180도 회전 보정 적용)
-- [PUSH_KNOCKBACK-TUNE 2026-08-20] 80/40 → 100/45 상향.
--   방식: hrp.AssemblyLinearVelocity 에 일회성 임펄스 (지속 힘 아님).
--   탄도 수평거리 33 → 46 stud. 단 PlatformStand=true 라 착지 후 남은 RAGDOLL_TIME 동안
--   마찰로 계속 미끄러지므로 실제 이동은 이보다 크다(경사·마찰 의존, 계산 불가 → 실측).
--   RAGDOLL_TIME 은 3 유지: 넉백은 '전진 손실', 무력화 시간 연장은 별개 문제.
--   파도 속도 60 < PUSH_FORCE 100 이라 러너가 파도보다 앞서 밀려나 재피격되지 않음
--   (TsunamiHit 속성 가드도 있음).
-- [PUSH_KNOCKBACK-TUNE 2026-08-20] 80/40 → 100/45 상향.
--   방식: hrp.AssemblyLinearVelocity 에 일회성 임펄스 (지속 힘 아님).
--   탄도 수평거리 33 → 46 stud. 단 PlatformStand=true 라 착지 후 남은 RAGDOLL_TIME 동안
--   마찰로 계속 미끄러지므로 실제 이동은 이보다 크다(경사·마찰 의존, 계산 불가 → 실측).
--   RAGDOLL_TIME 은 3 유지: 넉백은 '전진 손실', 무력화 시간 연장은 별개 문제.
--   파도 속도 60 < PUSH_FORCE 100 이라 러너가 파도보다 앞서 밀려나 재피격되지 않음
--   (TsunamiHit 속성 가드도 있음).
--
-- [재조정 2026-09-02] 밀림은 100/45 그대로 두고, RAGDOLL_TIME 을 3 → 2 로 줄인다.
--   [왜] 2단계에서 계단 위 러너가 정지한 압박선 뒤로 날아가 불기둥에 타 죽었다.
--     실측 3건 — 사망 좌표가 계단 상단에서 117~163 stud 뒤였다.
--     데미지 0 인 제어기가 즉사기로 둔갑하는 통로였다.
--   [왜 PUSH_FORCE 가 아니라 RAGDOLL_TIME 인가] 탄도는 46 stud 뿐이다.
--     실측 거리 117~163 의 대부분은 착지 후 마찰 미끄러짐이므로, 임펄스를 깎아봐야
--     13 stud 밖에 안 줄어든다. 실제 거리를 만드는 변수는 미끄러지는 '시간'이다.
--     (100/45 → 80/40 으로 내려봤다가 이 이유로 원복했다.)
--   ⚠️ 위 08-20 주석의 "RAGDOLL_TIME 은 3 유지" 판단을 뒤집는 것이다.
--     그때는 넉백(전진 손실)과 무력화 시간을 별개 축으로 분리했는데, 실측 결과
--     두 축이 사실상 한 변수였다 — 미끄러짐이 곧 넉백 거리였다.
--   ⚠️ 대가: 제어기로서의 무력화 시간이 3초 → 2초로 같이 줄어든다.
--     쓰나미가 너무 약해지면 다음 후보는 RAGDOLL_TIME 복구가 아니라
--     '2단계 한정 압박선 위치'다 — 밀려난 자리가 곧 지대인 게 근본 원인이다.
local PUSH_FORCE       = 100  -- 명중 시 진행 방향 push
local PUSH_UP_FORCE    = 45   -- 위로 띄움
-- ─── 발사 예고 (TSUNAMI-TELEGRAPH) ────────────────────────────
-- 파도는 clickPosition 에서 태어나 러너 베이스 쪽(-X)으로 쓸고 간다.
-- 2단계 결투장(ItemSpawnPlate2, X 689~711)이 발원지와 겹쳐서, 예고가 없으면
-- 결투 중 러너의 반응시간이 0.00초였다(실측 로그 2회: 발사 시각 == 피격 시각).
-- 아이템 스폰 예고(ItemSpawnHandler)와 같은 시각 언어를 쓴다: ForceField 고스트.
--
-- ⚠️ 실측 점유 범위 (8꼭짓점, direction=-X 기준):
--      진행방향 X 69.4 / 측면 Z 74.9  → 정중앙에서 측면 탈출까지 37.5 stud
--      걸어서(WalkSpeed 16) 2.34초 필요. 즉 1.4초는 "대시(Q)로 피한다"가 전제다.
--      걸어서도 피하게 하려면 TELEGRAPH_TIME_NEAR 를 2.4 로.
local TELEGRAPH_NEAR_RANGE = 45   -- 실측 측면 반폭 37.5 + 여유. 이 안에 러너가 있으면 근접 발사
local TELEGRAPH_TIME_NEAR  = 1.4  -- 그랩 스턴 1.0 + 여유 0.4 (아이템 예고와 같은 값)
local TELEGRAPH_TIME_FAR   = 0.6  -- 원거리: 파도가 날아오는 시간이 따로 있어 짧게

local RAGDOLL_TIME     = 2    -- 래그돌 + 무력화 시간 (2026-09-02: 3 → 2, 위 재조정 주석 참조)

-- ─── 시각 효과 (연출용, 기능 없음) ────────────────────────────
local VFX_UPPER_BACK_OFFSET    = 30   -- WaterfallUpper를 파도 뒤로 떨어진 거리 (stud)
local VFX_UPPER_Y_OFFSET       = 0    -- WaterfallUpper Y 보정 (파도 중심 기준)
local VFX_FLOW_SPAWN_INTERVAL  = 0.5  -- WaterFlow 복제 주기 (초)
local VFX_FLOW_LIFETIME        = 2    -- WaterFlow 복제본 수명 (초)
local VFX_FLOW_Y_OFFSET        = 3    -- WaterFlow 생성 위치 Y 보정 (양수=낮추기) [fallback용]
local VFX_FLOW_Y_OFFSET_FROM_GROUND = 0.5  -- ground raycast hit 위에서 띄우는 거리 (z-fighting 방지)
local VFX_UPPER_FADE_LINGER    = 2    -- 파도 종료 후 WaterfallUpper 잔여 파티클 정리 시간
local VFX_UPPER_SAFETY_TIMEOUT = 15   -- 안전망: 정상 cleanup이 실패해도 이 시간 후 강제 제거 (초)
local VFX_UPPER_BEAM_DURATION  = 1    -- 흰 폭포 빔/미스트 방출 시간(초). 이후 Beam·Emitter 끔 → 발사 직후만 짧게 보임

-- 진행 방향 fallback (playerbase 못 찾는 비정상 케이스용)
local FALLBACK_DIRECTION = Vector3.new(0, 0, 1)

-- ─── 현재 맵의 러너 베이스 찾기 ───────────────────────────────
-- map1/map2가 동시에 workspace에 존재. 태거는 항상 활성 맵 위에서 클릭하므로,
-- 클릭 위치에서 가장 가까운 맵의 베이스 = 활성 맵 베이스 (맵끼리 수천 stud 떨어짐).
-- 맵마다 이름이 달라(map1=playerbase / map2=playerspawn2) 폴백 체인으로 흡수.
local function findPlayerbase(clickPosition)
	local best, bestDist = nil, math.huge
	for _, mapFolder in ipairs(workspace:GetChildren()) do
		if mapFolder.Name:lower():find("map") then
			local base = mapFolder:FindFirstChild("playerbase", true)
				or mapFolder:FindFirstChild("playerspawn", true)
				or mapFolder:FindFirstChild("playerspawn2", true)
			if base and base:IsA("BasePart") then
				local d = clickPosition and (base.Position - clickPosition).Magnitude or 0
				if d < bestDist then bestDist = d; best = base end
			end
		end
	end
	return best
end

-- ─── 러너 ragdoll + push ─────────────────────────────────────
local function ragdollAndPush(runnerCharacter, direction)
	local humanoid = runnerCharacter:FindFirstChildOfClass("Humanoid")
	local hrp = runnerCharacter:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp then return end

	-- ⚠️ [2026-08-28] NoTarget 모델은 전투 대상이 아니다 (연출용 더미·로비 NPC 등).
	--   [증상] 쓰나미가 _PunchDummy(펀치 연출용 킬러 복제본)를 러너로 보고
	--     ragdoll 시켰다(실측 11:39:14.392 / 11:54:50.449).
	--   [왜 CanQuery=false 로 안 막혔나] 더미 파트에 CanQuery=false 를 걸었는데도
	--     detectAndHit 의 GetPartBoundsInBox 가 계속 잡아냈다(11:54 판에서 재현).
	--     → 공간 질의 쪽 차단에 기대지 말고 NoTarget 규약으로 거른다.
	--   ⚠️ 쓰나미는 processHit 을 안 타므로 NoTarget 을 스스로 봐야 한다.
	--     (processHit·SpearSystem:280 은 이미 이 규약을 존중한다)
	if runnerCharacter:GetAttribute("NoTarget") == true then return end

	-- ⚠️ [2026-08-28] 태거 베이스 안이면 면역.
	--   [증상] 쓰나미가 베이스 위 러너를 그대로 밀어냈다. 베이스는 "푸시툴로만
	--     대항하는 결투 구역" 이라 태거 아이템 반입 금지가 원칙인데
	--     (ItemSpawnHandler:436), 쓰나미에만 이 판정이 통째로 없었다.
	--   ⚠️ 판정은 _G.IsOnTaggerBase 를 쓴다. 복사하지 말 것 — 그 함수가
	--     ItemSpawnPlate 중첩과 부동소수점 오차(EDGE_EPS)까지 처리한다.
	--     (BlackHoleSystem:602 흡인 면제와 같은 방식 — 러너 위치 기준)
	--   ⚠️ TsunamiHit 표식보다 '앞'에 둘 것. 뒤에 두면 베이스에서 걸러진 러너가
	--     표식만 얻고, 베이스를 나온 뒤에도 영영 안 맞는다.
	if _G.IsOnTaggerBase and _G.IsOnTaggerBase(hrp.Position) then return end

	if runnerCharacter:GetAttribute("TsunamiHit") then return end
	runnerCharacter:SetAttribute("TsunamiHit", true)

	local pushVel = direction * PUSH_FORCE + Vector3.new(0, PUSH_UP_FORCE, 0)
	hrp.AssemblyLinearVelocity = pushVel

	humanoid.PlatformStand = true
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0

	hrp.AssemblyAngularVelocity = Vector3.new(
		math.random(-8, 8),
		math.random(-4, 4),
		math.random(-8, 8)
	)

	print("🌊 Tsunami → ragdoll:", runnerCharacter.Name)

	task.delay(RAGDOLL_TIME, function()
		if not humanoid or not humanoid.Parent then return end
		humanoid.PlatformStand = false
		humanoid.WalkSpeed = 16
		humanoid.JumpPower = 50
		if runnerCharacter and runnerCharacter.Parent then
			runnerCharacter:SetAttribute("TsunamiHit", nil)
		end
	end)
end

-- ─── 메쉬 영역 내 러너 감지 ────────────────────────────────────
local function detectAndHit(waveMesh, direction, hitSet)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {waveMesh}
	params.MaxParts = 100

	local parts = workspace:GetPartBoundsInBox(waveMesh.CFrame, waveMesh.Size, params)
	for _, part in ipairs(parts) do
		local char = part.Parent
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		if humanoid and not hitSet[char] then
			local plr = Players:GetPlayerFromCharacter(char)
			local isTagger = plr and plr:GetAttribute("Role") == "Tagger"
			if not isTagger then
				hitSet[char] = true
				-- 🛡️ [2026-08-30] 우든 실드로 막을 수 있게 한다.
				--   [배경] 쓰나미는 Anchored + GetPartBoundsInBox 로 러너를 직접 집어가므로
				--     방패의 Touched 가 아예 발생하지 않았다. "막을 수 없다"가 아니라
				--     "방패가 볼 수조차 없다" 였다.
				--   ⚠️ 가해 지점은 파도 중심이다. 방패는 방향이 있어 뒤에서 온 건 안 막는다.
				--   ⚠️ hitSet 에는 그대로 넣는다 — 막혔어도 이번 파도에 재판정될 이유가 없다.
				if _G.WoodShieldBlockAt and _G.WoodShieldBlockAt(waveMesh.Position, direction) then
					print("🌊 Tsunami → 방패에 차단:", char.Name)
					-- 🛡️ 그 자리에서 잠깐 멈춘다(굴리기류와 같은 피드백).
					--   ⚠️ 멈추기만 한다. 판정은 이미 끝났고 다른 러너는 계속 맞는다.
					if _G.__TsunamiStall then _G.__TsunamiStall() end
				else
					ragdollAndPush(char, direction)
				end
			end
		end
	end
end

-- ─── 앞·뒤 두 지점에서 지면 raycast ───────────────────────────
local function probeGround(centerPos, direction, halfLength, params)
	local rayUp  = Vector3.new(0, 100, 0)
	local rayDir = Vector3.new(0, -400, 0)

	local frontPos = centerPos + direction * halfLength
	local backPos  = centerPos - direction * halfLength

	local frontHit = workspace:Raycast(frontPos + rayUp, rayDir, params)
	local backHit  = workspace:Raycast(backPos  + rayUp, rayDir, params)

	return frontHit, backHit
end

-- ─── 시각 효과 헬퍼 ──────────────────────────────────────────
-- 모델 찾기: workspace → ReplicatedStorage → ServerStorage 순서로 재귀 탐색
local function findVFXModel(name)
	local found = workspace:FindFirstChild(name, true)
	if found then return found end
	found = game:GetService("ReplicatedStorage"):FindFirstChild(name, true)
	if found then return found end
	found = ServerStorage:FindFirstChild(name, true)
	return found
end

-- ── 색조(hue) 틴트: 원본 명암·포말 그라데이션은 유지하고 색조만 타겟색으로 (B 방식) ──
-- 원본 채도·명도 유지 + 타겟 hue → 흰 포말(채도≈0)은 흰색 그대로, 짙은 물색만 타겟 색조로.
-- 타겟이 무채색(흰/회/검, 채도<0.12)이면 채도를 빼 회색조로(명암만 유지).
local function tintColorToTarget(origColor, targetColor)
	local _, oSat, oVal = origColor:ToHSV()
	local tHue, tSat = targetColor:ToHSV()
	if tSat < 0.12 then
		return Color3.fromHSV(0, 0, oVal)        -- 무채색 타겟: 회색조(명암만)
	end
	return Color3.fromHSV(tHue, oSat, oVal)       -- 유채색: hue만 교체, 원본 채도·명도 유지
end

local function tintSequenceToTarget(seq, targetColor)
	local kps = {}
	for _, kp in ipairs(seq.Keypoints) do
		kps[#kps + 1] = ColorSequenceKeypoint.new(kp.Time, tintColorToTarget(kp.Value, targetColor))
	end
	return ColorSequence.new(kps)
end

-- VFX 모델 전체(Part / Beam / ParticleEmitter)에 색조 틴트 적용. targetColor=nil이면 원본 유지.
local function tintVFX(model, targetColor)
	if not (model and targetColor) then return end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Color = tintColorToTarget(d.Color, targetColor)
		elseif d:IsA("Beam") or d:IsA("ParticleEmitter") then
			d.Color = tintSequenceToTarget(d.Color, targetColor)
		end
	end
end

-- 모델 복제 + 위치/방향 변환
--   targetDir이 nil이면 회전 유지하고 위치만 평행 이동 (WaterfallUpper)
--   targetDir이 있으면 모델의 흐름축을 targetDir에 맞춰 회전 (WaterFlow)
local function cloneVFX(model, targetPos, targetDir)
	if not model then return nil end
	local clone = model:Clone()
	-- [VFX-NOQUERY] 이 파일 상단에 "시각 효과 (연출용, 기능 없음)"이라고 적어뒀지만
	--   실제로는 CanQuery=true 라 다른 시스템의 raycast 에 지면처럼 잡혔다.
	--   실측 사고: TaggerBotSystem.clampToPlateX 의 지면 raycast 가 이 VFX 를 찍어
	--   블랙홀 조준 Y 가 157(지면은 110~130)이 되고, 포물선이 과사출돼 맵 밖에 착탄.
	--   순수 연출물이므로 모든 raycast 에서 제외한다.
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then d.CanQuery = false end
	end

	-- 원본의 중심
	local origPivot = model:GetPivot()
	local origCenter = origPivot.Position

	if targetDir then
		-- 방향성 정렬: FoamStart→FoamStop이 흐름 방향
		local fA = model:FindFirstChild("FoamStart")
		local fB = model:FindFirstChild("FoamStop")
		local origDir
		if fA and fB then
			origCenter = (fA.Position + fB.Position) / 2
			local v = fB.Position - fA.Position
			origDir = Vector3.new(v.X, 0, v.Z).Unit
		else
			-- fallback: pivot의 LookVector
			local lv = origPivot.LookVector
			origDir = Vector3.new(lv.X, 0, lv.Z).Unit
		end

		local deltaAngle = math.atan2(targetDir.X, targetDir.Z)
		                 - math.atan2(origDir.X, origDir.Z)
		local transform = CFrame.new(targetPos)
		                * CFrame.Angles(0, deltaAngle, 0)
		                * CFrame.new(-origCenter)

		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CFrame = transform * d.CFrame
			end
		end
	else
		-- 회전 유지, 위치만 평행 이동
		local offset = targetPos - origCenter
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CFrame = d.CFrame + offset
			end
		end
	end

	return clone
end

-- WaterfallUpper 클론을 새 위치로 이동 (각 프레임 갱신용)
local function moveWaterfallUpper(clone, targetPos)
	if not clone or not clone.Parent then return end
	local curCenter = clone:GetPivot().Position
	local offset = targetPos - curCenter
	if offset.Magnitude < 0.01 then return end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CFrame = d.CFrame + offset
		end
	end
end

-- ─── Tsunami 발동 ────────────────────────────────────────────
-- _telegraphed: 내부 전용 플래그. 외부 호출(ItemSpawnHandler / TaggerBotSystem)은
--   항상 (player, clickPosition) 2개만 넘기므로 nil → 예고 단계부터 시작한다.
--   예고가 끝나면 자기 자신을 true 로 재호출해 아래 본문을 그대로 태운다.
--   ⚠️ 이 함수는 절대 yield 하면 안 된다. 호출자가 반환 직후에 일을 하기 때문:
--      ItemSpawnHandler:571 이 쿨다운을 기록하고(늦으면 예고 중 연타로 이중 발사),
--      TaggerBotSystem:389 가 itemLastFired 를 찍는다(늦으면 봇 결정 스레드가 멈춘다).
--      그래서 대기는 task.spawn 안에서만 한다.
local function fireTsunami(player, clickPosition, _telegraphed)
	-- 진행 방향: 클릭 위치 → playerbase (수평 평면)
	-- 태거 시선과 무관하게 항상 러너 베이스 쪽으로 흐름
	local direction = FALLBACK_DIRECTION
	local playerbase = findPlayerbase(clickPosition)
	if playerbase then
		local toBase = playerbase.Position - clickPosition
		local flat = Vector3.new(toBase.X, 0, toBase.Z)
		if flat.Magnitude > 0.01 then
			direction = flat.Unit
		end
	else
		warn("⚠️ Tsunami: playerbase를 찾을 수 없음 → fallback +Z 방향 사용")
	end

	-- 메쉬 클론 + 수동 제어를 위한 anchored 설정
	-- ── 🌊 발사 예고 (TSUNAMI-TELEGRAPH) ────────────────────────
	-- 위치는 여기(클론 직전)여야 한다. 아래 스킨 블록의 Rainbow Heartbeat 루프가
	-- `if not (wave and wave.Parent) then Disconnect()` 이라, 클론 후 parent 전에
	-- yield 가 끼면 첫 Heartbeat 에 즉시 끊겨 RainbowTsunami 스킨이 죽는다.
	if not _telegraphed then
		task.spawn(function()
			-- 근접 여부: 발원지 반경 안에 러너(유저/AI)가 있으면 예고를 늘린다
			local waitTime = TELEGRAPH_TIME_FAR
			do
				local near = false
				for _, plr in ipairs(Players:GetPlayers()) do
					if plr:GetAttribute("Role") == "Runner" then
						local ch = plr.Character
						local rt = ch and ch:FindFirstChild("HumanoidRootPart")
						if rt and (rt.Position - clickPosition).Magnitude <= TELEGRAPH_NEAR_RANGE then
							near = true
							break
						end
					end
				end
				if not near then
					for _, m in ipairs(workspace:GetChildren()) do
						if m:GetAttribute("AIRunner") == true then
							local rt = m:FindFirstChild("HumanoidRootPart")
							if rt and (rt.Position - clickPosition).Magnitude <= TELEGRAPH_NEAR_RANGE then
								near = true
								break
							end
						end
					end
				end
				if near then waitTime = TELEGRAPH_TIME_NEAR end
			end

			-- 고스트: 아래 377~379 의 CFrame 공식과 동일하게 배치한다.
			--   (스킨은 입히지 않는다 — ForceField 재질이 텍스처를 덮어 외형 차이가 없고,
			--    스킨 블록을 여기서 또 돌리면 진실이 두 곳이 된다)
			local ghost = tsunamiTemplate:Clone()
			ghost.Name = "TsunamiTelegraph"
			local ghostHalfHeight = ghost.Size.Y / 2
			local gPos = clickPosition + Vector3.new(0, ghostHalfHeight + HOVER_OFFSET, 0)
			ghost.CFrame = CFrame.lookAt(gPos, gPos + direction)
				* CFrame.Angles(0, math.rad(YAW_OFFSET_DEG), 0)
				* CFrame.Angles(0, 0, math.rad(BASE_FORWARD_TILT_DEG))
			local function ghostify(p)
				p.Anchored     = true
				p.CanCollide   = false
				p.CanQuery     = false   -- 조준 raycast 에 안 잡힘 (청사진이 고스트 위로 뜨는 것 방지)
				p.CanTouch     = false
				p.Material     = Enum.Material.ForceField
				p.Transparency = math.max(p.Transparency, 0.5)
				p:SetAttribute("NoContactDown", true)   -- 방어: 어떤 경로로든 접촉 판정 금지
			end
			ghostify(ghost)
			for _, d in ipairs(ghost:GetDescendants()) do
				if d:IsA("LuaSourceContainer") or d:IsA("Sound") then
					d:Destroy()          -- 고스트에서 스크립트 실행/사운드 방지
				elseif d:IsA("BasePart") then
					ghostify(d)
				end
			end
			-- TaggerItems 그룹을 유지해야 ItemMarkerClient 의 마젠타 기둥이 붙는다.
			-- 메시 내부에 서 있으면 뒷면이 안 그려져 고스트 자체가 안 보일 수 있어서,
			-- 화면에 뜨는 기둥이 유일한 단서가 되는 경우가 있다.
			pcall(function() ghost.CollisionGroup = "TaggerItems" end)
			ghost.Parent = workspace
			Debris:AddItem(ghost, waitTime + 0.25)   -- 안전망: 이 스레드가 죽어도 정리됨

			task.wait(waitTime)
			if ghost and ghost.Parent then ghost:Destroy() end

			-- 대기 중 라운드가 끝났으면 발사하지 않는다 (인터미션 중 파도 방지)
			-- 🧪 [TEST 2026-08-30] /spawnfree 로 켠 우회 스위치를 여기서도 존중한다.
			--   ⚠️ ItemSpawnHandler 가드만 풀면 여기서 다시 막힌다 — 두 관문이 짝이다.
			--     릴리즈 전 AllowSpawnOffRound 조건을 양쪽에서 함께 삭제할 것.
			if _G.IsRoundLive and not _G.IsRoundLive() and not _G.AllowSpawnOffRound then return end
			fireTsunami(player, clickPosition, true)
		end)
		return
	end

	local wave = tsunamiTemplate:Clone()
	wave.Anchored   = true   -- 수동 CFrame 제어
	wave.CanCollide = false  -- 지면/플레이어와 물리 충돌 안 함 (raycast + OverlapParams로 처리)

	-- 🎨 색 적용: Rainbow 카드(장착 스킨) 우선 → 없으면 ITEM COLOR 단색/금색(TsunamiColor 속성)
	-- vfxTint: 부가 이펙트(폭포/물흐름)에 색조 틴트로 적용할 색 (nil이면 원본 물색 유지)
	local vfxTint
	do
		local skin = _G.getEquippedSkin and _G.getEquippedSkin(player, "tsunami")
		local skinData = (skin and _G.getSwordSkinData) and _G.getSwordSkinData("tsunami", skin) or nil
		if skin == "RainbowTsunami" and player:GetAttribute("Has_RainbowTsunami") == true then
			-- Rainbow: wave만 Heartbeat hue 순환. VFX는 발사 시점 hue로 고정(순환 안 함).
			wave.TextureID = ""
			wave.Material  = Enum.Material.Neon
			local RunService = game:GetService("RunService")
			local startHue = (os.clock() * 0.13) % 1   -- 발사 시점 hue (발사마다 다른 시작색)
			local hue = startHue
			local conn
			conn = RunService.Heartbeat:Connect(function(dt)
				if not (wave and wave.Parent) then if conn then conn:Disconnect() end return end
				hue = (hue + dt * 0.25) % 1
				wave.Color = Color3.fromHSV(hue, 1, 1)
			end)
			vfxTint = Color3.fromHSV(startHue, 1, 1)    -- VFX는 그 순간 색으로 고정
			print("🌊 Tsunami: Rainbow 순환 (VFX 고정색)")
		elseif skinData and skinData.meshTexture and player:GetAttribute("Has_" .. skin) == true then
			-- 텍스처 스왑 스킨 (예: Lava Tsunami): 웨이브 메시 텍스처 교체 + VFX 색조 틴트
			wave.TextureID = skinData.meshTexture
			if skinData.color then
				vfxTint = skinData.color   -- getSwordSkinData가 이미 Color3로 변환해서 반환
			end
			print("🌊 Tsunami 텍스처 스킨:", skin)
		else
			-- ITEM COLOR: TsunamiColor_Wave 속성이 있을 때만 색칠(없으면 원본 텍스처 물 유지)
			local colorName = player:GetAttribute("TsunamiColor_Wave")
			if colorName then
				local ok, palette = pcall(function()
					return require(game:GetService("ReplicatedStorage"):WaitForChild("NoobColorPalette"))
				end)
				if ok and palette and palette.COLORS[colorName] then
					local cfg = palette.getConfig("tsunami")
					local finishKey = player:GetAttribute("TsunamiMaterial_Wave") or (cfg and cfg.materialDefault)
					palette.applyFinish(wave, finishKey, palette.COLORS[colorName])  -- TextureID="" + Material + Color
					vfxTint = palette.COLORS[colorName]   -- VFX도 같은 색조로 틴트
					print("🌊 Tsunami 색:", colorName, finishKey)
				end
			end
		end
	end

	-- 자식 스크립트 비활성화 (Package 등)
	for _, child in ipairs(wave:GetDescendants()) do
		if child:IsA("Script") or child:IsA("LocalScript") then
			child.Disabled = true
		end
	end

	pcall(function()
		wave.CollisionGroup = "TaggerItems"
	end)
	-- 접촉 다운 면제: 쓰나미는 "휩쓸기(래그돌+넉백)" 전용. 다운은 래그돌 중 다른 아이템 콤보로만.
	wave:SetAttribute("NoContactDown", true)

	local meshHalfHeight = wave.Size.Y / 2
	local meshHalfLength = wave.Size.Z / 2  -- 진행 방향 길이의 절반
	local maxTiltRad     = math.rad(MAX_TILT_DEG)

	-- 메쉬 정면(LookVector = 로컬 -Z = 청사진이 바라보는 방향)을 direction과 정렬
	-- 초기 위치: 클릭 위치 위에 메쉬 절반 + HOVER_OFFSET
	local spawnPos = clickPosition + Vector3.new(0, meshHalfHeight + HOVER_OFFSET, 0)
	wave.CFrame = CFrame.lookAt(spawnPos, spawnPos + direction)
		* CFrame.Angles(0, math.rad(YAW_OFFSET_DEG), 0)
		* CFrame.Angles(0, 0, math.rad(BASE_FORWARD_TILT_DEG))  -- 초기 frame에도 기본 앞쪽 기울기 적용
	wave.Parent = workspace
	-- 조준 레이캐스트 제외용 표식 (ItemSpawnHandler 와 동일 규약).
	-- 이게 없으면 BlackHole/Spear 조준 시 쓰나미 표면이 잡혀 청사진이 물 위로 떠오른다.
	wave:SetAttribute("TaggerSpawnedItem", true)

	-- ─── 시각 효과: WaterfallUpper (발사별 개별 클론, 쓰나미 뒤에 배치) ──────
	-- 컨셉: 폭포에서 쏟아져 나오는 쓰나미. 발사할 때마다 폭포가 spawn 위치 뒤쪽에 같이 생성됨.
	-- BBox 중심을 origin으로 사용해서 (spawnPos 뒤쪽 + Y 보정) 위치로 평행이동.
	local waterfallUpperClone
	local waterfallUpperRef = findVFXModel("WaterfallUpper")
	if waterfallUpperRef and upperBBoxCenter then
		local targetPos = spawnPos
			- direction * VFX_UPPER_BACK_OFFSET
			+ Vector3.new(0, VFX_UPPER_Y_OFFSET, 0)
		local offset = targetPos - upperBBoxCenter
		waterfallUpperClone = waterfallUpperRef:Clone()
		for _, d in ipairs(waterfallUpperClone:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CFrame = d.CFrame + offset
				d.CanQuery = false   -- [VFX-NOQUERY] 연출물 — 다른 시스템 raycast 에서 제외
			end
		end
		waterfallUpperClone.Name = "_TsunamiWaterfallUpper_" .. player.Name
		tintVFX(waterfallUpperClone, vfxTint)  -- 색조 틴트 (vfxTint nil이면 원본 물색)
		waterfallUpperClone.Parent = workspace
		waterfallUpperClone:SetAttribute("TaggerSpawnedItem", true)   -- 조준 제외
		-- 흰 폭포 빔/미스트: 발사 직후 짧게만 → VFX_UPPER_BEAM_DURATION 후 Beam·Emitter 끔 (파도 수명 내내 지속 방지)
		do
			local wfc = waterfallUpperClone
			task.delay(VFX_UPPER_BEAM_DURATION, function()
				if not (wfc and wfc.Parent) then return end
				for _, d in ipairs(wfc:GetDescendants()) do
					if d:IsA("Beam") or d:IsA("ParticleEmitter") then d.Enabled = false end
				end
			end)
		end
		-- 안전망: 빔 종료 + 미스트 잔여(최대 3초) 후 강제 제거
		Debris:AddItem(waterfallUpperClone, VFX_UPPER_BEAM_DURATION + 3.5)
	end

	-- WaterFlow 참조 + 트레일 타이밍
	local waterFlowRef = findVFXModel("WaterFlow")
	local lastFlowSpawn = 0

	-- 동적 lifetime: clickPosition → playerbase 수평 거리 기반 산출
	local targetPos
	if playerbase then
		targetPos = playerbase.Position
	else
		targetPos = clickPosition + direction * 300  -- fallback
	end
	local horizDist = (Vector3.new(targetPos.X, 0, targetPos.Z)
	                 - Vector3.new(clickPosition.X, 0, clickPosition.Z)).Magnitude
	local dynamicLifetime = horizDist / WAVE_SPEED + LIFETIME_BUFFER
	if dynamicLifetime < MIN_LIFETIME then dynamicLifetime = MIN_LIFETIME end
	if dynamicLifetime > MAX_LIFETIME then dynamicLifetime = MAX_LIFETIME end

	print(string.format(
		"🌊 Tsunami fired by %s | dist=%.0f stud | lifetime=%.1fs | dir=(%.2f, %.2f, %.2f)",
		player.Name, horizDist, dynamicLifetime, direction.X, direction.Y, direction.Z))

	-- raycast params: 매 프레임 갱신해서 새로 생긴 장애물도 차단
	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Exclude
	groundParams.IgnoreWater = true

	-- 지면 raycast 필터 갱신: 자기 자신/청사진/불기둥/test_launcher/다른 TaggerItems(다른 파도·통나무·돌)/캐릭터 제외
	-- 폴더를 통째로 넣으면 자손까지 모두 제외됨
	local function refreshGroundFilter()
		local list = {wave}
		local bp = workspace:FindFirstChild("Blueprint_" .. player.Name)
		if bp then table.insert(list, bp) end
		local fp = workspace:FindFirstChild("FirePressurePillars")
		if fp then table.insert(list, fp) end
		local tl = workspace:FindFirstChild("test_launcher")
		if tl then table.insert(list, tl) end
		-- 픽업 상자(PickupContainer) 통째 제외: 지면 레이가 상자를 지형으로 오인해
		-- 파도가 상자 높이로 점프하는 버그 방지 (폴더째 넣으면 자손 파트 전부 제외)
		local pk = workspace:FindFirstChild("PickupContainer")
		if pk then table.insert(list, pk) end
		for _, child in ipairs(workspace:GetChildren()) do
			if child:IsA("BasePart") and child ~= wave and child.CollisionGroup == "TaggerItems" then
				table.insert(list, child)  -- 다른 파도, 떨어진 통나무, 배럴 등
			elseif child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") then
				table.insert(list, child)  -- 플레이어/NPC 캐릭터
			end
		end
		groundParams.FilterDescendantsInstances = list
	end
	refreshGroundFilter()

	-- 상태
	local hitSet = {}
	local elapsed = 0
	local currentPitch = 0
	-- 🛡️ [2026-08-30] 방패에 막히면 잠깐 멈춘다.
	--   [왜] 굴리기류는 방패 앞에서 멈췄다가 3초 뒤 되돌아 굴러간다. 그 '멈춤'이
	--     "내 방패가 막았다"는 유일한 시각 피드백이다. 쓰나미는 그대로 지나가서
	--     차단이 성공해도 화면상으론 아무 일도 없었다(실측 제보).
	--   ⚠️ 영구 정지가 아니다. 파도는 광역기라 러너 하나가 세워버리면 뒤의 러너들이
	--     공짜로 살아남는다(실측 11:29:18 — 차단 0.08초 뒤에도 AIRunner_3 를 때리고 있었다).
	--     방패는 '나를 지키는 것'이지 '파도를 없애는 것'이 아니다.
	local stallUntil = 0
	local STALL_TIME = 1.2   -- 멈춰 있는 시간(초)

	_G.__TsunamiStall = function()   -- detectAndHit 에서 호출
		stallUntil = os.clock() + STALL_TIME
	end

	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not wave or not wave.Parent then
			if conn then conn:Disconnect() end
			_G.__TsunamiStall = nil   -- ⚠️ 다음 파도가 죽은 파도의 함수를 부르지 않도록
			return
		end

		-- 🛡️ 정지 중: 전진도 수명도 멈춘다.
		--   ⚠️ elapsed 를 같이 멈추지 않으면 서 있는 동안 수명이 깎여
		--     파도가 목적지에 못 가고 중간에 사라진다.
		if os.clock() < stallUntil then
			return
		end

		elapsed = elapsed + dt

		local currentPos = wave.Position
		local step = WAVE_SPEED * dt

		-- 1. X/Z 전진
		local nextX = currentPos.X + direction.X * step
		local nextZ = currentPos.Z + direction.Z * step
		local probeCenter = Vector3.new(nextX, currentPos.Y, nextZ)

		-- 2. 앞·뒤 두 지점에서 지면 raycast (필터 갱신: 비행 중 새로 생긴 파도/장애물도 제외)
		refreshGroundFilter()
		local frontHit, backHit = probeGround(probeCenter, direction, meshHalfLength, groundParams)

		local targetY = currentPos.Y
		local targetPitch = currentPitch

		if frontHit and backHit then
			-- 양쪽 다 지면 있음 → 평균 Y + 기울기
			local avgY = (frontHit.Position.Y + backHit.Position.Y) / 2
			targetY = avgY + meshHalfHeight + HOVER_OFFSET
			-- 내리막일수록 nose-down (front가 back보다 낮을수록 양수)
			local heightDiff = backHit.Position.Y - frontHit.Position.Y
			targetPitch = math.atan2(heightDiff, meshHalfLength * 2)
			-- 최대 기울기 제한
			if targetPitch >  maxTiltRad then targetPitch =  maxTiltRad end
			if targetPitch < -maxTiltRad then targetPitch = -maxTiltRad end
		elseif frontHit then
			-- 앞만 잡힘 (절벽 끝 등) → 앞 기준
			targetY = frontHit.Position.Y + meshHalfHeight + HOVER_OFFSET
			targetPitch = 0
		elseif backHit then
			-- 뒤만 잡힘 (앞이 허공) → 뒤 기준, 살짝 nose-down 유지
			targetY = backHit.Position.Y + meshHalfHeight + HOVER_OFFSET
			targetPitch = math.rad(15)
		end
		-- 둘 다 안 잡히면 현재값 유지 (그냥 떨어지지는 않음)

		-- 3. Y / Pitch lerp
		-- Y는 비대칭: 내려갈 때 빠르게 (hill에 붙음), 올라갈 때 매우 느리게
		--   → 앞에 떨어진 통나무/돌/장애물에 raycast가 부딪혀도 위로 안 튀어오름
		local goingDown  = (targetY < currentPos.Y)
		local yRate      = goingDown and Y_LERP_RATE_DOWN or Y_LERP_RATE_UP
		local yAlpha     = math.min(yRate * dt, 1)
		local pitchAlpha = math.min(TILT_LERP_RATE * dt, 1)
		local newY = currentPos.Y + (targetY - currentPos.Y) * yAlpha
		currentPitch = currentPitch + (targetPitch - currentPitch) * pitchAlpha

		-- 4. CFrame 갱신: lookAt(정면 정렬) + Pitch(슬로프 기울기)
		-- lookAt 후 로컬 +X 회전: 양수=정면 위로, 음수=정면 아래로
		-- 내리막 nose-down 위해 -currentPitch
		local nextPos = Vector3.new(nextX, newY, nextZ)
		wave.CFrame = CFrame.lookAt(nextPos, nextPos + direction)
			* CFrame.Angles(0, math.rad(YAW_OFFSET_DEG), 0)
			* CFrame.Angles(0, 0, -currentPitch + math.rad(BASE_FORWARD_TILT_DEG))  -- pitch axis = 로컬 +Z. 기본 앞쪽 기울기 + 슬로프 pitch 합산 (base tilt 부호 반대)

		-- 5. 충돌 감지
		detectAndHit(wave, direction, hitSet)

		-- 5.5 시각 효과: WaterFlow 트레일 (WaterfallUpper는 고정 위치라 매 프레임 갱신 불필요)
		if waterFlowRef and (elapsed - lastFlowSpawn) >= VFX_FLOW_SPAWN_INTERVAL then
			lastFlowSpawn = elapsed
			-- waterflowconnectpart 위치 사용 (없으면 wave 중심으로 fallback)
			local flowSpawnPos = nextPos
			if connectPartLocalCF then
				flowSpawnPos = (wave.CFrame * connectPartLocalCF).Position
			end

			-- 🎯 Ground raycast: WaterFlow 위치에서 바로 아래로 쏴서 실제 hill 표면 찾기
			-- 이렇게 하면 wave의 pitch 상태와 무관하게 항상 hill 경사에 맞춰 배치됨
			local rayOrigin = flowSpawnPos + Vector3.new(0, 50, 0)
			local rayDir = Vector3.new(0, -300, 0)
			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
			rayParams.FilterDescendantsInstances = {wave}
			local groundHit = workspace:Raycast(rayOrigin, rayDir, rayParams)

			local flowClone
			if groundHit then
				-- Ground 위에 배치 + Y 보정
				local groundPos = groundHit.Position + Vector3.new(0, VFX_FLOW_Y_OFFSET_FROM_GROUND, 0)
				flowClone = cloneVFX(waterFlowRef, groundPos, direction)
				if flowClone then
					-- Ground normal에 맞춰 정렬: 로컬 +Y가 normal과 일치하도록 회전
					local up = Vector3.yAxis
					local n = groundHit.Normal
					local rotAxis = up:Cross(n)
					if rotAxis.Magnitude > 0.001 then
						rotAxis = rotAxis.Unit
						local rotAngle = math.acos(math.clamp(up:Dot(n), -1, 1))
						local tiltCF = CFrame.new(groundPos)
							* CFrame.fromAxisAngle(rotAxis, rotAngle)
							* CFrame.new(-groundPos)
						for _, d in ipairs(flowClone:GetDescendants()) do
							if d:IsA("BasePart") then
								d.CFrame = tiltCF * d.CFrame
							end
						end
					end
				end
			else
				-- Fallback: 기존 방식
				flowSpawnPos = flowSpawnPos - Vector3.new(0, VFX_FLOW_Y_OFFSET, 0)
				flowClone = cloneVFX(waterFlowRef, flowSpawnPos, direction)
			end

			if flowClone then
				flowClone.Name = "_TsunamiWaterFlow"
				tintVFX(flowClone, vfxTint)  -- 색조 틴트 (vfxTint nil이면 원본 물색)
				flowClone.Parent = workspace
				flowClone:SetAttribute("TaggerSpawnedItem", true)   -- 조준 제외
				Debris:AddItem(flowClone, VFX_FLOW_LIFETIME)
			end
		end

		-- 6. 종료 조건: playerbase 도달 OR dynamicLifetime 초과
		local distToTarget = (Vector3.new(nextX, 0, nextZ)
		                   - Vector3.new(targetPos.X, 0, targetPos.Z)).Magnitude
		local reachedBase = distToTarget < ARRIVAL_RADIUS
		local timedOut    = elapsed >= dynamicLifetime

		if reachedBase or timedOut then
			conn:Disconnect()
			_G.__TsunamiStall = nil   -- ⚠️ 정상 종료 경로에서도 반드시 치운다(위 조기 종료와 짝)
			print(string.format("🌊 Tsunami end → %s (dist=%.0f, t=%.1fs)",
				reachedBase and "REACHED BASE" or "TIMEOUT", distToTarget, elapsed))
			local fadeOut = TweenService:Create(wave,
				TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{Transparency = 1})
			fadeOut:Play()

			-- 시각 효과 정리: 이 발사의 WaterfallUpper만 (다른 활성 쓰나미는 자기 클론을 따로 가짐)
			if waterfallUpperClone and waterfallUpperClone.Parent then
				for _, d in ipairs(waterfallUpperClone:GetDescendants()) do
					if d:IsA("Beam") or d:IsA("ParticleEmitter") then
						d.Enabled = false
					end
				end
				Debris:AddItem(waterfallUpperClone, VFX_UPPER_FADE_LINGER)
			end
			fadeOut.Completed:Connect(function()
				if wave and wave.Parent then wave:Destroy() end
			end)
		end
	end)

	-- 안전망: dynamicLifetime + 페이드 여유분
	Debris:AddItem(wave, dynamicLifetime + 2)
end

-- 글로벌 노출 (ItemSpawnHandler가 호출)
_G.fireTsunami = fireTsunami
print("✅ TsunamiSystem ready (lookAt-aligned front + dynamic lifetime + arrival detect)")
