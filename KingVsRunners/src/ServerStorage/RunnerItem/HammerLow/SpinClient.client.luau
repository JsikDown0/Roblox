-- HammerLow 스핀 슬래시 — 클라 버튼 + 회전 연출
-- 버튼 누르면 서버에 스핀 발동 요청. 회전 동안 캐릭터를 시각적으로 빙글 돌림.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Tool = script.Parent
local SpinRemote = Tool:WaitForChild("SpinRemote")

local SPIN_DURATION = 2.5     -- 서버와 동일
local SPIN_COOLDOWN = 6       -- 서버와 동일 (HammerScript SPIN_COOLDOWN)
local equipped = false
local onCooldown = false
local cooldownUntil = 0   -- 쿨 만료 시각 — 해제/재장착과 무관하게 유지
local isSpinning = false      -- 회전 진행 중 (이 동안 무기 전환/해제 금지)

-- ── 버튼 UI ──────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "HammerSpinGui"
gui.ResetOnSpawn = true  -- 사망 리스폰 시 자동 정리 (UI 잔재 방지)
gui.IgnoreGuiInset = true
gui.DisplayOrder = 18
gui.Enabled = false
gui.Parent = playerGui

local btn = Instance.new("ImageButton")
btn.Name = "SpinButton"
btn.AnchorPoint = Vector2.new(1, 1)
-- 우하단 Q 스킬 슬롯 바로 위 — 디바이스별 위치는 아래 syncSkillBtnPos가 처리
btn.BackgroundTransparency = 1        -- 아이콘 자체 배경 사용
btn.AutoButtonColor = true
btn.Image = "rbxassetid://126974616980064"  -- Spin(해머) 스킬 아이콘
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

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0.5, 0)  -- 원형
corner.Parent = btn

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(200, 160, 110)
stroke.Thickness = 3
stroke.Parent = btn

-- 상태/쿨다운 숫자 오버레이 (ImageButton엔 Text가 없어 라벨로 표시)
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

-- ── 회전 시각 연출 ───────────────────────────────────────────
local spinConn = nil
local function startVisualSpin()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then return end
	if spinConn then spinConn:Disconnect() end

	-- 이동 시 캐릭터가 이동방향으로 자동정렬되는 걸 끔 → 회전 연출과 안 싸움(끊김 방지)
	hum.AutoRotate = false

	local t0 = os.clock()
	spinConn = RunService.Heartbeat:Connect(function()
		local hrpNow = char and char:FindFirstChild("HumanoidRootPart")
		local humNow = char and char:FindFirstChildOfClass("Humanoid")
		-- ⚠️ [2026-09-07] 툴 소멸을 종료 조건에 넣는다.
		--   실측: 로비 훈련장에서 스핀 중 라운드에 끌려가면 툴이 회수되는데,
		--   이 Heartbeat 연결은 끊기지 않고 SPIN_DURATION 이 찰 때까지 계속 돈다.
		--   서버가 방향을 펴도(RoundStateResetServer) 그 직후 여기가 다시 돌려서
		--   캐릭터가 '뒤로 달리는' 상태가 됐다.
		--     19:29:27.079  스핀 시작
		--     19:29:27.330  서버 복구 (look 0,0,-1 / 기울기 0 — 서버는 정상)
		--     19:29:29.579  스핀 종료 예정 ← 그 사이 2.25초 동안 클라가 계속 회전
		--   Tool.Parent 가 nil 이면 회수·파괴된 것이다.
		if not hrpNow or not Tool.Parent or os.clock() - t0 > SPIN_DURATION then
			if spinConn then spinConn:Disconnect(); spinConn = nil end
			if humNow then humNow.AutoRotate = true end   -- 자동정렬 복원
			-- 돌다 만 각도를 펴 준다. AutoRotate 만 켜면 엔진이 되돌려주지 않는다.
			if hrpNow then
				local lv = hrpNow.CFrame.LookVector
				local flat = Vector3.new(lv.X, 0, lv.Z)
				if flat.Magnitude > 0.001 then
					hrpNow.CFrame = CFrame.lookAt(hrpNow.Position, hrpNow.Position + flat.Unit)
				end
			end
			return
		end
		-- 캐릭터를 Y축으로 빠르게 회전 (시각 효과). AutoRotate가 꺼져 있어 이동 중에도 매끄러움.
		hrpNow.CFrame = hrpNow.CFrame * CFrame.Angles(0, math.rad(24), 0)
	end)
end

-- ── 회전 중 무기 스왑 차단: 백팩 GUI를 끔 (클릭·숫자키 둘 다 막힘) ──
local function setBackpack(enabled)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, enabled)
	end)
end

-- ── 버튼 동작 ────────────────────────────────────────────────
-- 발동 → 회전 중 표시. 서버가 회전 끝나면 spinEnded 신호 → 그때부터 쿨다운 카운트.
local function fireSpin()
	if onCooldown or os.clock() < cooldownUntil then return end
	onCooldown = true
	isSpinning = true       -- 회전 시작 → 무기 전환/해제 금지
	setBackpack(false)      -- 백팩 잠금 (무기 스왑 차단)
	btn.ImageColor3 = Color3.fromRGB(140, 140, 140)   -- 회전 중 아이콘 어둡게
	cdLabel.Text = "..."     -- 회전 중 표시
	SpinRemote:FireServer()
	startVisualSpin()
	-- 안전장치: 회전 시간이 지나면 isSpinning 해제 + 백팩 복원 (spinEnded 신호 누락 대비)
	task.delay(SPIN_DURATION + 0.5, function()
		if isSpinning then
			isSpinning = false
			setBackpack(true)
		end
	end)
end

-- 쿨다운 카운트다운 (회전 종료 후 서버 신호로 시작)
local function runCooldownDisplay()
	task.spawn(function()
		while os.clock() < cooldownUntil and equipped do
			cdLabel.Text = tostring(math.ceil(cooldownUntil - os.clock()))
			task.wait(0.2)
		end
		if os.clock() >= cooldownUntil then
			onCooldown = false
			btn.ImageColor3 = Color3.fromRGB(255, 255, 255)
			cdLabel.Text = ""
		end
	end)
end
local function beginCooldown()
	cooldownUntil = os.clock() + SPIN_COOLDOWN
	onCooldown = true
	runCooldownDisplay()
end

SpinRemote.OnClientEvent:Connect(function(msg)
	if msg == "spinEnded" then
		isSpinning = false   -- 회전 끝 → 무기 전환 다시 허용
		setBackpack(true)    -- 백팩 잠금 해제
		beginCooldown()      -- 회전이 다 끝난 시점부터 쿨다운 시작
	end
end)

btn.MouseButton1Click:Connect(fireSpin)
-- PC: F 키 (무기 스킬 통일키). 장착 중 + 버튼 표시 상태에서만
_UIS.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if not gui.Enabled then return end
	if input.KeyCode == Enum.KeyCode.F then
		fireSpin()
	end
end)

Tool.Equipped:Connect(function()
	equipped = true
	gui.Enabled = true
	-- 들 때마다 버튼 상태 초기화
	onCooldown = false
	btn.ImageColor3 = Color3.fromRGB(255, 255, 255)   -- 아이콘 밝기 복원
	cdLabel.Text = ""
end)

Tool.Unequipped:Connect(function()
	equipped = false
	gui.Enabled = false
	if spinConn then spinConn:Disconnect(); spinConn = nil end
	onCooldown = false
	isSpinning = false
	setBackpack(true)        -- 안전: 무기 벗으면 백팩 항상 복원 (잠긴 채 남지 않게)
	cdLabel.Text = ""
	btn.ImageColor3 = Color3.fromRGB(255, 255, 255)   -- 아이콘 밝기 복원
	-- 자동정렬 복원
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then hum.AutoRotate = true end
end)

-- ─── 백팩 UI 복구 안전망 (스킬 중 라운드 종료 대응) ───
-- HammerLow가 차징/시전 중 백팩을 끄는데, 스킬 중 툴이 파괴/회수되면 복구 코드가
-- 실행 안 돼 백팩이 꺼진 채 잔존 → 다음 라운드 무기 장착 불가. 다단계로 확실히 켠다.
local function _restoreBackpack()
	pcall(function() setBackpack(true) end)
end
Tool.Destroying:Connect(function()
	_restoreBackpack()
	task.delay(0.6, _restoreBackpack)
	task.delay(1.8, _restoreBackpack)
end)
Tool.Unequipped:Connect(function()
	task.delay(0.1, _restoreBackpack)  -- 정상 해제 시에도 안전 복구 (스킬 안 켜졌으면 무해)
end)

-- 재장착 시 남은 쿨 표시 재개 (해제로 표시 루프가 죽어도 cooldownUntil은 유지)
Tool.Equipped:Connect(function()
	task.defer(function()
		if os.clock() < cooldownUntil then
			onCooldown = true
			runCooldownDisplay()
		end
	end)
end)
