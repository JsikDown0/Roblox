-- ChargeClient: 건틀렛 스킬(차징 돌진 → 오라오라) 입력 — 클라
-- 버튼을 누르는 시간 = 차징량(0~1). 차징 시작 시 서버에 알려 차징 애니 재생.
-- 떼면 돌진 발동. 돌진이 명중하면 서버가 "hitReady" → 버튼이 "ORA ORA"로 바뀜.
-- 그 상태에서 버튼을 다시 누르면 오라오라 발동.
-- 모바일 우선: 전용 버튼(화면 홀드는 카메라/이동과 충돌).

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

-- ── 백팩(인벤) 잠금: 돌진 중 무기 스왑 차단 ───────────────────
-- 돌진 중 건틀렛을 해제하면 물리가 깨지므로, 차징~돌진 종료까지 백팩을 잠가 스왑을 막음.
-- (망치와 동일 패턴. 잠금이 안 풀리면 영구 인벤 잠금이 되므로 여러 경로에서 반드시 해제)
local backpackLockId = 0   -- 안전망 타이머 무효화용
local function setBackpack(enabled)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, enabled)
	end)
end

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Tool       = script.Parent
local DashRemote = Tool:WaitForChild("DashRemote")

local MAX_CHARGE_TIME = 2.0    -- 풀차징까지 걸리는 시간(0~2초). 2초에 최대 데미지·거리
local OVERCHARGE_TIME = 4.0    -- 이 시점부터 과충전 패널티 표시(스파크+연기). 2~4초는 "떼기 좋은" 유예
local FORCE_FIRE_TIME = 4.5    -- 4.5초 도달 시 강제 발사(과충전 0.5초 후)
-- 타임라인: 0~2 차징 / 2 풀차징(core 펄스="떼라") / 4~ 과충전(스파크+연기="패널티") / 4.5 강제발사

-- 돌진 거리 계산용 (서버 GauntletScript와 동일해야 경로 예측이 정확)
local DASH_SPEED_MIN = 60
local DASH_SPEED_MAX = 140
local DASH_TIME_MIN  = 0.18
local DASH_TIME_MAX  = 0.42
local PATH_WIDTH     = 4       -- 경로 표시 폭(studs)

local equipped   = false
local charging   = false
local chargeStart = 0
local chargeConn = nil
local mode = "dash"           -- "dash" | "oraora"
local sentFullCharge = false  -- 4초 풀차징 신호 보냈는지
local sentOvercharge = false  -- 과충전 신호 보냈는지
local pathPart = nil          -- 돌진 경로 미리보기 Part (클라 로컬) — 미사용(세그먼트 방식으로 대체)
local pathSegments = {}       -- 계단/경사 따라가는 경로 세그먼트 박스들
local PATH_SEG_COUNT = 16     -- 경로 분할 수 (많을수록 굴곡 매끈)

local camera = workspace.CurrentCamera

-- ── 버튼 UI ──────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "GauntletDashGui"
gui.ResetOnSpawn = true  -- 사망 리스폰 시 자동 정리 (스킬 아이콘 잔재 방지; 재지급 시 새로 생성됨)
gui.IgnoreGuiInset = true
gui.DisplayOrder = 18
gui.Enabled = false
gui.Parent = playerGui

local btn = Instance.new("TextButton")
btn.Name = "DashButton"
btn.AnchorPoint = Vector2.new(1, 1)
btn.BackgroundColor3 = Color3.fromRGB(40, 55, 80)
btn.BackgroundTransparency = 1
btn.AutoButtonColor = false
btn.Text = "DASH"
btn.TextScaled = true
btn.Font = Enum.Font.GothamBold
btn.TextColor3 = Color3.fromRGB(220, 235, 255)
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
btn.TextTransparency = 1      -- 텍스트 숨김(아이콘으로 대체)

local icon = Instance.new("ImageLabel")
icon.Name = "SkillIcon"
icon.BackgroundTransparency = 1
icon.AnchorPoint = Vector2.new(0.5, 0.5)
icon.Position = UDim2.fromScale(0.5, 0.5)
icon.Size = UDim2.fromScale(1, 1)
icon.Image = "rbxassetid://74209447621572"
icon.ZIndex = 2
icon.Parent = btn

local iconCorner = Instance.new("UICorner")
iconCorner.CornerRadius = UDim.new(0.5, 0)
iconCorner.Parent = icon

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0.5, 0)
corner.Parent = btn

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(120, 170, 240)
stroke.Thickness = 3
stroke.Parent = icon

local fill = Instance.new("Frame")
fill.Name = "ChargeFill"
fill.AnchorPoint = Vector2.new(0.5, 1)
fill.Position = UDim2.new(0.5, 0, 1, 0)
fill.Size = UDim2.new(1, 0, 0, 0)
fill.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
fill.BackgroundTransparency = 0.5
fill.BorderSizePixel = 0
fill.ZIndex = 3
fill.Parent = btn
local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0.5, 0)
fillCorner.Parent = fill

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

-- ── 모드 전환 (돌진 ↔ 오라오라) ──────────────────────────────
local function setMode(m)
	mode = m
	if m == "dash" then
		btn.Text = "DASH"
		btn.BackgroundColor3 = Color3.fromRGB(40, 55, 80)
		stroke.Color = Color3.fromRGB(120, 170, 240)
	else  -- oraora
		btn.Text = "ORA ORA"
		btn.BackgroundColor3 = Color3.fromRGB(80, 40, 40)
		stroke.Color = Color3.fromRGB(255, 90, 60)
	end
	fill.Size = UDim2.new(1, 0, 0, 0)
end

-- ── 차징 (돌진 모드일 때만) ──────────────────────────────────
-- ── 돌진 경로 미리보기 (차징 중, 본인 화면에만) — 계단/경사 표면 추적 ─────────────
-- 세그먼트 박스 풀 확보(없으면 생성)
local function ensureSegments()
	for i = 1, PATH_SEG_COUNT do
		local seg = pathSegments[i]
		if not seg or not seg.Parent then
			local p = Instance.new("Part")
			p.Name = "_GauntletDashPathSeg"
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Material = Enum.Material.Neon
			p.Color = Color3.fromRGB(255, 140, 40)
			p.Transparency = 0.55
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
			p.Parent = workspace
			pathSegments[i] = p
		end
	end
end

local function clearPathPart()
	for i = #pathSegments, 1, -1 do
		if pathSegments[i] then pathSegments[i]:Destroy() end
		pathSegments[i] = nil
	end
	if pathPart then pathPart:Destroy(); pathPart = nil end
end

-- (x,z) 위에서 아래로 레이캐스트해 "걸을 수 있는 윗면" 표면 점 찾기 (에너지볼 기법)
-- refY: 이 높이 + PROBE_UP 에서 아래로 쏨 (위로 가는 계단도 위에서 쏘게)
local PROBE_UP = 60
local PROBE_DOWN = 140
local WALK_NORMAL_Y = 0.5   -- 면의 Normal.Y가 이 값 이상이어야 "윗면"(벽·가파른 면 제외)
local function probeSurface(xzPos, refY, params)
	local startY = math.max(xzPos.Y, refY) + PROBE_UP
	local origin = Vector3.new(xzPos.X, startY, xzPos.Z)
	local remaining = startY + PROBE_DOWN   -- 충분히 아래까지
	-- 벽을 만나면 그 안쪽을 무시하고 계속 내려가며 윗면을 찾음
	for _ = 1, 6 do
		local r = workspace:Raycast(origin, Vector3.new(0, -remaining, 0), params)
		if not r then return nil end
		if r.Normal.Y >= WALK_NORMAL_Y then
			return r.Position   -- 걸을 수 있는 윗면
		end
		-- 벽/가파른 면 → 살짝 아래에서 다시 쏨
		remaining = remaining - ((origin.Y - r.Position.Y) + 0.5)
		origin = Vector3.new(xzPos.X, r.Position.Y - 0.5, xzPos.Z)
		if remaining <= 0 then break end
	end
	return nil
end

local function updatePathPreview(ratio)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- 서버와 동일한 거리 공식: 차징량으로 속도·시간 보간 → 거리 = 속도×시간
	local function lerp(a, b) return a + (b - a) * ratio end
	local dist = lerp(DASH_SPEED_MIN, DASH_SPEED_MAX) * lerp(DASH_TIME_MIN, DASH_TIME_MAX)

	-- 캐릭터 정면(수평)
	local dir = hrp.CFrame.LookVector * Vector3.new(1, 0, 1)
	dir = dir.Magnitude > 0.01 and dir.Unit or hrp.CFrame.LookVector

	-- 캐릭터·경로 세그먼트 무시 + castle/Forest 벽 제외(경로가 벽 안 타게)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = { char }
	for _, m in ipairs(workspace:GetChildren()) do
		if m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") then
			table.insert(exclude, m)
		end
		if m.Name == "_GauntletDashPathSeg" then table.insert(exclude, m) end
	end
	-- map1 castle 폴더 전체 + Forest map wall segment 제외
	local map1 = workspace:FindFirstChild("map1")
	if map1 then
		local castle = map1:FindFirstChild("map1 castle")
		if castle then table.insert(exclude, castle) end
		for _, c in ipairs(map1:GetChildren()) do
			if c.Name:find("Forest map wall segment") then table.insert(exclude, c) end
		end
	end
	rp.FilterDescendantsInstances = exclude

	ensureSegments()
	local startXZ = hrp.Position
	local segLen = dist / PATH_SEG_COUNT
	-- 첫 점: 본인 발밑 표면
	local prevPt = probeSurface(startXZ, startXZ.Y, rp) or Vector3.new(startXZ.X, startXZ.Y - 2.5, startXZ.Z)
	for i = 1, PATH_SEG_COUNT do
		local nextXZ = startXZ + dir * (segLen * i)
		-- 직전 세그먼트 높이를 기준으로 probe(위로 가는 계단 대응)
		local nextPt = probeSurface(nextXZ, prevPt.Y, rp)
			or Vector3.new(nextXZ.X, prevPt.Y, nextXZ.Z)   -- 표면 못 찾으면 이전 높이 유지
		nextPt = nextPt + Vector3.new(0, 0.1, 0)   -- 표면 살짝 위

		local seg = pathSegments[i]
		local mid = (prevPt + nextPt) / 2
		local segVec = nextPt - prevPt
		local segDist = segVec.Magnitude
		if segDist < 0.05 then segDist = 0.05 end
		seg.Size = Vector3.new(PATH_WIDTH, 0.2, segDist)
		seg.CFrame = CFrame.lookAt(mid, mid + segVec.Unit)
		seg.Color = (ratio >= 1) and Color3.fromRGB(255, 90, 20) or Color3.fromRGB(255, 140, 40)
		prevPt = nextPt
	end
end

local releaseCharge   -- forward 선언 (차징 루프에서 5초 강제발사로 호출하므로)
local function startCharge()
	if not equipped or charging then return end
	if mode ~= "dash" then return end
	local cdUntil = player:GetAttribute("GauntletDashCdUntil") or 0
	-- 🕒 [버그수정 2026-09-20] GauntletDashCdUntil 은 서버가 GetServerTimeNow() 로 찍는다.
	--   os.clock() 과 비교하면 서버·클라의 시계 원점이 달라 쿨이 영구 봉인된다(라이브 317초).
	--   ⚠️ 바로 아래 chargeStart 처럼 "클라 안에서만 재는 경과시간"은 os.clock() 그대로 둘 것.
	if workspace:GetServerTimeNow() < cdUntil then return end

	charging = true
	chargeStart = os.clock()
	sentFullCharge = false
	sentOvercharge = false
	btn.Text = ""
	setBackpack(false)   -- 차징~돌진 종료까지 무기 스왑 차단(돌진 중 해제 시 물리 깨짐 방지)
	DashRemote:FireServer("chargeStart")   -- 서버: 차징 애니 재생

	if chargeConn then chargeConn:Disconnect() end
	chargeConn = RunService.RenderStepped:Connect(function()
		if not charging then return end
		local held = os.clock() - chargeStart
		local ratio = math.clamp(held / MAX_CHARGE_TIME, 0, 1)
		fill.Size = UDim2.new(1, 0, ratio, 0)
		fill.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		updatePathPreview(ratio)   -- 돌진 경로 미리보기 갱신(차징량에 따라 길이 ↑)

		-- 4초 풀차징 도달 → core 펄스("떼라") 신호 (1회)
		if held >= MAX_CHARGE_TIME and not sentFullCharge then
			sentFullCharge = true
			DashRemote:FireServer("fullcharge")
		end
		-- 4초 넘겨 계속 홀딩 → 과충전(스파크+연기+감전음) 신호 (1회)
		if held >= OVERCHARGE_TIME and not sentOvercharge then
			sentOvercharge = true
			DashRemote:FireServer("overcharge")
		end
		-- 5초 도달 → 강제 발사(과충전 패널티). charging 가드로 1회만.
		if held >= FORCE_FIRE_TIME and charging then
			releaseCharge()
		end
	end)
end

local function releaseChargeImpl()
	if not charging then return end
	charging = false
	if chargeConn then chargeConn:Disconnect(); chargeConn = nil end
	clearPathPart()   -- 경로 미리보기 제거
	local held = os.clock() - chargeStart
	local ratio = math.clamp(held / MAX_CHARGE_TIME, 0, 1)
	-- 4.5초(과충전 표시) 넘겨서 떼면 패널티 적용. 4~4.5초는 풀차징 유지(떼기 좋은 구간)
	local overcharged = held >= OVERCHARGE_TIME
	fill.Size = UDim2.new(1, 0, 0, 0)
	btn.Text = "DASH"
	DashRemote:FireServer("dash", ratio, overcharged)
	-- 백팩 잠금 안전망: 서버 "dashEnded" 신호가 정상이면 그때 풀리지만, 신호를 놓쳐도
	-- 최대 시간(돌진+후딜+여유) 뒤 무조건 해제 → 영구 인벤 잠금 방지.
	backpackLockId = backpackLockId + 1
	local myLockId = backpackLockId
	task.delay(3.5, function()
		if myLockId == backpackLockId then setBackpack(true) end
	end)
end
releaseCharge = releaseChargeImpl

-- ── 버튼 입력 ────────────────────────────────────────────────
btn.MouseButton1Down:Connect(function()
	if mode == "dash" then
		startCharge()
	end
end)
btn.MouseButton1Up:Connect(function()
	if mode == "dash" then
		releaseCharge()
	elseif mode == "oraora" then
		-- 오라오라 발동(탭)
		DashRemote:FireServer("oraora")
	end
end)
UIS.InputEnded:Connect(function(input)
	if charging and (input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch) then
		releaseCharge()
	end
end)
-- PC: F 키 (무기 스킬 통일키) — 누름=차지, 뗌=발동 (버튼 핸들러와 동일 분기)
UIS.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if not gui.Enabled then return end
	if input.KeyCode == Enum.KeyCode.F and mode == "dash" then
		startCharge()
	end
end)
UIS.InputEnded:Connect(function(input)
	if input.KeyCode ~= Enum.KeyCode.F then return end
	if mode == "dash" then
		if charging then releaseCharge() end
	elseif mode == "oraora" then
		DashRemote:FireServer("oraora")
	end
end)

-- ── 서버 신호 수신 ───────────────────────────────────────────
-- (오라오라는 다른 아이템으로 이관됨 — 건틀렛은 돌진 단일 스킬. 명중해도 모드 전환 없음)
local grabPinConn = nil
DashRemote.OnClientEvent:Connect(function(msg, taggerRoot)
	if msg == "dashEnded" then
		-- 돌진 완전 종료(후딜 포함) → 백팩 잠금 해제
		backpackLockId = backpackLockId + 1   -- 안전망 타이머 무효화(이미 해제하므로)
		setBackpack(true)
		-- 쿨다운 표시: GauntletDashCdUntil 속성 기반 카운트다운 (아이콘 어둡게 + 숫자)
		task.spawn(function()
			while equipped do
				local cdUntil = player:GetAttribute("GauntletDashCdUntil") or 0
				local remain = cdUntil - workspace:GetServerTimeNow()
				if remain <= 0 then break end
				icon.ImageColor3 = Color3.fromRGB(140, 140, 140)
				cdLabel.Text = tostring(math.ceil(remain))
				task.wait(0.2)
			end
			icon.ImageColor3 = Color3.fromRGB(255, 255, 255)
			cdLabel.Text = ""
		end)
	elseif msg == "grabStart" and taggerRoot then
		-- ★ 클라 핀: 서버가 태거 소유권을 내게 넘기고 grabStart를 쏘면, 매 렌더 프레임마다
		--   내 캐릭터 앞 3stud에 태거를 직접 배치. 클라 소유라 즉시 반영 → 지연 0, 물리 제약 없음(폭주 방지).
		if grabPinConn then grabPinConn:Disconnect() end
		grabPinConn = RunService.RenderStepped:Connect(function()
			if not taggerRoot or not taggerRoot.Parent then
				if grabPinConn then grabPinConn:Disconnect(); grabPinConn = nil end
				return
			end
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				taggerRoot.CFrame = hrp.CFrame * CFrame.new(0, 0, -3)
			end
		end)
	elseif msg == "grabEnd" then
		if grabPinConn then grabPinConn:Disconnect(); grabPinConn = nil end
	end
end)

-- ── 장착 / 해제 ──────────────────────────────────────────────
local function resetState()
	charging = false
	if chargeConn then chargeConn:Disconnect(); chargeConn = nil end
	clearPathPart()
	setMode("dash")
	-- 백팩 잠금 해제(장착/해제/취소 등 어느 경로로 와도 잠금이 안 남게)
	backpackLockId = backpackLockId + 1
	setBackpack(true)
end

Tool.Equipped:Connect(function()
	equipped = true
	gui.Enabled = true
	resetState()
end)

Tool.Unequipped:Connect(function()
	equipped = false
	gui.Enabled = false
	resetState()
	DashRemote:FireServer("chargeCancel")
end)

-- 툴 파괴 시 UI 완전 정리 (라운드 종료 회수/강제 파괴 시 PlayerGui 잔재·누적 방지)
Tool.Destroying:Connect(function()
	if gui then gui:Destroy() end
	pcall(clearPathPart)
	pcall(function() setBackpack(true) end)  -- ★ 백팩 UI 복구 (스킬 중 종료로 꺼진 채 잔존 방지)
	task.delay(0.6, function() pcall(function() setBackpack(true) end) end)
	task.delay(1.8, function() pcall(function() setBackpack(true) end) end)  -- 차징 중 파괴 시 벽/바닥의 대시 경로 이펙트(_GauntletDashPathSeg) 잔존 방지
end)

-- ─── 재장착 시 남은 쿨 표시 재개 ───
-- 쿨 진실은 GauntletDashCdUntil 속성(시각 기반)이라 해제와 무관하게 유지되지만,
-- 표시 루프는 서버 메시지 때만 시작돼 재장착 후 쿨 숫자가 안 보였다.
Tool.Equipped:Connect(function()
	task.defer(function()
		local cdUntil = player:GetAttribute("GauntletDashCdUntil") or 0
		if cdUntil - workspace:GetServerTimeNow() > 0.05 then
			task.spawn(function()
				while equipped do
					local remain = (player:GetAttribute("GauntletDashCdUntil") or 0) - workspace:GetServerTimeNow()
					if remain <= 0 then break end
					icon.ImageColor3 = Color3.fromRGB(140, 140, 140)
					cdLabel.Text = tostring(math.ceil(remain))
					task.wait(0.2)
				end
				icon.ImageColor3 = Color3.fromRGB(255, 255, 255)
				cdLabel.Text = ""
			end)
		end
	end)
end)
