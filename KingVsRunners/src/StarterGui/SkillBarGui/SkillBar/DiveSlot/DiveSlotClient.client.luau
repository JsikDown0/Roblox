-- DiveSlotClient — 산데비스탄 (RunnerDive) 스킬 슬롯 UI 컨트롤러
-- 책임:
--   1) 아이콘 버튼 클릭 → _G.RunnerDive.try() 호출 (Q 키와 동등)
--   2) 쿨다운 시각화 (위에서 아래로 채워지는 어둠 오버레이 + 남은 초 텍스트)
--   3) 사용 가능 / 쿨다운 / 다운 / 비러너 상태 시각 표현
--   4) 모바일에서 키 힌트 자동 숨김

local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local Players    = game:GetService("Players")

local player = Players.LocalPlayer

local slot           = script.Parent                       -- DiveSlot Frame
local iconButton     = slot:WaitForChild("IconButton")     -- ImageButton
local cooldownOverlay = slot:WaitForChild("CooldownOverlay") -- Frame
local cooldownText   = slot:WaitForChild("CooldownText")   -- TextLabel
local keyHint        = slot:WaitForChild("KeyHint")        -- TextLabel
local slotStroke     = slot:WaitForChild("UIStroke")        -- 슬롯 외곽선

-- 모바일 노치/펀치홀 자동 회피 (ScreenInsets = SafeAreaInsets)
local _gui = slot:FindFirstAncestorOfClass("ScreenGui")
if _gui then
	pcall(function() _gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)
end

-- ── 반응형 스케일 + 디바이스별 위치 (공통 모듈) ──────────────────
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Scaler = require(ReplicatedStorage:WaitForChild("ResponsiveScaler"))
local screenGui = slot:FindFirstAncestorOfClass("ScreenGui")
local skillBar  = slot.Parent  -- SkillBar Frame (위치 조정 대상)

-- 디바이스별 위치 설정
local SKILLBAR_POS = {
	-- MOBA식 부채꼴 슬롯1 (우하단 모서리 기준). offset × UIScale(0.55) = 실제px
	--   슬롯1 Q(여기) / 슬롯2 무기스킬(-155,-160) / 슬롯3 예약(-273,-82)
	Mobile = UDim2.new(1, -36, 1, -218),  -- 실제 right-20 / bottom-120 (점프버튼 위)
	-- [DASH-POS] PC Y: -20 → -180 (2026-08-21). 무기 스킬 버튼(F)과 중심 높이를 맞춘다.
	--   무기 스킬은 SKILLBTN_POS.PC = (1, -365, 1, -170), 크기 150.
	--   ⚠️ 두 버튼은 AnchorPoint(1,1) 이라 Position.Y 가 '하단'이고 크기가 다르다(130 vs 150).
	--      하단을 맞추면 중심이 어긋난다. 중심 기준으로 역산해야 한다:
	--        강타 중심 = -(170 + 150/2) = -245
	--        대시 하단 = 중심 + 130/2  = -245 + 65 = -180
	--   ⚠️ 여기를 바꾸면 무기 스킬 버튼 5종의 SKILLBTN_POS 도 함께 재계산해야 한다. 두 값이 짝이다.
	--   가로: 대시 좌측끝 -290 / 강타 우측끝 -365 → 75px 간격으로 안 겹침.
	PC     = UDim2.new(1, -160, 1, -180),
}

-- 스케일은 모듈에 위임 (위치는 핫스왑 위해 아래서 직접 관리)
if screenGui then
	Scaler.applyEdge(screenGui, nil, {
		baseW = 1280, baseH = 720,
		Mobile = { minScale = 0.55 },
		PC     = { minScale = 0.55 },
	})
end

-- 슬롯 크기 (스크립트에서 지정 — 인스턴스 속성은 Ctrl+S 없이 롤백되므로)
--   Mobile 100 × 0.55 = 55px / PC 130 × UIScale = 마우스 클릭용으로 크게
local SLOT_SIZE = { Mobile = 100, PC = 130 }

-- 디바이스별 위치·크기 (디바이스 핫스왑 대응)
local function updateSkillBarPosition()
	local dev = Scaler.device()
	local sz  = SLOT_SIZE[dev] or SLOT_SIZE.PC
	skillBar.Size = UDim2.fromOffset(sz, sz)
	slot.Size     = UDim2.fromOffset(sz, sz)
	skillBar.Position = SKILLBAR_POS[dev]
end
updateSkillBarPosition()
UIS:GetPropertyChangedSignal("KeyboardEnabled"):Connect(updateSkillBarPosition)
UIS:GetPropertyChangedSignal("TouchEnabled"):Connect(updateSkillBarPosition)

-- 색상 상수
local COLOR_READY    = Color3.fromRGB(80, 220, 255)   -- 청록 (산데비스탄 발광색)
local COLOR_COOLDOWN = Color3.fromRGB(100, 100, 110)  -- 회색 (쿨다운 중)
local COLOR_LOCKED   = Color3.fromRGB(180, 50, 50)    -- 빨강 (다운/사용 불가)

-- 모바일에서 키 힌트 자동 숨김
local function updateKeyHintVisibility()
	if UIS.TouchEnabled and not UIS.KeyboardEnabled then
		keyHint.Visible = false
	else
		keyHint.Visible = true
	end
end
updateKeyHintVisibility()
UIS:GetPropertyChangedSignal("KeyboardEnabled"):Connect(updateKeyHintVisibility)

-- 클릭 / 탭 → 산데비스탄 발동
iconButton.Activated:Connect(function()
	if _G.RunnerDive and _G.RunnerDive.try then
		_G.RunnerDive.try()
	end
end)

-- 매 프레임 상태 갱신
-- [DASH-HINT] 버튼 왼쪽에 붙는 말풍선. 라운드당 1회, 첫 N판만.
-- ⚠️ blinkIcon 은 아래(3층 블록)에서 정의되지만 1층에서도 써야 한다.
--    전방 선언으로 순서를 푼다. 실제 호출은 스크립트 로드 후이므로 안전하다.
local blinkIcon

-- 라벨을 DiveSlot '바로 위'에 놓는다.
--   ⚠️ 라벨은 ScreenGui 직속이라 Position 이 화면 기준이다. 슬롯의 실제 위치를 읽어 환산한다.
--      (slot 에 붙이면 ClipsDescendants 로 잘리고, skillBar 에 붙이면 UIListLayout 이 덮어쓴다)
local function placeAboveSlot(lbl)
	if not (lbl and skillBar and skillBar.Parent) then return end
	-- ⚠️ AbsolutePosition 으로 계산하면 안 된다. ScreenGui 에 UIScale(Scaler.applyEdge)이
	--    걸려 있어 AbsolutePosition(실제 픽셀)과 Position(스케일 적용 전) 단위가 다르다.
	--    실측 2026-08-22: 그대로 넣었더니 라벨이 좌상단으로 밀렸다(REVIVE 때와 같은 유형).
	--    → skillBar 의 Position/Size 를 그대로 써서 '같은 좌표계'로 계산한다.
	--      두 요소가 같은 UIScale 아래 있으므로 배율이 자동으로 상쇄된다.
	--    skillBar 는 AnchorPoint(1,1) 이라 Position 이 '우하단' 지점이다:
	--      중심 X = Position.X - Size.X/2 ,  상단 Y = Position.Y - Size.Y
	local p, s = skillBar.Position, skillBar.Size
	-- ⚠️ 중앙 정렬은 안 된다. 모바일은 아이콘이 화면 오른쪽 끝(-36)에 붙어 있어
	--    라벨(250폭)을 중앙에 맞추면 오른쪽으로 39px 넘쳐 잘린다(실측 2026-08-22).
	--    → 라벨 '오른쪽 끝'을 아이콘 오른쪽 끝에 맞춘다. 어느 플랫폼이든 화면 안에 남는다.
	lbl.AnchorPoint = Vector2.new(1, 1)
	lbl.Position = UDim2.new(
		p.X.Scale, p.X.Offset,
		p.Y.Scale, p.Y.Offset - s.Y.Offset - 12)
end

local HINT_ROUNDS   = 3     -- 누적 라운드가 이 값 미만일 때만 표시
local HINT_DURATION = 5.0   -- 표시 시간(초)
local hintShownThisRound = false
local hintLabel = nil

local function showDashHintOnce()
	if hintShownThisRound then return end
	local rp = player:GetAttribute("RoundsPlayed")
	-- 속성이 없으면(로드 전) 신규로 간주 — 보수적으로 보여주는 쪽
	if rp ~= nil and rp >= HINT_ROUNDS then return end
	hintShownThisRound = true

	if not hintLabel then
		hintLabel = Instance.new("TextLabel")
		hintLabel.Name = "_DashHint"
		-- ⚠️ 왼쪽에 두면 3층에서 무기 스킬 버튼(강타 등)에 가려진다.
		--    위쪽은 비어 있으므로 아이콘 바로 위에 띄운다.
		hintLabel.AnchorPoint = Vector2.new(0.5, 1)
		hintLabel.Position = UDim2.new(0.5, 0, 0, -12)   -- 버튼 위
		hintLabel.Size = UDim2.fromOffset(250, 48)
		hintLabel.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
		hintLabel.BackgroundTransparency = 0.08
		hintLabel.Font = Enum.Font.GothamBold
		hintLabel.TextSize = 19
		hintLabel.TextColor3 = Color3.fromRGB(150, 235, 255)
		hintLabel.TextWrapped = true
		-- ⚠️ 모바일은 KeyHint("Q")가 숨겨져 있어 "Q"라고 쓰면 무슨 말인지 모른다.
		--    기능 이름(Dash)으로 통일하고, 어느 버튼인지는 아이콘 점멸이 알려준다.
		hintLabel.Text = "Dash to dodge items"
		hintLabel.ZIndex = 30
		hintLabel.Active = false
		hintLabel.Selectable = false
		-- ⚠️ 부모 선택 주의:
		--    · slot(DiveSlot)  → ClipsDescendants=true 라 바깥 라벨이 잘린다
		--    · skillBar        → UIListLayout(Horizontal/Right/Bottom)이 있어
		--                        Position 이 무시되고 슬롯 왼쪽에 자동 배치된다
		--    → ScreenGui 직속에 두고 슬롯의 실제 위치를 읽어 따라간다.
		hintLabel.Parent = screenGui
		Instance.new("UICorner", hintLabel).CornerRadius = UDim.new(0.25, 0)
		local st = Instance.new("UIStroke", hintLabel)
		st.Color = Color3.fromRGB(120, 210, 240) ; st.Thickness = 2
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end

	placeAboveSlot(hintLabel)
	hintLabel.Visible = true
	-- 아이콘도 함께 강조 — 문구만으론 어느 버튼인지 모른다(특히 모바일).
	if blinkIcon then blinkIcon(HINT_DURATION) end
	task.delay(HINT_DURATION, function()
		if hintLabel then hintLabel.Visible = false end
	end)
end

-- 라운드가 바뀌면 다시 보여줄 수 있게 초기화
task.spawn(function()
	local last = nil
	while true do
		task.wait(1)
		local ph = ReplicatedStorage:GetAttribute("RoundPhase")
		local inRound = (ph == "stage1" or ph == "stage2")
		if inRound ~= last then
			last = inRound
			if not inRound then hintShownThisRound = false end
		end
	end
end)

-- [GRAB-ESCAPE-HINT] 그랩당한 순간 "대시로 빠져나갈 수 있다"를 알린다.
--   ⚠️ 이건 숨겨진 기믹이라 안 알리면 '아는 사람만 아는 버그 플레이'로 보인다.
--      다만 매번 띄우면 강요처럼 느껴지므로 첫 그랩 한 번만 보여준다.
--   ⚠️ 모바일에는 키 힌트가 없어 문구만으론 어느 버튼인지 모른다 → 아이콘을 점멸시킨다.
--   ⚠️ Stunned 는 카타나 카운터(SwordScript:268)도 쓰지만 그건 '태거'에게 거는 것이라
--      러너 화면에는 영향이 없다.
-- ⚠️ 세션 한정. 접속 중에는 첫 그랩 한 번만 뜬다.
--    재접속하면 다시 뜨지만, RoundsPlayed < 3 가드가 있어 첫 3판 안으로 제한된다.
local escapeHintShown = false
local escapeLabel = nil
local blinkToken = 0

-- 아이콘 강조: 테두리 점멸 + 크기 펄스(커졌다 줄었다).
--   ⚠️ 크기는 slot.Size 를 직접 건드리면 update() 의 SLOT_SIZE 재설정과 충돌한다.
--      UIScale 을 따로 얹어 그것만 조절한다.
local function getPulseScale()
	local s = slot:FindFirstChild("_PulseScale")
	if not s then
		s = Instance.new("UIScale")
		s.Name = "_PulseScale"
		s.Parent = slot
	end
	return s
end

blinkIcon = function(duration)
	blinkToken = blinkToken + 1
	local myToken = blinkToken
	local savedStroke = slotStroke and slotStroke.Color
	local pulse = getPulseScale()
	task.spawn(function()
		local TS = game:GetService("TweenService")
		local t0 = tick()
		while tick() - t0 < duration and myToken == blinkToken do
			if slotStroke then
				TS:Create(slotStroke, TweenInfo.new(0.22), { Color = Color3.fromRGB(120, 240, 255), Thickness = 7 }):Play()
			end
			TS:Create(pulse, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Scale = 1.28 }):Play()
			task.wait(0.22)
			if myToken ~= blinkToken then break end
			if slotStroke then
				TS:Create(slotStroke, TweenInfo.new(0.22), { Color = Color3.fromRGB(255, 255, 255), Thickness = 2 }):Play()
			end
			TS:Create(pulse, TweenInfo.new(0.22, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
			task.wait(0.22)
		end
		-- 원상 복구 (다른 점멸이 시작됐으면 그쪽에 맡긴다)
		if myToken == blinkToken then
			if slotStroke then
				slotStroke.Color = savedStroke or Color3.fromRGB(255, 255, 255)
				slotStroke.Thickness = 2
			end
			TS:Create(pulse, TweenInfo.new(0.2), { Scale = 1 }):Play()
		end
	end)
end

local function showEscapeHint()
	if escapeHintShown then return end
	if player:GetAttribute("Role") ~= "Runner" then return end
	local rp = player:GetAttribute("RoundsPlayed")
	if rp ~= nil and rp >= HINT_ROUNDS then return end
	escapeHintShown = true

	if not escapeLabel then
		escapeLabel = Instance.new("TextLabel")
		escapeLabel.Name = "_EscapeHint"
		-- ⚠️ 왼쪽은 무기 스킬 버튼과 겹친다(실측 2026-08-22). 아이콘 위로 띄운다.
		escapeLabel.AnchorPoint = Vector2.new(0.5, 1)
		escapeLabel.Position = UDim2.new(0.5, 0, 0, -12)
		escapeLabel.Size = UDim2.fromOffset(270, 52)
		escapeLabel.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
		escapeLabel.BackgroundTransparency = 0.06
		escapeLabel.Font = Enum.Font.GothamBlack
		escapeLabel.TextSize = 21
		escapeLabel.TextColor3 = Color3.fromRGB(160, 245, 255)
		escapeLabel.TextWrapped = true
		escapeLabel.Text = "You can Dash to escape"
		escapeLabel.ZIndex = 30
		escapeLabel.Active = false
		escapeLabel.Selectable = false
		-- ⚠️ skillBar 는 UIListLayout 이 있어 Position 이 무시된다. ScreenGui 직속에 둔다.
		escapeLabel.Parent = screenGui
		Instance.new("UICorner", escapeLabel).CornerRadius = UDim.new(0.25, 0)
		local st = Instance.new("UIStroke", escapeLabel)
		st.Color = Color3.fromRGB(120, 220, 250) ; st.Thickness = 2
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end
	placeAboveSlot(escapeLabel)
	escapeLabel.Visible = true
	blinkIcon(2.5)
	task.delay(2.5, function()
		if escapeLabel then escapeLabel.Visible = false end
	end)
end

-- 내 캐릭터의 Stunned 가 켜지는 순간을 잡는다.
local function bindStunWatch(char)
	if not char then return end
	char:GetAttributeChangedSignal("Stunned"):Connect(function()
		if char:GetAttribute("Stunned") then showEscapeHint() end
	end)
end
player.CharacterAdded:Connect(bindStunWatch)
if player.Character then bindStunWatch(player.Character) end

local function update()
	-- _G.RunnerDive 가 아직 로드 안 됐으면 슬롯 숨김
	if not _G.RunnerDive then
		slot.Visible = false
		return
	end

	-- 역할이 러너가 아니면 슬롯 숨김
	-- ⚠️ [2026-09-07] 로비 무기 체험장 예외.
	--   RunnerDive:502 에 같은 Role 검사가 있어 대시 자체는 열었는데, 버튼을 그리는
	--   여기가 그대로라 "대시는 되는데 아이콘만 안 보이는" 상태가 됐다.
	--   같은 규칙이 두 곳에 있으면 한쪽만 고쳐진다 — 그 재현이다.
	local role = player:GetAttribute("Role")
	local trialActive = player:GetAttribute("WeaponTrialActive")
	if role ~= "Runner" and not trialActive then
		slot.Visible = false
		return
	end
	-- ⚠️ [2026-09-08] King 도구를 든 동안에는 슬롯도 숨긴다.
	--   RunnerDive 가 같은 조건으로 대시를 막는다(그쪽 502행 근처).
	--   버튼만 남으면 "눌리는데 안 나가는" 상태가 되어 더 헷갈린다.
	--   ⚠️ 위 주석이 경고한 그 함정이다 — 두 곳을 반드시 짝으로 유지할 것.
	if trialActive then
		local ch = player.Character
		if ch and ch:FindFirstChild("PushTool") then
			slot.Visible = false
			return
		end
	end
	slot.Visible = true

	-- [DASH-HINT] 신규 유저에게 Q 가 뭔지 알려준다.
	--   ⚠️ 대시는 아이템이 아니라 라운드 시작 시 기본 장착되는 스킬이라
	--      인벤/상점 툴팁 경로가 없다. 안 알려주면 존재 자체를 모른다.
	--   ⚠️ 라운드 중이므로 화면을 가리면 안 된다 → 버튼 옆 작은 말풍선.
	--   ⚠️ RoundsPlayed 로 첫 N판만. 숙련자에겐 잔소리가 된다.
	showDashHintOnce()

	-- 다운 상태 체크
	local character = player.Character
	local isDowned  = character and character:GetAttribute("Downed") or false
	-- 🚫 [2026-08-27] 배럴 웅덩이 안 = 대시 봉인. 다운과 같은 '사용 불가' 표시를 쓴다.
	--   ⚠️ 표시가 없으면 "Q 를 눌렀는데 아무 일도 안 난다" 가 되어 버그로 읽힌다.
	--     봉인 자체보다 봉인이 보이는 게 중요하다(RunnerDive 가 조용히 return 하므로).
	local inSpill   = character and character:GetAttribute("InBarrelSpill") or false
	local isLocked  = isDowned or inSpill

	local remaining = _G.RunnerDive.cooldownRemaining()
	local total     = _G.RunnerDive.COOLDOWN
	local ready     = _G.RunnerDive.isReady()

	if isLocked then
		-- 다운 중 / 웅덩이 안: 빨간 외곽선 + 어둠 풀로 채워짐 + 텍스트 숨김
		slotStroke.Color = COLOR_LOCKED
		cooldownOverlay.Size = UDim2.new(1, 0, 1, 0)
		cooldownOverlay.BackgroundTransparency = 0.2
		cooldownText.Visible = false
		iconButton.ImageTransparency = 0.5
		iconButton.Active = false
	elseif ready then
		-- 사용 가능: 청록 외곽선 + 오버레이 없음 + 텍스트 숨김
		slotStroke.Color = COLOR_READY
		cooldownOverlay.Size = UDim2.new(1, 0, 0, 0)
		cooldownText.Visible = false
		iconButton.ImageTransparency = 0
		iconButton.Active = true
	else
		-- 쿨다운 중: 회색 외곽선 + 위에서 아래로 채워지는 오버레이 + 남은 초
		slotStroke.Color = COLOR_COOLDOWN
		local fillRatio = math.clamp(remaining / total, 0, 1)
		cooldownOverlay.Size = UDim2.new(1, 0, fillRatio, 0)
		cooldownOverlay.BackgroundTransparency = 0.4
		cooldownText.Visible = true
		cooldownText.Text = string.format("%.1f", remaining)
		iconButton.ImageTransparency = 0.3
		iconButton.Active = false
	end
end

RunService.Heartbeat:Connect(update)
update()

print("✅ DiveSlotClient (산데비스탄 스킬 슬롯) 준비!")
