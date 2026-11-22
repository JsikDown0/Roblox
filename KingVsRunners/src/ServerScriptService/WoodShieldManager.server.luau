-- WoodShieldManager
-- Touched 연결을 WoodShieldManager 자체 coroutine에서 수행 (use Script 삭제 영향 없음)

local SHIELD_LIFETIME  = 30
local COLLISION_RADIUS = 0.1

local pendingShields = {}  -- use Script에서 등록 → main loop에서 처리
local activeShields  = {}

-- 🗺️ [2026-08-30] 현재 라운드 맵. 방패 방향(flowDir) 계산에 쓴다.
--   [증상] map2 라운드에서 원거리 차단이 전혀 안 됐다(실측 11:41 판).
--     map1 라운드(11:29)에서는 정상 동작 — 맵에 따라 갈렸다.
--   [원인] 아래 flowDir 계산이 workspace 를 훑다가 '첫 번째' 맵의 taggerspawn 에서 break 했다.
--     스왑 OFF 가 기본이라 map1·map2 가 동시에 workspace 에 있고, map2 라운드인데
--     map1 의 taggerspawn 을 잡았다. 두 맵은 Z 로 1500 stud 넘게 떨어져 있어
--     방향이 완전히 다른 곳을 가리켰고 정면 판정을 통과하지 못했다.
--   ⚠️ 이 세션에서 같은 패턴이 세 번째다(CaptureSystem, BarricadeSystem, 여기).
--     RoundSystem:2186 주석의 규칙 — "맵을 이름으로 찾는 코드는 반드시 SetCurrentMap 을 우선 쓸 것".
--   ⚠️ detector 배치도 같은 flowDir 을 쓴다. 즉 map2 에서는 감지 파트도 엉뚱한 방향에 놓여 있었다.
local currentMapFolder = nil
do
	local ev = game:GetService("ReplicatedStorage"):FindFirstChild("SetCurrentMap")
	if ev and ev:IsA("BindableEvent") then
		ev.Event:Connect(function(mapFolder)
			currentMapFolder = mapFolder
		end)
	else
		warn("[WoodShield] SetCurrentMap 이벤트 못 찾음 — 맵 판별이 첫 번째 맵으로 폴백된다")
	end
end

-- use Script에서 호출: queue에 넣기만 함
_G.StartWoodShield = function(shield, timerLabel, player, placeCFrame)
	-- 태거 방향 앞면에 투명 판정 파트 생성 (시각적으로 방패에 딱 막히게)
	local detector = nil
	-- 🛡️ 방패가 향한 방향(= 공격이 날아오는 쪽). 아래 detector 배치와 원거리 판정이 공유한다.
	--   ⚠️ if 블록 밖에 선언해야 등록 테이블에서도 보인다(선언 ≺ 사용).
	local flowDir = nil
	if placeCFrame then
		-- flowDir = 방패에서 태거 쪽(=통나무 오는 쪽). 방패 LookVector는 스킨마다
		-- 앞뒤가 뒤집힐 수 있으므로, taggerspawn 위치를 기준으로 독립 계산.
		-- ⚠️ [2026-08-30] 활성 맵을 최우선으로 본다. 예전엔 workspace 를 훑다 첫 맵에서
		--   break 해서, map2 라운드인데 map1 의 taggerspawn 을 잡는 일이 있었다.
		-- ⚠️ [2026-08-30] 폴백을 '첫 번째'가 아니라 '가장 가까운' 맵으로 한다.
		--   [왜] SetCurrentMap 은 라운드가 시작해야 뜬다. 테스트 하네스(/map2 TP + 라운드 정지)나
		--     부팅 직후엔 currentMapFolder 가 nil 이라 폴백이 그대로 쓰인다.
		--     '첫 번째'로 두면 그 경우 map1 이 항상 뽑혀 원래 버그가 재현된다(실측 12:36 판).
		--   ⚠️ 두 맵은 Z 로 1500 stud 넘게 떨어져 있어 '가장 가까운'이 모호하지 않다.
		--     맵이 겹치게 배치되면 이 전제가 깨지므로 그때는 SetCurrentMap 경로만 믿을 것.
		local shieldPos = shield:GetPivot().Position
		flowDir = placeCFrame.LookVector  -- 기본값(원본 방패)
		local best, bestD = nil, math.huge
		for _, mapFolder in ipairs(workspace:GetChildren()) do
			if mapFolder.Name:lower():find("map") then
				local ts = mapFolder:FindFirstChild("taggerspawn") or mapFolder:FindFirstChild("taggerspawn2")
				if ts then
					if currentMapFolder and mapFolder == currentMapFolder then
						best, bestD = ts, -1   -- 활성 맵이면 즉시 확정
						break
					end
					local d = (ts.Position - shieldPos).Magnitude
					if d < bestD then best, bestD = ts, d end
				end
			end
		end
		if best then
			local d = Vector3.new(best.Position.X - shieldPos.X, 0, best.Position.Z - shieldPos.Z)
			if d.Magnitude > 0.1 then flowDir = d.Unit end
		end
		detector = Instance.new("Part")
		detector.Name      = "_ShieldDetector"
		detector.Size      = Vector3.new(0.2, 7, 14)
		-- 태거 방향으로 15 studs 앞에 배치
		local DETECTOR_OFFSET = 15
		local right = flowDir:Cross(Vector3.new(0,1,0))
		if right.Magnitude < 0.001 then
			right = Vector3.new(0, 0, 1)  -- flowDir가 수직일 때 fallback
		else
			right = right.Unit
		end
		detector.CFrame = CFrame.new(
			shieldPos + flowDir * DETECTOR_OFFSET,
			shieldPos + flowDir * (DETECTOR_OFFSET + 1)
		)
		detector.Anchored      = true
		detector.CanCollide    = false
		detector.CanTouch      = true
		detector.Transparency  = 1  -- 완전 투명 (감지 전용)
		detector.CollisionGroup = "WoodShield"
		detector.Parent = workspace
	end

	table.insert(pendingShields, {
		shield     = shield,
		timerLabel = timerLabel,
		player     = player,
		startTime  = tick(),
		detector   = detector,
		fxCFrame   = detector and detector.CFrame or (placeCFrame or CFrame.new()),  -- FX 방출 위치(실제 막히는 지점)
		-- 🛡️ [2026-08-30] 방패가 향한 방향(= 공격이 날아오는 쪽). 원거리 판정에 쓴다.
		--   ⚠️ 위에서 이미 구한 flowDir 을 그대로 넘긴다. 여기서 다시 계산하면 로직이 두 벌이 되어
		--     한쪽만 고쳐지는 사고가 난다(실제로 한 번 그렇게 썼다가 되돌렸다).
		--   ⚠️ placeCFrame 이 없으면 nil — 그 경우 방향 판정 없이 접촉만 본다(예전 동작).
		facing     = flowDir,
	})
	print("🛡️ 방패 queue 등록:", player.Name)
end

-- 레전더리 방패 방어 성공 시 정면 버스트 FX
-- 서버 :Emit은 클라에 복제 안 되므로, 위치만 보내 각 클라가 로컬 생성+Emit (PunchVfx 패턴)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local shieldBlockEmit = ReplicatedStorage:WaitForChild("ShieldBlockEmit", 5)
local function emitBlockFx(atCFrame, fxType)
	if not shieldBlockEmit then return end
	local pos = (atCFrame or CFrame.new()).Position
	shieldBlockEmit:FireAllClients(pos, fxType)
end

-- 🛡️ 방패가 물리적으로 막는 대상인가. (Touched / 폴링 공용)
--   ⚠️ [2026-08-30] 두 경로가 같은 판정을 쓴다. 예전엔 각자 조건을 갖고 있어
--     새 그룹을 추가하면 한쪽만 고쳐질 구조였다.
--   ⚠️ 톡스박스(ToxBox 그룹)는 여기 없다 — 의도적이다.
--     박스 히트박스와 방패 디텍터가 '둘 다 Anchored' 라 Touched 가 아예 발생하지 않고,
--     폴링은 COLLISION_RADIUS(0.1) 라 중심이 겹쳐야 걸린다. 즉 이 경로로는 못 잡는다.
--     대신 ToxBoxSystem 이 굴리기 직전에 _G.WoodShieldBlockAt 을 직접 부른다
--     (쓰나미·에너지볼·창과 같은 표준 형태).
local BLOCKABLE_GROUPS = {
	["TaggerItems"] = true,
}
local function isBlockablePart(part)
	if not (part and part:IsA("BasePart")) then return false end
	if BLOCKABLE_GROUPS[part.CollisionGroup] then return true end
	return part:GetAttribute("IsTaggerItem") == true
end

-- 차단 처리
local function handleBlock(entry, hitObj)
	if entry.blocked then return end
	entry.blocked = true
	for _, c in ipairs(entry.connections) do c:Disconnect() end

	-- ⚠️ [2026-08-30] hitObj 가 nil 일 수 있다.
	--   원거리 차단(_G.WoodShieldBlocks)은 '막을 실물'이 없다 — 쓰나미·에너지볼은
	--   좌표 판정이라 튕겨낼 파트 자체가 존재하지 않는다.
	--   아래 되돌리기(task.delay 안)도 같은 이유로 hitObj 가드가 이미 있다.
	local vel, angVel
	if hitObj then
		vel    = hitObj.AssemblyLinearVelocity
		angVel = hitObj.AssemblyAngularVelocity
		hitObj.Anchored = true
	end

	local isSkinned = entry.shield:GetAttribute("IsLegendShield") == true
	local fxType = entry.shield:GetAttribute("ShieldBlockFx")
	if fxType == "redtint" then
		-- 스킨 방패지만 빨강 틴트 피드백 (Jade Barrier: 초록 발광부 → 빨강)
		for _, p in ipairs(entry.shield:GetDescendants()) do
			if p:IsA("BasePart") and p.Material == Enum.Material.Neon then
				p.Color = Color3.fromRGB(255, 60, 60)
			end
		end
	elseif isSkinned then
		-- 스킨 방패: 빨강 틴트 스킵(외형 보존). 파티클 FX는 종류가 있을 때만.
		if fxType then
			emitBlockFx(entry.shield:GetPivot(), fxType)
		end
	else
		-- 기본 나무 방패: 빨강 틴트로 차단 피드백
		for _, p in ipairs(entry.shield:GetDescendants()) do
			if p:IsA("BasePart") then p.Color = Color3.fromRGB(255, 100, 100) end
		end
	end

	-- HP 레이블 0/0 + 바 너비 0으로
	for _, desc in ipairs(entry.shield:GetDescendants()) do
		if desc:IsA("TextLabel") and desc.Name ~= "TimerLabel" then
			desc.Text = "0/0"
		end
		if desc:IsA("Frame") and desc.Name == "Bar" then
			desc.Size = UDim2.new(0, 0, 1, 0)
		end
	end

	print("🛡️ Wood Shield 차단!", entry.player.Name)

	-- ⚠️ [2026-08-30] 소멸 지연을 경우에 따라 다르게 준다.
	--   [왜] 3초는 굴리기용이다 — 막은 아이템을 방패에 붙잡아뒀다가 되돌려 굴리는 시간.
	--     원거리 차단은 붙잡을 실물이 없는데 3초를 기다리니 "막았는데 방패가 안 없어진다"로 보였다
	--     (실측 13:41 제보 — 차감이 늦게 느껴진다).
	--   ⚠️ 0 으로 하면 안 된다. 빨강 틴트·0/0 표시가 한 프레임도 안 보이고 사라진다.
	local DESPAWN_DELAY = hitObj and 3 or 0.6
	task.delay(DESPAWN_DELAY, function()
		if entry.shield and entry.shield.Parent then entry.shield:Destroy() end
		if entry.detector and entry.detector.Parent then entry.detector:Destroy() end
		if hitObj and hitObj.Parent then
			task.wait(0.1)
			hitObj.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
			hitObj.Anchored = false
			-- 원래 진행 방향(-X)으로 살짝 밀어줌
			hitObj.AssemblyLinearVelocity = Vector3.new(-100, 10, 0)
		end
	end)

	for i, s in ipairs(activeShields) do
		if s == entry then table.remove(activeShields, i) break end
	end
end

-- 🛡️ [2026-08-30] 원거리 공격 차단 판정 (외부 공용 API).
--   [배경] 방패는 지금까지 Touched + CollisionGroup=="TaggerItems" 두 조건이 모두 참일 때만
--     반응했다. 즉 '굴러와서 물리적으로 부딪히는 것'만 막았다.
--     쓰나미·에너지볼·데몬스피어 등은 좌표 질의로 러너를 직접 집어가므로 방패를 아예 못 봤다.
--   [무엇을 하나] "가해 지점이 방패 앞쪽에 있고 러너가 방패 뒤에 있는가"를 본다.
--     맞으면 방패를 소모하고 true 를 돌려준다. 호출부는 true 면 피해를 건너뛴다.
--   ⚠️ 광역기(폭격·블랙홀)는 호출하지 않는 것으로 구분한다. 여기서 종류를 알 수 없고,
--     알려고 하면 이 함수가 아이템 목록을 들고 있게 되어 결합이 생긴다.
--     "부르면 막힌다"만 보장하고, 무엇을 막을지는 각 시스템이 정한다.
--   ⚠️ 방패는 방향이 있는 물건이다. 뒤에서 온 공격은 막지 않는다(FRONT_DOT).
-- 🛡️ [2026-08-30 개정2] 경로 기반 차단. "공격이 이 지점을 지날 때 방패에 막히는가."
--   [왜 바꿨나] 예전 API 는 '맞는 순간의 가해 위치'를 받았다. 그런데 발사체는 방패를
--     이미 지나친 뒤에 피격자를 때린다(실측: 방패 X=632, 피격 X=610, 볼은 뒤쪽).
--     그 시점을 보면 방패 기준으로 공격이 등 뒤에 있어 판정이 뒤집힌다.
--   [지금] 발사체가 이동하면서 매 구간 이 함수를 부른다. 방패 근처를 지나면 그때 막힌다.
--     피격자를 안 보므로 방패 뒤에 아무도 없어도 막힌다(엄폐물로서 자연스럽다).
--   ⚠️ travelDir 은 공격의 진행 방향. 방패 정면으로 들어오는 것만 막기 위해 쓴다.
--     생략하면 방향을 안 보고 근처를 지나기만 하면 막는다.
local SHIELD_BLOCK_RADIUS = 14   -- 방패가 실제로 가로막는 반경(stud)
local FRONT_DOT = 0.35           -- 대략 ±70도

_G.WoodShieldBlockAt = function(pos, travelDir)
	if not pos then return false end
	for _, s in ipairs(activeShields) do
		if not s.blocked and s.shield and s.shield.Parent and s.facing then
			local sp = s.shield:GetPivot().Position
			local d = Vector3.new(pos.X - sp.X, 0, pos.Z - sp.Z)
			if d.Magnitude <= SHIELD_BLOCK_RADIUS then
				-- 진행 방향이 방패 정면을 향해 들어오는가(= facing 과 반대)
				local ok = true
				if travelDir then
					local td = Vector3.new(travelDir.X, 0, travelDir.Z)
					if td.Magnitude > 0.01 then
						ok = td.Unit:Dot(s.facing) <= -FRONT_DOT
					end
				end
				if ok then
					print(string.format("🛡️ 경로 차단! (%s 의 방패)", s.player and s.player.Name or "?"))
					handleBlock(s, nil)
					return true
				end
			end
		end
	end
	return false
end
-- 🔎 [진단 2026-08-30] 현재 방패 상태를 문자열로 돌려준다 (/atk 진단이 호출).
--   ⚠️ 검증이 끝나면 이 함수와 호출부를 함께 삭제할 것.
_G.DebugShieldState = function(plr)
	for _, s in ipairs(activeShields) do
		if s.player == plr then
			local f = s.facing
			return string.format("활성 | blocked=%s | facing=%s | 방패위치=(%.0f,%.0f)",
				tostring(s.blocked),
				f and string.format("(%.2f,%.2f)", f.X, f.Z) or "❌nil(방향판정 불가)",
				s.shield and s.shield:GetPivot().Position.X or 0,
				s.shield and s.shield:GetPivot().Position.Z or 0)
		end
	end
	return nil
end

-- 🛡️ [2026-08-30 개정2] 엄폐 판정. "방패가 내 앞을 가려주는가."
--   [왜 둘인가] 넘기는 좌표의 성격이 다르다.
--     · WoodShieldBlockAt(발사체 위치, 진행방향) — 발사체가 방패 곁을 지나는가. 반경 14.
--     · WoodShieldBlocks(피격자, 진행방향)      — 방패가 나와 공격 사이에 서 있는가. 반경 60.
--     반경이 다른 이유: 앞은 '스치는가', 뒤는 '가려주는가'라 척도가 다르다.
--   ⚠️ [실측 13:35] 데몬스피어에 경로형(반경 14)을 쓰다가 계속 뚫렸다.
--     피격자가 방패에서 20 stud 떨어져 있어 반경 밖이었기 때문이다.
--     좌표의 의미가 다른데 같은 함수를 쓰면 이런 식으로 조용히 어긋난다.
--   ⚠️ 착탄점이 아니라 '진행 방향'을 쓴다. 범위기는 착탄점이 피격자와 겹칠 수 있어
--     방향이 성립하지 않는다(프드·데몬스피어에서 실제로 그랬다).
local SHIELD_COVER_RADIUS = 60   -- 방패가 엄폐를 제공하는 거리(stud)
-- 🛡️ [2026-08-31] ignoreFacing(=톡스박스) 일 때 쓰는 위치 조건. 기본 0.35 는 ±70도,
--   이 값 0.10 은 ±84도 — 사실상 "방패가 내 등 뒤만 아니면 막힌다".
--   ⚠️ 실측 16:01 에 0.17 로 실패했다. 그걸 통과시키는 선에서 잡은 값이다.
--   ⚠️ 톡스박스에만 적용된다. 쓰나미·창·에너지볼·데몬스피어는 FRONT_DOT(0.35) 그대로다 —
--     한쪽만 관대하게 하려고 분리한 것이니 여기 값을 다른 아이템에 끌어다 쓰지 말 것.
local FRONT_DOT_LOOSE = 0.10

-- 🛡️ [2026-08-31] 세 번째 인자 ignoreFacing — 각도 조건(②)만 건너뛴다.
--   [왜] 방패 facing 은 설치 시 태거스폰 방향(+X)으로 고정된다. 그런데 톡스박스는
--     전진 3 step 뒤 측면 4 step 으로 ±Z 로 굴러온다. 그 구간에서는 방패와 공격이
--     직각이라 d2 가 구조적으로 0 근처에 머문다 — 아무리 잘 서 있어도 -0.35 를 못 넘는다
--     (실측 16:01 — d2 = 0.09, 공격방향 (-0.05, 1.00), 박스 Z 869→883→899→929).
--   ⚠️ 톡스박스에만 켠다. 쓰나미·창·에너지볼·데몬스피어는 전부 +X 에서 오므로
--     각도 조건이 제 역할을 한다. 거기까지 풀면 '한 방향 엄폐물'이라는 성격이 사라진다.
--   ⚠️ 위치 조건(d1)은 그대로 요구한다. 방패 뒤에 있어야 막힌다 — 그건 각도와 무관하게 성립한다.
_G.WoodShieldBlocks = function(victimChar, travelDir, ignoreFacing)
	if not (victimChar and travelDir) then return false end
	local hrp = victimChar:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	local td = Vector3.new(travelDir.X, 0, travelDir.Z)
	if td.Magnitude < 0.01 then return false end
	td = td.Unit

	local any = false
	for _, s in ipairs(activeShields) do
		if not s.blocked and s.shield and s.shield.Parent and s.facing then
			any = true
			local sp = s.shield:GetPivot().Position
			local toShield = Vector3.new(sp.X - hrp.Position.X, 0, sp.Z - hrp.Position.Z)
			if toShield.Magnitude >= 0.1 and toShield.Magnitude <= SHIELD_COVER_RADIUS then
				-- ① 방패가 '공격이 오는 쪽'에 있는가 (= 진행 방향의 반대편)
				-- ② 그 방패가 공격을 정면으로 받는가  (ignoreFacing 이면 생략)
				local d1 = toShield.Unit:Dot(-td)
				local d2 = td:Dot(s.facing)
				local need = ignoreFacing and FRONT_DOT_LOOSE or FRONT_DOT
				if d1 >= need and (ignoreFacing or d2 <= -FRONT_DOT) then
					print(string.format("🛡️ 엄폐 차단! (%s 의 방패, 거리 %.0f%s) ← %s",
						s.player and s.player.Name or "?", toShield.Magnitude,
						ignoreFacing and ", 각도무시" or "", victimChar.Name))
					handleBlock(s, nil)
					return true
				end
				-- 🔎 [진단 2026-08-30] 실패 이유를 남긴다. 조용히 false 를 돌려주면
				--   "왜 안 막히지"를 매번 추측으로 좁혀야 한다(실측에서 세 번 그랬다).
				--   ⚠️ 검증이 끝나면 이 줄은 지울 것.
				-- ⚠️ [2026-08-31] 피격자 이름을 반드시 함께 찍는다. 없으면 이 줄이 내 것인지
				--   AI 러너 것인지 구분이 안 돼 판을 통째로 날린다(실측 15:19 / 15:33 두 판).
				-- ⚠️ [2026-08-31] 방패·피격자 좌표도 같이 찍는다. dot 값만으로는 기하를
				--   재구성할 수 없어 "왜 d1 이 낮았나"를 매번 추측해야 했다.
				warn(string.format("[WoodShield] 엄폐 실패 ← %s | 거리 %.0f | 방패가앞쪽? %.2f(≥%.2f) | 정면받나? %.2f(%s) | facing=(%.2f,%.2f) 공격방향=(%.2f,%.2f) | 방패(%.0f,%.0f) 나(%.0f,%.0f)",
					victimChar.Name, toShield.Magnitude, d1, need, d2,
					ignoreFacing and "무시됨" or string.format("≤%.2f", -FRONT_DOT),
					s.facing.X, s.facing.Z, td.X, td.Z,
					sp.X, sp.Z, hrp.Position.X, hrp.Position.Z))
			else
				warn(string.format("[WoodShield] 엄폐 실패 ← %s | 거리 %.0f — 반경 %d 밖",
					victimChar.Name, toShield.Magnitude, SHIELD_COVER_RADIUS))
			end
		end
	end
	if not any then
		warn(string.format("[WoodShield] 엄폐 실패 ← %s — 활성 방패 없음(이미 소모됐거나 미설치)", victimChar.Name))
	end
	return false
end

-- ── 메인 루프: WoodShieldManager 자체 coroutine ──────────────
while true do
	task.wait(0.05)  -- 50ms = 20 FPS 폴링

	-- 1. pendingShields → activeShields 이동 + Touched 연결 (이 coroutine에서)
	for i = #pendingShields, 1, -1 do
		local p = table.remove(pendingShields, i)
		if not (p.shield and p.shield.Parent) then continue end

		local entry = {
			shield      = p.shield,
			timerLabel  = p.timerLabel,
			player      = p.player,
			startTime   = p.startTime,
			blocked     = false,
			connections = {},
			detector    = p.detector,
			fxCFrame    = p.fxCFrame,
			-- ⚠️ [2026-08-30] pendingShields 에 필드를 추가하면 여기도 반드시 복사할 것.
			--   entry 는 새 테이블이라 p 의 필드가 자동으로 따라오지 않는다.
			--   (facing 을 빠뜨려 원거리 차단이 통째로 동작하지 않았다 — 실측)
			facing      = p.facing,
		}

		-- CollisionGroup 재확인 + Touched 연결
		local function connectTouched(part)
			local conn = part.Touched:Connect(function(hit)
				if entry.blocked then return end
				if not (hit and hit.Parent) then return end
				if not isBlockablePart(hit) then return end
				print("🔥 방패 Touched! hit:", hit.Name, "CG:", hit.CollisionGroup)
				handleBlock(entry, hit)
			end)
			table.insert(entry.connections, conn)
		end

		for _, part in ipairs(p.shield:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CollisionGroup = "WoodShield"
				-- Touched는 detector에서만 처리 (방패 파트에는 연결 안 함)
			end
		end

		-- detector에만 Touched 연결
		if p.detector then
			connectTouched(p.detector)
		end

		table.insert(activeShields, entry)
		print("🛡️ 방패 활성화 완료 / 플레이어:", p.player.Name)
	end

	-- 2. 활성 방패 타이머 + 폴링 감지
	for i = #activeShields, 1, -1 do
		local s = activeShields[i]
		if not (s.shield and s.shield.Parent) then
			for _, c in ipairs(s.connections) do c:Disconnect() end
			table.remove(activeShields, i)
			continue
		end

		local elapsed   = tick() - s.startTime
		local remaining = math.max(0, math.ceil(SHIELD_LIFETIME - elapsed))

		-- 타이머 텍스트
		if s.timerLabel and s.timerLabel.Parent then
			s.timerLabel.Text = remaining .. "s"
			if remaining <= 5 then
				s.timerLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
			elseif remaining <= 10 then
				s.timerLabel.TextColor3 = Color3.fromRGB(255, 160, 60)
			else
				s.timerLabel.TextColor3 = Color3.fromRGB(255, 220, 80)
			end
		end

		-- 30초 소멸
		if elapsed >= SHIELD_LIFETIME then
			print("⏱️ Wood Shield 소멸:", s.player.Name)
			for _, c in ipairs(s.connections) do c:Disconnect() end
			s.shield:Destroy()
			if s.detector and s.detector.Parent then s.detector:Destroy() end
			table.remove(activeShields, i)
			continue
		end

		-- 폴링 감지 (Touched 보조 + 통과 대비)
		if not s.blocked then
			local shieldCenter = s.shield:GetPivot().Position
			for _, obj in ipairs(workspace:GetDescendants()) do
				if isBlockablePart(obj) then
					local dist = (obj.Position - shieldCenter).Magnitude
					if dist < COLLISION_RADIUS then
						print("🎯 폴링 감지! obj:", obj.Name, "dist:", math.floor(dist*10)/10)
						handleBlock(s, obj)
						break
					end
				end
			end
		end
	end
end
