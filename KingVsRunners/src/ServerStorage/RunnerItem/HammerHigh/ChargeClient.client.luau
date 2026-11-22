-- HammerHigh 타겟 조준 슬램 — 클라
-- 아이콘 클릭 → 조준 모드: 화면 터치/마우스 위치에 청사진 경계원 표시(착지 예고).
-- 떼면 그 지점으로 도약 슬램 발동. 서버가 좌표를 다시 검증(사거리·벽·castle).
-- 슬램(도약~착지) 동안 무기 전환/해제 금지(백팩 잠금).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UIS = game:GetService("UserInputService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

local Tool = script.Parent
local SlamRemote = Tool:WaitForChild("SlamRemote")

local AIM_RANGE      = 55     -- 서버와 동일 (조준 최대 사거리)
local SLAM_RADIUS    = 16     -- 서버와 동일 (경계원 반경)
local SLAM_COOLDOWN  = 6      -- 서버와 동일 (HammerHighScript SLAM_COOLDOWN)

local equipped = false
local onCooldown = false
local cooldownUntil = 0   -- 쿨 만료 시각(os.clock). 해제/재장착과 무관하게 유지 — 표시용 루프가 죽어도 진실은 이 값
local aiming = false          -- 조준 모드 중
local isSlamming = false      -- 도약~착지 중 (무기 전환/해제 금지)

-- ── 백팩 잠금 (무기 스왑 차단) ───────────────────────────────
local function setBackpack(enabled)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, enabled)
	end)
end

-- ── 버튼 UI ──────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "HammerSlamGui"
gui.ResetOnSpawn = true  -- 사망 리스폰 시 자동 정리 (UI 잔재 방지)
gui.IgnoreGuiInset = true
gui.DisplayOrder = 18
gui.Enabled = false
gui.Parent = playerGui

local btn = Instance.new("TextButton")
btn.Name = "SlamButton"
btn.AnchorPoint = Vector2.new(1, 1)
btn.BackgroundColor3 = Color3.fromRGB(90, 70, 50)
btn.BackgroundTransparency = 1
btn.AutoButtonColor = false
btn.Text = "슬램"
btn.TextScaled = true
btn.Font = Enum.Font.GothamBold
btn.TextColor3 = Color3.fromRGB(255, 240, 220)
btn.Active = true
btn.Parent = gui

-- 키 힌트 "F" (DiveSlot.KeyHint와 동일 스타일 · 모바일에서도 표시)
do
	local hint = Instance.new("TextLabel")
	hint.Name = "KeyHint"
	hint.Text = "F"
	hint.AnchorPoint = Vector2.new(1, 0)
	hint.Position = UDim2.new(0.96, 0, 0.04, 0)
	hint.Size = UDim2.new(0.32, 0, 0.32, 0)
	hint.BackgroundColor3 = Color3.fromRGB(15, 20, 31)
	hint.BackgroundTransparency = 0.2
	hint.BorderSizePixel = 0
	hint.TextColor3 = Color3.new(1, 1, 1)
	hint.Font = Enum.Font.GothamBlack
	hint.TextScaled = true
	hint.ZIndex = 4
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = hint
	local s = Instance.new("UIStroke")
	s.Thickness = 1.5; s.Color = Color3.fromRGB(255, 190, 60); s.Parent = hint
	hint.Parent = btn
	-- 키보드 입력 가능할 때만 표시 (DiveSlotClient와 동일 규칙)
	local _uis = game:GetService("UserInputService")
	local function updateHintVisibility()
		hint.Visible = not (_uis.TouchEnabled and not _uis.KeyboardEnabled)
	end
	updateHintVisibility()
	_uis:GetPropertyChangedSignal("KeyboardEnabled"):Connect(updateHintVisibility)
	_uis:GetPropertyChangedSignal("TouchEnabled"):Connect(updateHintVisibility)
end

-- 디바이스별 스킬 버튼 위치 (Q 슬롯 SKILLBAR_POS 바로 위 · 핫스왑 대응)
local _Scaler = require(game:GetService("ReplicatedStorage"):WaitForChild("ResponsiveScaler"))
-- Q 슬롯과 동일한 UIScale (좌표계 일치용 · 필수)
_Scaler.applyEdge(gui, nil, {
	baseW = 1280, baseH = 720,
	Mobile = { minScale = 0.55 },
	PC     = { minScale = 0.55 },
})
local SKILLBTN_POS = {
	-- MOBA식 부채꼴 슬롯2 (슬롯1 Q=-36,-218)
	Mobile = UDim2.new(1, -187, 1, -128),
	PC     = UDim2.new(1, -365, 1, -170),  -- -20 → -100 (2026-08-21): 하단에 너무 붙어 있어 올림
}
local SKILLBTN_SIZE = { Mobile = 120, PC = 150 }   -- PC는 마우스 클릭용으로 크게
local function syncSkillBtnPos()
	local dev = _Scaler.device()
	local sz  = SKILLBTN_SIZE[dev] or SKILLBTN_SIZE.PC
	btn.Size = UDim2.fromOffset(sz, sz)
	btn.Position = SKILLBTN_POS[dev] or SKILLBTN_POS.PC
end
syncSkillBtnPos()
local _UIS = game:GetService("UserInputService")
_UIS:GetPropertyChangedSignal("KeyboardEnabled"):Connect(syncSkillBtnPos)
_UIS:GetPropertyChangedSignal("TouchEnabled"):Connect(syncSkillBtnPos)
btn.TextTransparency = 1      -- 상태 텍스트 숨김(아이콘으로 대체)

local icon = Instance.new("ImageLabel")
icon.Name = "SkillIcon"
icon.BackgroundTransparency = 1
icon.AnchorPoint = Vector2.new(0.5, 0.5)
icon.Position = UDim2.fromScale(0.5, 0.5)
icon.Size = UDim2.fromScale(1, 1)
icon.Image = "rbxassetid://136390793392380"
icon.ZIndex = 2
icon.Parent = btn

local iconCorner = Instance.new("UICorner")
iconCorner.CornerRadius = UDim.new(0.5, 0)
iconCorner.Parent = icon

local cdLabel = Instance.new("TextLabel")
cdLabel.Name = "CooldownLabel"
cdLabel.BackgroundTransparency = 1
cdLabel.Size = UDim2.fromScale(1, 1)
cdLabel.Font = Enum.Font.GothamBold
cdLabel.TextScaled = true
cdLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
cdLabel.TextStrokeTransparency = 0.3
cdLabel.ZIndex = 5
cdLabel.Text = ""
cdLabel.Parent = btn

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0.5, 0)
corner.Parent = btn

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(200, 160, 110)
stroke.Thickness = 3
stroke.Parent = icon

-- 조준 안내 텍스트(조준 중 화면 상단)
local hint = Instance.new("TextLabel")
hint.Name = "AimHint"
hint.AnchorPoint = Vector2.new(0.5, 0)
hint.Position = UDim2.new(0.5, 0, 0.08, 0)
hint.Size = UDim2.new(0, 320, 0, 36)
hint.BackgroundTransparency = 0.4
hint.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
hint.Text = "착지 지점을 터치하세요 (떼면 발동)"
hint.TextScaled = true
hint.Font = Enum.Font.GothamMedium
hint.TextColor3 = Color3.fromRGB(255, 255, 255)
hint.Visible = false
hint.Parent = gui
local hintCorner = Instance.new("UICorner")
hintCorner.CornerRadius = UDim.new(0, 8)
hintCorner.Parent = hint

-- ── 청사진 경계원 (workspace에 클라 로컬 Part — 다른 사람에겐 안 보임) ──
local indicator = nil
local function ensureIndicator()
	if indicator and indicator.Parent then return indicator end
	local p = Instance.new("Part")
	p.Name = "_SlamAimPreview"
	p.Shape = Enum.PartType.Cylinder
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(80, 200, 255)   -- 청록 (첫 프레임 회색 방지)
	p.Transparency = 0.5
	p.Size = Vector3.new(0.2, SLAM_RADIUS * 2, SLAM_RADIUS * 2)
	p.Parent = workspace
	indicator = p
	return p
end
local function clearIndicator()
	if indicator then indicator:Destroy(); indicator = nil end
end

-- ── 조준 지점 계산 ───────────────────────────────────────────
-- 화면 좌표 → 월드 레이캐스트 → 착지 후보. 사거리 밖이면 원 가장자리로 클램프.
-- 반환: worldPos(지면), valid(사거리·경로 OK 여부)
-- 🚧 [2026-09-13] HammerHighScript 의 isBlocker 와 **짝**. 같이 바꿔야 한다.
--   여기는 예고(경계원)를 그리고, 서버는 실제 착지를 정한다. 한쪽만 고치면 UI 가 거짓말을 한다.
--   [왜 표식인가] 성문은 콜리전 그룹이 Default 라 BLOCK_GROUPS 에 안 걸렸고,
--     castleFolder 는 "map1 castle" 만 찾아 map2 에선 캐슬 판정이 죽어 있었다.
--     막을 것에 LeapBlocker 를 켜고 상위까지 훑는다 — 재건되는 성문도 자동으로 덮인다.
local BLOCK_GROUPS = { Mountains = true, Walls = true, ItemBarrier = true, TaggerBarrier = true }
local function hasLeapBlockerTag(inst)
	local cur = inst
	while cur and cur ~= workspace do
		if cur:GetAttribute("LeapBlocker") then return true end
		cur = cur.Parent
	end
	return false
end
local function isBlocker(inst)
	if not inst then return false end
	if BLOCK_GROUPS[inst.CollisionGroup] then return true end
	if hasLeapBlockerTag(inst) then return true end
	return false
end

local function computeAimPoint(screenX, screenY, ignoreList)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil, false end

	ignoreList = ignoreList or { indicator }

	-- 화면 → 월드 레이
	local ray = camera:ViewportPointToRay(screenX, screenY)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = ignoreList
	local hitResult = workspace:Raycast(ray.Origin, ray.Direction * 1000, rp)
	local worldHit = hitResult and hitResult.Position
	if not worldHit then
		-- 허공을 가리키면 러너 발높이 평면과 교차시킴
		local groundY = hrp.Position.Y - 3
		local t = (groundY - ray.Origin.Y) / ray.Direction.Y
		if t and t > 0 then worldHit = ray.Origin + ray.Direction * t else return nil, false end
	end

	-- 사거리 클램프 (러너 중심 수평거리)
	local flat = (worldHit - hrp.Position) * Vector3.new(1, 0, 1)
	local dist = flat.Magnitude
	local dir = (dist < 0.01) and Vector3.new(0,0,-1) or flat.Unit
	local clampedDist = math.min(dist, AIM_RANGE)

	-- 경로상 벽/castle 검사 → 막히면 그 앞까지 자름
	do
		local rp2 = RaycastParams.new()
		rp2.FilterType = Enum.RaycastFilterType.Exclude
		rp2.FilterDescendantsInstances = ignoreList
		local traveled = 0
		local cur = hrp.Position
		for _ = 1, 8 do
			local remain = clampedDist - traveled
			if remain <= 0 then break end
			local res = workspace:Raycast(cur, dir * remain, rp2)
			if not res then break end
			if isBlocker(res.Instance) then
				local hitDist = traveled + (res.Position - cur).Magnitude
				clampedDist = math.max(0, hitDist - 1.5)
				break
			end
			local stepped = (res.Position - cur).Magnitude + 0.5
			traveled = traveled + stepped
			cur = cur + dir * stepped
		end
	end

	-- 최종 착지점 + 지면 보정
	local origin = hrp.Position + dir * clampedDist
	local rp3 = RaycastParams.new()
	rp3.FilterType = Enum.RaycastFilterType.Exclude
	rp3.FilterDescendantsInstances = ignoreList
	local groundRes = workspace:Raycast(origin + Vector3.new(0, 50, 0), Vector3.new(0, -300, 0), rp3)
	local groundY = groundRes and groundRes.Position.Y or (hrp.Position.Y - 3)
	local finalPos = Vector3.new(origin.X, groundY + 0.1, origin.Z)

	return finalPos, true
end

-- ── 조준 루프 ────────────────────────────────────────────────
local aimConn = nil
local lastAimPos = nil

local function getPointerPos()
	-- MouseLocation은 터치 입력도 반영함 (마우스·터치 공용)
	local mp = UIS:GetMouseLocation()
	return mp.X, mp.Y
end

local function startAim()
	if onCooldown or os.clock() < cooldownUntil or isSlamming or aiming then return end
	if not equipped then return end
	aiming = true
	setBackpack(false)
	btn.Text = "조준"
	btn.BackgroundColor3 = Color3.fromRGB(70, 90, 110)
	hint.Visible = true
	SlamRemote:FireServer("aimStart")   -- 조준 시작 → 서버가 flame tail ON

	-- 제외 목록: Humanoid 가진 모든 캐릭터(플레이어·더미·NPC·봇) + 프리뷰.
	-- 조준 시작 시 한 번만 수집(매 프레임 GetDescendants는 무거움).
	local ignoreList = { indicator }
	for _, m in ipairs(workspace:GetDescendants()) do
		if m:IsA("Humanoid") and m.Parent then
			table.insert(ignoreList, m.Parent)
		end
	end

	if aimConn then aimConn:Disconnect() end
	aimConn = RunService.RenderStepped:Connect(function()
		if not aiming then return end
		-- 프리뷰는 항상 최신 인스턴스를 제외 목록 첫 항목으로 갱신
		ignoreList[1] = indicator
		local sx, sy = getPointerPos()
		local pos = computeAimPoint(sx, sy, ignoreList)
		lastAimPos = pos
		if pos then
			local p = ensureIndicator()
			p.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))  -- 바닥 원판
			p.Color = Color3.fromRGB(80, 200, 255)   -- 항상 청록 통일
		end
	end)
end

local function confirmAim()
	if not aiming then return end
	aiming = false
	hint.Visible = false
	if aimConn then aimConn:Disconnect(); aimConn = nil end
	clearIndicator()

	if not lastAimPos then
		-- 조준 지점 없음 → 취소
		SlamRemote:FireServer("aimCancel")   -- 조준 취소 → 서버가 flame tail OFF
		setBackpack(true)
		btn.Text = "슬램"
		btn.BackgroundColor3 = Color3.fromRGB(90, 70, 50)
		return
	end

	-- 발동: 좌표 전송 + 슬램 진행 표시 + 쿨다운 진입
	onCooldown = true
	isSlamming = true
	btn.BackgroundColor3 = Color3.fromRGB(60, 50, 40)
	btn.Text = "▼"
	SlamRemote:FireServer("slam", lastAimPos)
	lastAimPos = nil

	-- 안전장치: slamEnded 신호 누락 대비 (선딜 + 비행 + 여유)
	task.delay(4.0, function()
		if isSlamming then
			isSlamming = false
			onCooldown = false
			setBackpack(true)
		end
	end)
end

-- ── 쿨다운 카운트다운 (착지 후 서버 신호로 시작) ─────────────
-- 표시 루프: cooldownUntil까지 카운트다운. 해제로 루프가 죽어도 쿨 자체(시각)는 유지되고,
-- 재장착 시 이 함수를 다시 불러 남은 쿨을 이어서 표시한다.
local function runCooldownDisplay()
	task.spawn(function()
		icon.ImageColor3 = Color3.fromRGB(140, 140, 140)
		while os.clock() < cooldownUntil and equipped do
			cdLabel.Text = tostring(math.ceil(cooldownUntil - os.clock()))
			task.wait(0.2)
		end
		if os.clock() >= cooldownUntil then
			onCooldown = false
			icon.ImageColor3 = Color3.fromRGB(255, 255, 255)
			cdLabel.Text = ""
		end
	end)
end
local function beginCooldown()
	cooldownUntil = os.clock() + SLAM_COOLDOWN
	onCooldown = true
	runCooldownDisplay()
end

SlamRemote.OnClientEvent:Connect(function(msg)
	if msg == "slamEnded" then
		isSlamming = false
		setBackpack(true)
		beginCooldown()
	elseif msg == "cancel" then
		-- 서버가 착지 무효 처리 → 쿨다운/잠금 모두 해제하고 즉시 재사용
		isSlamming = false
		onCooldown = false
		setBackpack(true)
	end
end)

-- ── 버튼 입력: 누름=조준 시작, 뗌=확정 발동 ──────────────────
btn.MouseButton1Down:Connect(startAim)
btn.MouseButton1Up:Connect(confirmAim)
-- PC: F 키 (무기 스킬 통일키) — 누름=조준, 뗌=확정
UIS.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if not gui.Enabled then return end
	if input.KeyCode == Enum.KeyCode.F then
		startAim()
	end
end)
UIS.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.F and aiming then
		confirmAim()
	end
end)
-- 버튼 밖에서 손가락/마우스를 떼도 확정되게 전역 백업
UIS.InputEnded:Connect(function(input)
	if aiming and (input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch) then
		confirmAim()
	end
end)

local function resetState()
	aiming = false
	onCooldown = false
	isSlamming = false
	if aimConn then aimConn:Disconnect(); aimConn = nil end
	clearIndicator()
	hint.Visible = false
	setBackpack(true)
	btn.Text = "슬램"
	btn.BackgroundColor3 = Color3.fromRGB(90, 70, 50)
end

Tool.Equipped:Connect(function()
	equipped = true
	gui.Enabled = true
	camera = workspace.CurrentCamera
	resetState()
	-- flame tail 텍스처 프리로드: 첫 슬램 때 불꽃이 1~2초 늦게 뜨는 지연 방지.
	-- raw ID 문자열 대신 실제 Beam/파티클 인스턴스를 넘겨야 확실히 로드됨.
	task.spawn(function()
		local ft = Tool:FindFirstChild("flame tail")
		if not ft then return end
		local toPreload = {}
		for _, e in ipairs(ft:GetDescendants()) do
			if e:IsA("Beam") or e:IsA("ParticleEmitter") then
				table.insert(toPreload, e)
			end
		end
		if #toPreload > 0 then
			pcall(function()
				game:GetService("ContentProvider"):PreloadAsync(toPreload)
			end)
		end
	end)
end)

Tool.Unequipped:Connect(function()
	equipped = false
	gui.Enabled = false
	resetState()
end)

-- ─── 라운드 종료(툴 파괴) 시 착지예고/스킬 UI 정리 ───────────────
-- Unequipped만으론 라운드 종료 시 툴 '파괴' 경로를 못 잡고, 단발 정리는
-- 살아있는 슬램 스레드가 gui.Enabled=true/착지예고를 재기록해 잔재한다.
-- → Destroying+Unequipped에, 즉시+0.6s+1.8s 다단계로 확실히 끈다.
local function _cleanupChargeUI()
	pcall(clearIndicator)
	pcall(function() gui.Enabled = false end)
	pcall(function() setBackpack(true) end)  -- ★ 백팩 UI 복구: 스킬 중 종료로 꺼진 채 잔존하면 다음 라운드 무기 장착 불가
	pcall(resetState)
end
-- 세대 토큰: 재장착하면 이전 해제의 지연 예약(0.6/1.8s)을 무효화.
-- (없으면 해제→즉시 재장착 시, 이전 예약이 방금 켜진 스킬 아이콘을 꺼버림)
local _cleanupGen = 0
local function _cleanupChargeStaged()
	_cleanupGen += 1
	local gen = _cleanupGen
	print("🧹 [HH-ChargeClient] cleanup 실행 (gen " .. gen .. ")")
	_cleanupChargeUI()
	task.delay(0.6, function() if _cleanupGen == gen then _cleanupChargeUI() end end)
	task.delay(1.8, function() if _cleanupGen == gen then _cleanupChargeUI() end end)
end
Tool.Destroying:Connect(_cleanupChargeStaged)
Tool.Unequipped:Connect(_cleanupChargeStaged)
-- 🧹 [2026-09-18] AncestryChanged 를 함께 건다. **이 줄이 없어서 정리가 통째로 안 돌았다.**
--   [측정] 09-18 훈련장 로그: 무기 회수가 두 번 일어났는데(14:37:43.879 / 14:37:58.245)
--     위 두 훅이 찍는 "🧹 [HH-ChargeClient] cleanup 실행" 이 **한 번도 안 찍혔다.**
--     같은 시각 [WeaponUICleanup] 클라 로그는 정상이라 로그 필터 문제가 아니다.
--   [증상] 조준 중 서버가 툴을 회수 → 청사진 경계원이 바닥에 영구 잔존.
--   [왜 안 오나] 서버가 Tool:Destroy() 하면 클라는 복제로 Parent=nil 을 받을 뿐이다.
--     Destroying 은 Destroy() 를 부른 쪽에서 발생하고, 이 경로의 Unequipped 도 안 온다.
--     ⚠️ 정확한 엔진 동작(복제가 Destroying 을 안 띄우는가 / 스크립트가 먼저 죽는가)은
--       단정하지 않는다. 어느 쪽이든 해법은 같다 — 확실히 오는 신호를 쓴다.
--   [선례] DiamondBladeSword.VitalMarkClient:367 이 이미 같은 형태다 —
--     "Destroying 은 툴 내부 스크립트와 같은 운명이라 늦거나 아예 안 올 수 있다".
--     새로 만들지 않고 그 형태를 따른다.
--   ⚠️ parent 가 nil 일 때만 정리한다. 장착/해제는 Backpack↔Character 이동이라
--     AncestryChanged 가 매번 뜨는데, 거기서 정리하면 장착할 때마다 UI 가 꺼진다.
Tool.AncestryChanged:Connect(function(_, parent)
	if not parent then _cleanupChargeStaged() end
end)
-- 재장착 시: 지연 예약 무효화 + UI 즉시 복구
Tool.Equipped:Connect(function()
	_cleanupGen += 1
	pcall(function() gui.Enabled = true end)
	-- 재장착 시 남은 쿨 표시 재개 (해제로 표시 루프가 죽어도 cooldownUntil은 유지됨)
	task.defer(function()
		if os.clock() < cooldownUntil then
			onCooldown = true
			runCooldownDisplay()
		end
	end)
end)
