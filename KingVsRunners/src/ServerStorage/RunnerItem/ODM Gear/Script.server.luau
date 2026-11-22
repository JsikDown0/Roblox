-- ODM Gear 서버 로직: 3회 충전식 + 정적/동적 타겟 부착 지원
local Tool = script.Parent
local RM = Tool:WaitForChild("RemoteEvent")
local RunService = game:GetService("RunService")
local BeltTemplate = Tool.ODM_Belt
BeltTemplate:WaitForChild("Handle")

-- ── ODM_Belt 모든 부품을 Handle에 명시적으로 weld ───────
-- (qPerfectionWeld가 Tool.Handle을 못 찾아 잘못된 부품에 weld하는 버그 우회)
-- ⚠️ 이 용접은 뺄 수 없다. Model 안 파츠들은 Model 내부의 '다른 Handle' 에만 묶여
--    있고, 바깥 Accessory Handle 과는 여기서 만드는 ODMWeld 로만 연결된다.
local function weldBeltToHandle(belt)
	local handle = belt:FindFirstChild("Handle")
	if not handle then return end
	for _, desc in ipairs(belt:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = false
			if desc ~= handle and not desc:FindFirstChild("ODMWeld") then
				local w = Instance.new("WeldConstraint")
				w.Name = "ODMWeld"
				w.Part0 = handle
				w.Part1 = desc
				w.Parent = desc
			end
		end
	end
	handle.Anchored = false
end

-- 🎒 [구조변경 2026-09-02] 원본은 '템플릿'으로만 두고, 장착할 때마다 복제해 입힌다.
--   [증상] 장착해도 기동장치 80파츠가 캐릭터에서 971 stud 떨어진 채였다.
--     Handle 은 몸통에서 1.8 stud 로 정상 부착이고 ODMWeld 도 있는데 안 따라왔다.
--   [원인] 로그의 "Accessory is already being worn by another character" 가 답이다.
--     같은 Accessory 인스턴스를 여러 캐릭터가 돌려 썼다(해제를 Parent = nil 로만 처리).
--     부착이 실패하면 Handle 만 캐릭터 어셈블리에 들어가고 Model 파츠는 못 들어간다.
--     WeldConstraint 는 같은 어셈블리 안에서만 작동하므로 용접이 있어도 무의미해진다.
--   [왜 '예전엔 됐다가 어느샌가'인가] 인스턴스를 재사용하니 라운드·리스폰이 쌓일수록
--     소유권 충돌이 누적된다. 처음 몇 번은 되다가 어느 시점부터 영구히 실패한다.
--   [해결] 매번 새 복제본을 입힌다. 충돌이 원천적으로 사라지고, 로블록스 표준
--     부착(BodyBackAttachment)을 그대로 쓰므로 위치·회전을 우리가 계산할 필요가 없다.
--   ⚠️ Unequipped 에서 반드시 파괴한다("켜는 코드에는 끄는 코드를 같이").
--   ⚠️ 위치 보정(PivotTo)은 넣지 않는다. 템플릿에서 Model 은 이미 Handle 옆
--     1.2 stud 에 정상 배치돼 있다(실측). 문제는 위치가 아니라 소유권이었다.
BeltTemplate.Parent = nil   -- 원본은 착용하지 않는다. 복제 원본으로만 보관
local activeBelt = nil      -- 지금 입고 있는 복제본

-- 충전 초기화 (인스턴스 최초 생성 시에만)
local MAX_CHARGES = 3
if Tool:GetAttribute("Charges") == nil then
	Tool:SetAttribute("Charges", MAX_CHARGES)
end
Tool:SetAttribute("MaxCharges", MAX_CHARGES)

-- 장착 시 등에 Belt 표시
-- 🎒 [2026-09-02] ODM_Belt 는 Model 이 아니라 Accessory 다.
--   ⚠️ PivotTo·수동 몸통 용접을 쓰면 안 된다. 시도했다가
--     "PivotTo is not a valid member of Accessory" 로 스크립트가 죽었다(실측 13:39).
--   [정상 경로] Handle 에 BodyBackAttachment 가 있으므로, Humanoid:AddAccessory 로
--     넣으면 엔진이 캐릭터의 같은 이름 Attachment 를 찾아 자동으로 용접한다.
--   ⚠️ Handle 은 Transparency 1 이다(보이지 않는 앵커). 실제 기동장치 본체는
--     Handle > Model 안의 파츠들이며, weldBeltToHandle 이 그걸 Handle 에 묶는다.
Tool.Equipped:Connect(function()
	local char = Tool.Parent
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (char and hum) then return end

	-- 이전 복제본이 남아 있으면 먼저 치운다(중복 착용 방지)
	if activeBelt then activeBelt:Destroy() ; activeBelt = nil end

	local belt = BeltTemplate:Clone()
	local handle = belt:FindFirstChild("Handle")

	-- 🎒 [구조변경 2026-09-02 #2] 부착 '뒤에' 최종 좌표로 직접 배치하고 나서 용접한다.
	--   [왜 이 순서인가] 앞선 시도들이 전부 실패했다. 실측으로 반증된 것:
	--     · 위치 오프셋 문제 → 템플릿은 이미 정상 배치였다(Model 이 Handle 옆 1.2 stud)
	--     · Accessory 소유권 문제 → 복제로 AddAccessory 는 성공했는데도 982 stud 떨어졌다
	--     · 끊어진 ODMWeld → 템플릿의 ODMWeld 는 0개였다(런타임에 새로 만들어진다)
	--     남은 사실: 용접을 만드는 시점의 파츠 위치가 최종 위치와 무관하고,
	--     Accessory 부착이 Handle 만 옮기고 파츠를 끌고 가지 않는다.
	--   [해결] 부착 전에 Handle 기준 상대 위치를 기록해 두고, 부착이 끝난 뒤
	--     Handle 의 '최종' CFrame 기준으로 다시 배치한 다음 용접한다.
	--     월드 좌표가 확정된 상태에서 묶으므로 엔진 동작에 의존하지 않는다.
	--   ⚠️ 오프셋은 복제본 자신에서 뽑는다. 템플릿과 파츠를 짝지을 필요가 없다.
	local offs = {}
	if handle then
		for _, d in ipairs(belt:GetDescendants()) do
			if d:IsA("BasePart") and d ~= handle then
				offs[d] = handle.CFrame:ToObjectSpace(d.CFrame)
				d.Anchored = false
				-- 🧍 [버그수정 2026-09-02] 장착 순간 캐릭터가 뒤로 튕기는 문제.
				--   [증상] ODM 을 들면 캐릭터가 뒤쪽으로 순간이동한 뒤 기어가 붙었다.
				--   [원인] Model 안 Handle 2개가 CanCollide=true 였다(나머지 79개는 false).
				--     그 파트가 캐릭터 몸속에 생성되면 물리 엔진이 겹침을 해소하려고
				--     캐릭터를 밀어낸다 = 뒤로 튕김.
				--   [해결] 복제본에서만 끈다. 장식용 파츠라 충돌이 필요 없다.
				--   ⚠️ 템플릿(ServerStorage)은 건드리지 않는다. 원본을 바꾸면 다른 용도
				--     (프리뷰·전시 등)에서 의도가 달라질 수 있다.
				d.CanCollide = false
				d.CanQuery = false   -- 레이캐스트에도 안 걸리게(지면 판정 오염 방지)
			end
		end
		handle.Anchored = false
		handle.CanCollide = false
	end

	-- ⚠️ [버그수정 2026-09-02] Parent 대입과 AddAccessory 를 같이 쓰면 안 된다.
	--   [증상] 장착할 때마다 "AddAcessory failed: Accessory is already being worn
	--     by another character." 가 떴다. 벨트는 정상 부착되는데 오류만 났다.
	--   [원인] Accessory 를 Humanoid 가 있는 캐릭터에 Parent 로 넣으면 로블록스가
	--     그 순간 자동으로 용접한다 = 이미 '착용' 상태다. 그 뒤 AddAccessory 를
	--     부르면 "이미 착용 중"으로 거부된다. 내가 만든 자충수였다.
	--   [해결] AddAccessory 만 쓴다. 그 함수가 부모 설정까지 알아서 한다.
	local ok, err = pcall(function() hum:AddAccessory(belt) end)
	if not ok then
		warn("🎒 [ODM] AddAccessory 실패: " .. tostring(err))
		belt.Parent = char   -- 폴백: 그래도 캐릭터 밑에는 둔다
	end
	activeBelt = belt

	-- 부착이 끝난 다음 프레임에 재배치 + 용접
	--   ⚠️ 그 한 프레임 동안 파츠가 '아직 옮겨지기 전 좌표'에 보인다. 몸에서 멀리
	--     떨어진 곳에 번쩍 나타났다 사라지는 것처럼 읽히므로, 배치가 끝날 때까지 숨긴다.
	local hidden = {}
	for part in pairs(offs) do
		hidden[part] = part.LocalTransparencyModifier
		part.LocalTransparencyModifier = 1
	end

	task.defer(function()
		if not (belt.Parent and handle and handle.Parent) then return end
		for part, off in pairs(offs) do
			if part.Parent then
				part.CFrame = handle.CFrame * off          -- ① 최종 위치로 배치
				if not part:FindFirstChild("ODMWeld") then  -- ② 그 자리에서 용접
					local w = Instance.new("WeldConstraint")
					w.Name = "ODMWeld"
					w.Part0 = handle
					w.Part1 = part
					w.Parent = part
				end
				part.LocalTransparencyModifier = hidden[part] or 0   -- ③ 다시 보이게
			end
		end
	end)
end)
Tool.Unequipped:Connect(function()
	-- ⚠️ 파괴한다. Parent = nil 로만 두면 '다른 캐릭터가 착용 중' 상태가 남아
	--   다음 부착이 실패한다 — 이 버그의 원인이었다.
	if activeBelt then activeBelt:Destroy() ; activeBelt = nil end
end)

local MOVE_SPEED = 50
local ARRIVAL_RADIUS = 5      -- 도착 판정 거리
local MAX_TRAVEL_TIME = 5     -- 최대 매달림 시간 (안전망)

-- ───────────────────────────────────────────────────────────────
-- Tool destroy 경로: charges가 0이 되면 "현재 진행 중인 grapple이 자연
-- 종료(도착/점프/타임아웃)될 때까지 대기"한 다음 destroy.
-- 이렇게 해야:
--   1) 마지막 grapple이 짤리지 않고 끝까지 진행됨
--   2) cleanup이 자연 호출되어 Grapple_BV가 안전하게 제거됨
--   3) Tool destroy로 script 죽기 전에 BV 정리가 완료됨
-- ───────────────────────────────────────────────────────────────
local destroyScheduled = false
local isGrappling = false  -- 현재 grapple이 진행 중인지
local activeRoot = nil     -- 진행 중 grapple의 player root (HRP) 참조 (belt-and-suspenders용)

local function scheduleToolDestroy()
	if destroyScheduled then return end
	destroyScheduled = true
	task.spawn(function()
		-- 진행 중 grapple이 자연 종료될 때까지 대기 (최대 MAX_TRAVEL_TIME 안에 cleanup 보장)
		while isGrappling do
			task.wait(0.1)
		end
		-- 자연 종료 후 짧은 버퍼 (시각/사운드 마무리)
		task.wait(0.3)
		-- 안전망: 그래도 HRP에 Grapple_BV 남아있으면 직접 제거
		if activeRoot and activeRoot.Parent then
			local bv = activeRoot:FindFirstChild("Grapple_BV")
			if bv then bv:Destroy() end
		end
		if Tool and Tool.Parent then
			-- Tool 외부에 남는 잔여물 정리:
			--   1) 캐릭터에 옮겨진 ODM_Belt (Equipped 이벤트로 Character의 child가 됨)
			--   2) PlayerGui의 GrappleChargeUI는 클라이언트 측에서 GrappleUIWatchdog가
			--      Tool removal을 감지해서 정리 (서버에서 PlayerGui 접근은 replication 미반영)
			local toolParent = Tool.Parent
			if toolParent:FindFirstChildOfClass("Humanoid") then
				-- 장착 중: Tool.Parent = Character → Belt도 Character의 child
				local beltOnChar = toolParent:FindFirstChild("ODM_Belt")
				if beltOnChar then beltOnChar:Destroy() end
			end
			print("🪝 ODM Gear destroy (charges depleted)")
			Tool:Destroy()
		end
	end)
end

Tool:GetAttributeChangedSignal("Charges"):Connect(function()
	if (Tool:GetAttribute("Charges") or 0) <= 0 then
		scheduleToolDestroy()
	end
end)
-- Tool 초기화 시점에 이미 0인 경우 대비
if (Tool:GetAttribute("Charges") or 0) <= 0 then
	scheduleToolDestroy()
end

-- 와이어 + anchor 생성. dynamicTarget이 주어지면 거기에 weld됨
local function makeBeams(targetCFrame, root, dynamicTarget)
	local anchorpart = Instance.new("Part")
	anchorpart.Size = Vector3.new(1, 1, 1)
	anchorpart.Shape = Enum.PartType.Ball
	anchorpart.CFrame = targetCFrame
	anchorpart.CanCollide = false
	anchorpart.Massless = true
	anchorpart.Transparency = 1  -- 끝점은 시각적으로 안 보이게 (와이어가 끝나는 위치 역할)
	anchorpart.Anchored = (dynamicTarget == nil)  -- 정적이면 anchored
	anchorpart.Parent = workspace

	if dynamicTarget then
		-- 움직이는 타겟에 부착 (태거 아이템 등)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = anchorpart
		weld.Part1 = dynamicTarget
		weld.Parent = anchorpart
	end

	local attachE = Instance.new("Attachment", anchorpart)
	local attachL = Instance.new("Attachment", root)
	local attachR = Instance.new("Attachment", root)
	local attachC = Instance.new("Attachment", root)

	attachC.WorldCFrame = root.CFrame
	attachE.WorldCFrame = anchorpart.CFrame
	attachL.WorldCFrame = root.CFrame - (root.CFrame.XVector * 1.5)
	attachR.WorldCFrame = root.CFrame + (root.CFrame.XVector * 1.5)

	local beamL = script.Beam:Clone()
	local beamR = script.Beam:Clone()
	beamL.CurveSize0 = 10
	beamR.CurveSize1 = 10
	beamL.Parent = attachL
	beamR.Parent = attachR

	beamL.Attachment0, beamL.Attachment1 = attachR, attachE
	beamR.Attachment0, beamR.Attachment1 = attachL, attachE

	return anchorpart, attachE, attachL, attachR, beamL, beamR
end

RM.OnServerEvent:Connect(function(player, root, target, hitPart, humanoid)
	-- 검증
	if not Tool.Enabled then return end
	-- ⚠️ [ODM-DOUBLEFIRE] Enabled 를 여기서 즉시 내린다(차감·사운드보다 먼저).
	--   예전엔 162행에서 내렸는데, 그 사이에 같은 프레임의 두 번째 요청이
	--   150행 검사를 통과해 2연발이 났다. 서버 이벤트는 프레임 단위로 묶여 들어온다.
	--   결과가 2연발로 끝나지 않는 이유:
	--     아래 cleanup 은 '자기 발사분'만 안다. 1번 cleanup 이 2번이 만든
	--     Grapple_BV 를 지우면, 2번 cleanup 은 지울 대상을 못 찾고 끝난다.
	--     그러면 BodyVelocity 가 살아남아 캐릭터가 영원히 그 방향으로 밀린다.
	--   → 진입을 막으면 두 증상이 함께 사라진다.
	Tool.Enabled = false

	local function abort()
		-- 검증 실패로 되돌릴 때는 잠금을 풀어준다(충전은 아직 안 깎았다).
		if Tool and Tool.Parent then Tool.Enabled = true end
	end
	if not root or not root.Parent then abort() return end
	if not humanoid or humanoid.Health <= 0 then abort() return end
	local charges = Tool:GetAttribute("Charges") or 0
	if charges <= 0 then abort() return end

	-- 충전 차감
	Tool:SetAttribute("Charges", charges - 1)
	-- [CONSUMABLE-ONUSE] 발사 확정 지점(root/humanoid/잔탄 가드 통과 후).
	--   player 는 RM.OnServerEvent(148행) 의 첫 인자로 이 범위에 있다.
	--   3충전을 다 써도 MarkConsumableUsed 는 라운드당 1회만 유효 → 인벤은 1개만 빠진다.
	if _G.MarkConsumableUsed then _G.MarkConsumableUsed(player, "ODM Gear") end

	-- 성공 발사 사운드 (3D 위치 기반, 플레이어 위치에서 재생)
	local successSound = Instance.new("Sound")
	successSound.SoundId = "rbxassetid://123809773739377"
	successSound.Volume = 1
	successSound.Parent = root
	successSound:Play()
	game:GetService("Debris"):AddItem(successSound, 5)

	-- 동적 부착 결정: hitPart가 anchored=false인 BasePart면 그것에 weld
	-- (지형, 벽, 정적 모델은 anchored=true라 정적 anchor 사용)
	local dynamicTarget = nil
	if hitPart and hitPart:IsA("BasePart") and not hitPart.Anchored then
		dynamicTarget = hitPart
	end

	local ank, atE, atL, atR, bL, bR = makeBeams(target, root, dynamicTarget)

	-- 정리 함수 (한 번만 실행 보장)
	local cleaned = false
	local heartConn, jumpConn = nil, nil
	-- [ODM-DOUBLEFIRE] 이번 발사가 만든 BodyVelocity 를 직접 들고 있는다.
	--   이름(FindFirstChild "Grapple_BV")으로 찾으면 발사가 겹쳤을 때
	--   남의 것을 지우고 자기 것은 못 지워 영구 전진이 남는다.
	local myVelocity = nil
	local function cleanup()
		if cleaned then return end
		cleaned = true
		if heartConn then heartConn:Disconnect() end
		if jumpConn then jumpConn:Disconnect() end
		for _, inst in ipairs({ank, atE, atL, atR, bL, bR}) do
			if inst and inst.Parent then inst:Destroy() end
		end
		if root and root.Parent then
			-- 자기 것을 우선 제거하고, 이름 검색은 안전망으로만 남긴다.
			if myVelocity and myVelocity.Parent then myVelocity:Destroy() end
			local v = root:FindFirstChild("Grapple_BV")
			if v then v:Destroy() end
		end
		-- Tool이 destroy 중일 때 호출되면 에러날 수 있으므로 보호
		if Tool and Tool.Parent then
			Tool.Enabled = true
		end
		-- grapple 종료 신호 → scheduleToolDestroy가 대기 중이면 풀림
		isGrappling = false
		if activeRoot == root then activeRoot = nil end
	end

	-- grapple 시작 표시 (scheduleToolDestroy가 이 grapple이 끝날 때까지 대기하게 함)
	isGrappling = true
	activeRoot = root

	-- BodyVelocity로 끌어당김 (Heartbeat마다 anchor 위치 추적)
	local velocity = Instance.new("BodyVelocity")
	velocity.Name = "Grapple_BV"
	velocity.MaxForce = Vector3.new(999999, 999999, 999999)
	velocity.P = 50000
	velocity.Velocity = Vector3.new(0, 0, 0)
	velocity.Parent = root
	myVelocity = velocity   -- [ODM-DOUBLEFIRE] cleanup 이 자기 것을 확실히 지우도록

	-- 점프로 중단 (GrappleHook이 사용하는 Humanoid.Jumping 이벤트 방식)
	-- Humanoid.Changed("Jump")는 property 변화에 fire되어 점프 직후 fire한 grapple이
	-- 점프 종료 신호(true→false)에 잘못 캔슬되는 버그가 있었음.
	-- Humanoid.Jumping은 점프 액션 자체에 fire되어 더 명확함 (active=true: 점프 시작).
	-- 추가로 grace period로 fire 직후 0.3초간 점프 잔여 완전 무시.
	local grappleStartTime = tick()
	local JUMP_GRACE = 0.3
	jumpConn = humanoid.Jumping:Connect(function(active)
		if active and (tick() - grappleStartTime) > JUMP_GRACE then
			cleanup()
		end
	end)

	-- 매 프레임 anchor 추적 (정적이든 동적이든 동일하게 처리)
	-- + overshoot 감지: 한번 가까이 갔다가 다시 멀어지면 통과로 간주
	local minDist = math.huge
	heartConn = RunService.Heartbeat:Connect(function()
		if not ank.Parent or not root.Parent then
			cleanup()
			return
		end
		local dir = ank.Position - root.Position
		local dist = dir.Magnitude

		-- 1) 정상 도착 판정 (직접 ARRIVAL_RADIUS 안 들어옴)
		if dist < ARRIVAL_RADIUS then
			cleanup()
			return
		end

		-- 2) Overshoot 판정: 최근까지 가까이 갔는데 (< 2x ARRIVAL_RADIUS) 
		--    현재 거리가 그 최소치보다 5스터드 이상 멀어졌으면 통과한 것으로 간주
		if minDist < ARRIVAL_RADIUS * 2 and dist > minDist + ARRIVAL_RADIUS then
			cleanup()
			return
		end
		if dist < minDist then
			minDist = dist
		end

		velocity.Velocity = dir.Unit * MOVE_SPEED
	end)

	-- 안전망: 너무 오래 매달리면 자동 종료
	task.delay(MAX_TRAVEL_TIME, cleanup)
end)

print("✅ ODM Gear Server ready (3 charges, dynamic attach)")
