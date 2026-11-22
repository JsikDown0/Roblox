-- ReviveClient
-- 부활 시스템 클라이언트 처리
--
-- 기능:
--   1. 부활자 시점: 다운자 근처일 때 E키 홀드 프롬프트 표시
--   2. E키 홀드 → 서버에 start 요청, 떼면 stop 요청
--   3. 모든 클라이언트: 진행 중인 부활의 다운자 머리 위 진행 바 표시
--   4. 다운자 시점: "(이름)이 부활 중 (X%)" 안내
--   5. 부활 후 무적 시각 효과 (반짝임)

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")   -- [REVIVE-HEALICON] 아이콘 맥동용

local localPlayer = Players.LocalPlayer
local stateEvent   = ReplicatedStorage:WaitForChild("ReviveStateChanged")
local requestEvent = ReplicatedStorage:WaitForChild("ReviveRequestEvent")

-- ── 설정 ────────────────────────────────────────────────
local REVIVE_KEY      = Enum.KeyCode.E
local REVIVE_DISTANCE = 10   -- ⚠️ ReviveSystem 의 REVIVE_DISTANCE 와 반드시 동일 (4 → 7 → 10)
                             --    범위 서클 크기도 이 값을 참조하므로 표시가 자동으로 따라간다.
local REVIVE_HOLD_SLACK = 1   -- 홀드 유지에만 주는 여유 (서버 ReviveSystem 과 동일)

-- ── 상태 ────────────────────────────────────────────────
-- 진행 중 부활: target -> { reviver, progress(0~1) }
local activeRevives = {}
-- 부활자 머리 위 진행 바: target -> { billboard, fillBar, label }
local progressBars = {}
-- 부활자 본인 측 프롬프트 UI
local promptGui = nil
local promptFrame = nil
local promptLabel = nil
-- 다운자 본인 측 안내 UI
local rescueInfoGui = nil
local rescueInfoLabel = nil
-- 본인이 E 홀드 중인지
local isHolding = false

-- ─────────────────────────────────────────────────────────────
-- 다운된 캐릭터 추적 (DownStateChanged 이벤트 필요)
-- ─────────────────────────────────────────────────────────────
local downedCharacters = {}  -- character -> true

local downStateEvent = ReplicatedStorage:WaitForChild("DownStateChanged")
downStateEvent.OnClientEvent:Connect(function(eventType, character)
    if eventType == "character_downed" and character then
        downedCharacters[character] = true
    elseif eventType == "downed" then
        local char = localPlayer.Character
        if char then downedCharacters[char] = true end
    elseif eventType == "character_died" or eventType == "character_revived" then
        if character then downedCharacters[character] = nil end
    elseif eventType == "died" or eventType == "revived" then
        local char = localPlayer.Character
        if char then downedCharacters[char] = nil end
    end
end)

-- ─────────────────────────────────────────────────────────────
-- 부활자 측 프롬프트 UI (E 홀드 안내)
-- ─────────────────────────────────────────────────────────────
local function getPromptGui()
    if promptGui and promptGui.Parent then return promptGui end

    promptGui = Instance.new("ScreenGui")
    promptGui.Name = "RevivePromptGui"
    promptGui.ResetOnSpawn = false
    promptGui.IgnoreGuiInset = true
    promptGui.Enabled = false
    promptGui.Parent = localPlayer:WaitForChild("PlayerGui")

    promptFrame = Instance.new("Frame")
    promptFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    promptFrame.Position = UDim2.new(0.5, 0, 0.6, 0)
    promptFrame.Size = UDim2.new(0, 280, 0, 56)
    promptFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    promptFrame.BackgroundTransparency = 0.3
    promptFrame.BorderSizePixel = 0
    promptFrame.Parent = promptGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = promptFrame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(120, 220, 120)
    stroke.Thickness = 2
    stroke.Parent = promptFrame

    promptLabel = Instance.new("TextLabel")
    promptLabel.Size = UDim2.new(1, 0, 1, 0)
    promptLabel.BackgroundTransparency = 1
    promptLabel.Text = "[E] Hold to revive"
    promptLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    promptLabel.TextSize = 22
    promptLabel.Font = Enum.Font.GothamBold
    promptLabel.Parent = promptFrame

    return promptGui
end

local function showPrompt(targetName)
    local gui = getPromptGui()
    gui.Enabled = true
    -- 플랫폼별 안내: 모바일에 "[E]"를 띄우면 누를 키가 없어 방법을 알 수 없다.
    local hint = UserInputService.TouchEnabled and "Hold to revive" or "[E] Hold to revive"
    promptLabel.Text = targetName and (hint .. " " .. targetName) or hint
end

local function hidePrompt()
    if promptGui then promptGui.Enabled = false end
end

-- ─────────────────────────────────────────────────────────────
-- 다운자 본인 측 "(이름)이 부활 중 (X%)" UI
-- ─────────────────────────────────────────────────────────────
local function getRescueInfoGui()
    if rescueInfoGui and rescueInfoGui.Parent then return rescueInfoGui end

    rescueInfoGui = Instance.new("ScreenGui")
    rescueInfoGui.Name = "ReviveRescueInfoGui"
    rescueInfoGui.ResetOnSpawn = false
    rescueInfoGui.IgnoreGuiInset = true
    rescueInfoGui.Enabled = false
    rescueInfoGui.Parent = localPlayer:WaitForChild("PlayerGui")

    local frame = Instance.new("Frame")
    frame.AnchorPoint = Vector2.new(0.5, 0)
    frame.Position = UDim2.new(0.5, 0, 0.18, 0)  -- 화면 상단 중앙
    frame.Size = UDim2.new(0, 360, 0, 60)
    frame.BackgroundColor3 = Color3.fromRGB(20, 30, 20)
    frame.BackgroundTransparency = 0.2
    frame.BorderSizePixel = 0
    frame.Parent = rescueInfoGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(120, 220, 120)
    stroke.Thickness = 2
    stroke.Parent = frame

    rescueInfoLabel = Instance.new("TextLabel")
    rescueInfoLabel.Size = UDim2.new(1, 0, 1, 0)
    rescueInfoLabel.BackgroundTransparency = 1
    rescueInfoLabel.Text = ""
    rescueInfoLabel.TextColor3 = Color3.fromRGB(180, 255, 180)
    rescueInfoLabel.TextSize = 20
    rescueInfoLabel.Font = Enum.Font.GothamBold
    rescueInfoLabel.Parent = frame

    return rescueInfoGui
end

local function showRescueInfo(reviverName, progress)
    local gui = getRescueInfoGui()
    gui.Enabled = true
    rescueInfoLabel.Text = string.format("🩹 %s reviving (%d%%)",
        reviverName or "동료", math.floor(progress * 100))
end

local function hideRescueInfo()
    if rescueInfoGui then rescueInfoGui.Enabled = false end
end

-- ────────────────────────────────────────────────────────────────
-- 부활 기회 표시 (라운드 중에만, 내 것만)
--   UsedRevive 는 캐릭터 속성이라 서버 이벤트 없이 바로 구독 가능하다.
--   단 캐릭터가 교체되면 속성도 새 캐릭터로 옮겨가므로 재구독이 필요하다.
--   라운드 여부는 ReplicatedStorage.RoundPhase 속성을 쓴다(HudButtonClient 와 동일 규약).
-- ────────────────────────────────────────────────────────────────
local chanceGui, chanceLabel = nil, nil
local chanceFrame = nil   -- [REVIVE-POS] EmotionBarGui 로 옮겨진 실제 표시 프레임
local chanceAttrConn = nil

local function getChanceGui()
	if chanceGui and chanceGui.Parent then return chanceGui end

	local Scaler = require(ReplicatedStorage:WaitForChild("ResponsiveScaler"))
	local isMobile = Scaler.isMobile()
	-- (DOWN_Y / DOWN_H 는 SOS 버튼과 높이를 맞추려던 값이었으나
	--  아래 REVIVE-POS 로 배치 방식을 바꾸면서 쓰이지 않게 되어 제거)
	local W      = isMobile and 110 or 140
	local H      = isMobile and 36 or 44

	chanceGui = Instance.new("ScreenGui")
	chanceGui.Name = "ReviveChanceGui"
	chanceGui.ResetOnSpawn = false
	chanceGui.IgnoreGuiInset = true
	chanceGui.DisplayOrder = 5
	chanceGui.Enabled = true    -- 껍데기. 실제 표시는 frame.Visible 로 제어
	chanceGui.Parent = localPlayer:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Name = "ChanceFrame"
	frame.AnchorPoint = Vector2.new(0, 1)   -- 좌측 하단 기준
	-- [REVIVE-POS] 이모트 패널 바로 위에 붙인다.
	--   ⚠️ 고정 계산(BASE_Y - 바높이 - 여백)으로는 안 된다. EmotionBarClient 는
	--      상황에 따라 세 가지 다른 기준으로 배치된다:
	--        ①모바일 라운드중: 화면 중앙 좌측(scale 0.5)
	--        ②모바일 로비    : 우측 하단
	--        ③PC            : LoadoutPreviewGui.Root 아래에 붙임(있을 때) / BASE_Y(없을 때)
	--      ③ 때문에 PC 에서 실제 위치가 계산값과 어긋나 붙어 보였다(실측 2026-08-21: 간격 38px).
	--   → 이모트 패널의 실제 AbsolutePosition 을 읽어 그 '아래'에 붙인다. 분기와 무관하게 따라간다.
	--   ⚠️ '위'가 아니라 '아래'인 이유: 모바일 라운드 중엔 EmoteBar 가 화면 세로 중앙
	--      (AnchorPoint 0,0.5 / Position 0.5,-60)이라, 위에 붙이면 REVIVE 가 화면 상단으로 튄다
	--      (실측 2026-08-21 모바일 실기기). 아래로 붙이면 모바일·PC 둘 다 자연스럽다.
	-- ⚠️ [REVIVE-POS] 좌표 추종을 버리고 EmoteBar 의 '자식'으로 붙인다.
	--    세 번 고쳤는데 세 번 다 재발한 이유:
	--      ① EmoteBar 에 UIListLayout 이 있어 이모트 장착/해제마다 크기가 바뀐다
	--         (실측: size.X 56 ↔ 164). 0.5초 폴링으로는 못 따라간다.
	--      ② 배치 기준이 상황마다 다르다(모바일 라운드/로비, PC 의 LoadoutPreview 추종).
	--      ③ 두 GUI 의 UIScale 이 달라 AbsolutePosition 환산이 매번 어긋난다.
	--    자식으로 붙이면 같은 좌표계·같은 UIScale 을 쓰므로 위 셋이 통째로 사라진다.
	--    부모가 움직이든 커지든 자동으로 따라간다. 폴링도 필요 없다.
	--    ⚠️ EmoteBar '자식'으로 넣으면 안 된다 — 거기 UIListLayout(Horizontal)이 있어
	--       이모트 버튼들 사이에 끼어들고 Position 이 무시된다.
	--       대신 '형제'(같은 ScreenGui 직속)로 두고 EmoteBar 를 추종한다.
	--       같은 GUI 라 UIScale 이 동일해 환산이 필요 없다.
	--       EmotionBarClient:207 이 LoadoutBox 를 같은 방식으로 붙인다 — 그 패턴을 따른다.
	local GAP = 8
	local GAP_BELOW = 18   -- 이모트 바와의 세로 간격(스케일 전 기준)
	local function syncToBar(bar)
		if not (bar and bar.Parent) then return end
		frame.AnchorPoint = bar.AnchorPoint
		frame.Size = UDim2.fromOffset(W, H)
		-- 부모 좌표계가 같으므로 EmoteBar 의 Position 에 높이만 더하면 된다.
		-- ⚠️ AbsoluteSize 를 쓰면 안 된다. 그건 UIScale 이 적용된 '실제 픽셀'인데
		--    Position.Offset 은 '스케일 전' 값이라 단위가 어긋난다.
		--    실측 2026-08-22: 모바일(scale 0.55)에서 간격이 의도의 절반으로 줄어 붙어 보였다.
		--    → Size.Y.Offset(스케일 전 고정값 68)을 쓴다.
		-- ⚠️ AnchorPoint 를 바에서 그대로 받아오므로 세로 기준이 상황마다 다르다.
		--    (라운드 중 0.5=중앙 / 로비 1=하단). 중앙 기준일 때는 두 요소의 '절반'씩을
		--    더해야 실제로 아래에 놓인다.
		local barH = bar.Size.Y.Offset
		local ay   = bar.AnchorPoint.Y
		local dy   = (ay == 0.5) and (barH * 0.5 + GAP_BELOW + H * 0.5)
		                          or (barH + GAP_BELOW)
		frame.Position = UDim2.new(
			bar.Position.X.Scale, bar.Position.X.Offset,
			bar.Position.Y.Scale, bar.Position.Y.Offset + dy)
	end

	local function attachToEmoteBar()
		local pg = localPlayer:FindFirstChild("PlayerGui")
		local ebg = pg and pg:FindFirstChild("EmotionBarGui")
		local bar = ebg and ebg:FindFirstChild("EmoteBar")
		if not (bar and bar:IsA("GuiObject")) then return false end
		frame.Parent = ebg          -- 형제로 배치
		syncToBar(bar)
		-- 위치·크기·앵커가 바뀔 때마다 즉시 따라간다(폴링 불필요).
		--   ⚠️ UIListLayout 때문에 이모트 장착/해제 시 AbsoluteSize 가 바뀐다(56 ↔ 164).
		bar:GetPropertyChangedSignal("Position"):Connect(function() syncToBar(bar) end)
		bar:GetPropertyChangedSignal("Size"):Connect(function() syncToBar(bar) end)
		bar:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() syncToBar(bar) end)
		bar:GetPropertyChangedSignal("AnchorPoint"):Connect(function() syncToBar(bar) end)
		return true
	end

	if not attachToEmoteBar() then
		-- EmoteBar 가 아직 없으면(로드 순서) 생길 때까지 기다렸다 붙인다.
		frame.Position = UDim2.new(0, isMobile and 12 or 20, 1, -280)
		frame.Size = UDim2.fromOffset(W, H)
		task.spawn(function()
			for _ = 1, 40 do
				task.wait(0.25)
				if attachToEmoteBar() then return end
			end
			warn("[ReviveClient] EmoteBar 를 못 찾아 폴백 위치 사용")
		end)
	end
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	frame.BackgroundTransparency = 0.3
	frame.BorderSizePixel = 0
	-- ⚠️ [REVIVE-POS] 부모는 attachToEmoteBar 가 EmotionBarGui 로 정한다.
	--    여기서 chanceGui 로 되돌리면 그 설정이 덮어써진다(순서상 뒤).
	--    ScreenGui(chanceGui)는 이제 껍데기로만 남고 실제 표시는 frame.Visible 로 제어한다.
	if not frame.Parent then frame.Parent = chanceGui end
	chanceFrame = frame   -- [REVIVE-POS] refreshChance 가 Visible 로 제어하도록 보관

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Name = "Edge"
	stroke.Color = Color3.fromRGB(140, 230, 140)
	stroke.Thickness = 2
	stroke.Parent = frame

	chanceLabel = Instance.new("TextLabel")
	chanceLabel.Name = "Label"
	chanceLabel.Size = UDim2.new(1, 0, 1, 0)
	chanceLabel.BackgroundTransparency = 1
	chanceLabel.Font = Enum.Font.GothamBold
	chanceLabel.TextSize = isMobile and 14 or 17
	chanceLabel.Text = ""
	chanceLabel.Parent = frame

	return chanceGui
end

local function refreshChance()
	local gui = getChanceGui()
	local phase = ReplicatedStorage:GetAttribute("RoundPhase")
	local inRound = (phase == "stage1" or phase == "stage2")
	local char = localPlayer.Character
	-- ⚠️ [REVIVE-POS] 프레임이 EmotionBarGui 로 옮겨졌으므로 gui.Enabled 로는 못 끈다.
	--    표시는 frame.Visible 로 제어한다. chanceFrame 은 모듈 상단에서 보관한다.
	local frame = chanceFrame
	-- 👑 [2026-08-27] 태거에게는 숨긴다. 부활은 러너 전용 개념이라 태거에겐 항상 "REVIVE 1"
	--   이 붙박이로 떠 있었고, 그 자리를 ChargeStackClient(SLAM POWER)가 쓰기로 했다.
	--   ⚠️ frame 을 만들긴 한다(Visible=false). ChargeStackClient 가 이 프레임의 좌표를
	--     슬롯으로 삼아 따라가기 때문 — 여기서 생성을 건너뛰면 그쪽 배치가 폴백으로 떨어진다.
	--   ⚠️ Role 은 라운드 시작 시 세팅되므로 refreshChance 가 RoundPhase 변화로 다시 돌 때
	--     올바른 값이 잡힌다.
	if localPlayer:GetAttribute("Role") == "Tagger" then
		if frame then frame.Visible = false end
		return
	end
	if not (inRound and char) then
		if frame then frame.Visible = false end
		return
	end

	local used = char:GetAttribute("UsedRevive") and true or false
	local stroke = frame and frame:FindFirstChild("Edge")
	if used then
		chanceLabel.Text = "REVIVE  0"
		chanceLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
		if stroke then stroke.Color = Color3.fromRGB(90, 90, 90) end
	else
		chanceLabel.Text = "REVIVE  1"
		chanceLabel.TextColor3 = Color3.fromRGB(180, 255, 180)
		if stroke then stroke.Color = Color3.fromRGB(140, 230, 140) end
	end
	if frame then frame.Visible = true end
end

local function bindChanceToCharacter(char)
	if chanceAttrConn then chanceAttrConn:Disconnect() end
	if not char then return end
	chanceAttrConn = char:GetAttributeChangedSignal("UsedRevive"):Connect(refreshChance)
	refreshChance()
end

ReplicatedStorage:GetAttributeChangedSignal("RoundPhase"):Connect(refreshChance)
localPlayer.CharacterAdded:Connect(bindChanceToCharacter)
if localPlayer.Character then bindChanceToCharacter(localPlayer.Character) end

-- ────────────────────────────────────────────────────────────────
-- 부활 가능 범위 원 (다운된 본인 + 주변 아군 모두에게 표시)
--   다운 상태인 캐릭터마다 반경 REVIVE_DISTANCE 의 바닥 원을 띄운다.
--   태거에게는 표시하지 않는다 — 다운된 러너 위치를 알려주는 표식이 되기 때문.
--   downedCharacters 는 이미 이 스크립트가 관리하는 목록이라 그대로 재사용한다.
-- ────────────────────────────────────────────────────────────────
local rangeCircles = {}   -- character -> Part

local function makeRangeCircle()
	local p = Instance.new("Part")
	p.Name = "ReviveRangeCircle"
	p.Shape = Enum.PartType.Cylinder
	-- Cylinder 는 원형 단면이 X 축이라, 눕히려면 Z 로 90도 회전시켜야 한다.
	p.Size = Vector3.new(0.2, REVIVE_DISTANCE * 2, REVIVE_DISTANCE * 2)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.ForceField   -- Neon 은 지면과 깊이 충돌(번쩍임)이 심함
	p.Color = Color3.fromRGB(255, 70, 70)   -- map1 언덕 초록과 겹쳐 빨강으로
	p.Transparency = 0.5
	p.Parent = workspace
	return p
end

local function clearRangeCircle(char)
	local c = rangeCircles[char]
	if c then
		c:Destroy()
		rangeCircles[char] = nil
	end
end

RunService.Heartbeat:Connect(function()
	local isTagger = (localPlayer:GetAttribute("Role") == "Tagger")

	if not isTagger then
		for char in pairs(downedCharacters) do
			local hrp = char and char.Parent and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				local c = rangeCircles[char]
				if not (c and c.Parent) then
					c = makeRangeCircle()
					rangeCircles[char] = c
				end
				-- 발밑에 깔리도록 살짝 내린다
				-- 바닥 법선을 받아 원판을 지형 기울기에 맞춘다.
				-- 언덕에서 수평으로 두면 절반이 땅에 파묻히거나 공중에 떠 보인다.
				local origin = hrp.Position
				local rayParams = RaycastParams.new()
				rayParams.FilterType = Enum.RaycastFilterType.Exclude
				rayParams.FilterDescendantsInstances = { char, workspace:FindFirstChild("ReviveRangeCircle") }
				local hit = workspace:Raycast(origin, Vector3.new(0, -12, 0), rayParams)
				local groundPos = hit and hit.Position or (origin - Vector3.new(0, 2.8, 0))
				local groundNormal = hit and hit.Normal or Vector3.new(0, 1, 0)
				-- Cylinder 는 원형 단면이 X 축이므로, X 축을 법선 방향으로 세운다.
				local up = groundNormal
				local side = up:Cross(Vector3.new(0, 0, 1))
				if side.Magnitude < 0.01 then side = up:Cross(Vector3.new(1, 0, 0)) end
				side = side.Unit
				local fwd = side:Cross(up).Unit
				-- CFrame.fromMatrix(pos, xVec, yVec, zVec) — x 를 법선으로 두면 원판이 눕는다
				c.CFrame = CFrame.fromMatrix(groundPos + up * 0.35, up, side, fwd)
			end
		end
	end

	-- 다운이 풀렸거나 태거 시점이면 정리
	for char in pairs(rangeCircles) do
		if isTagger or not downedCharacters[char] or not (char and char.Parent) then
			clearRangeCircle(char)
		end
	end
end)

-- ─────────────────────────────────────────────────────────────
-- 다운자 머리 위 진행 바 (3D BillboardGui, 모든 클라이언트가 봄)
-- ─────────────────────────────────────────────────────────────
-- [REVIVE-HEALICON] 치유 표시 아이콘
--   기존 진행 바만으로는 "치유 중"인지 한눈에 안 읽혀서 초록 + 아이콘을 얹는다.
--   ⚠️ 별도 BillboardGui 를 만들지 않고 기존 것 안에 넣는다 —
--      정리 경로(removeProgressBar)가 하나뿐이라 취소·완료 어느 쪽이든 같이 사라진다.
-- ⚠️ 업로드로 받은 ID(122470350724166)는 Decal 이라 ImageLabel 에 넣으면 안 그려진다.
--    아래는 그 Decal 안의 실제 Image ID (InsertService:LoadAsset 으로 추출).
--    앞으로도 이미지 올린 뒤 안 보이면 AssetTypeId 부터 확인할 것 (13=Decal, 1=Image).
local HEAL_ICON_ID   = "rbxassetid://133794907160143"
local HEAL_ICON_PX   = 34     -- 아이콘 한 변(픽셀)
local BAR_PX         = 14     -- 기존 진행 바 높이(변경 금지 — 아래 오프셋 보정과 짝)
local ICON_GAP_PX    = 6      -- 아이콘과 바 사이 간격
local BOARD_PX       = HEAL_ICON_PX + ICON_GAP_PX + BAR_PX
--   빌보드가 위아래로 커지면 바가 그만큼 내려앉는다. 커진 높이의 절반만큼 올려 보정.
--   (픽셀↔스터드는 거리 의존이라 정확한 환산은 불가 — 눈으로 맞춘 근삿값)
local BOARD_STUDS_Y  = 4.5 + 0.55

local function createProgressBar(target)
    if progressBars[target] then return progressBars[target] end

    local head = target:FindFirstChild("Head")
    if not head then return nil end

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "ReviveProgressBar"
    billboard.Size = UDim2.new(0, 120, 0, BOARD_PX)
    billboard.StudsOffset = Vector3.new(0, BOARD_STUDS_Y, 0)  -- 머리 위 (SOS 아이콘보다 살짝 위)
    billboard.AlwaysOnTop = true
    billboard.LightInfluence = 0
    billboard.Adornee = head
    billboard.Parent = head

    -- 치유 아이콘 (바 위쪽 중앙)
    local icon = Instance.new("ImageLabel")
    icon.Name = "HealIcon"
    icon.Image = HEAL_ICON_ID
    icon.BackgroundTransparency = 1
    icon.AnchorPoint = Vector2.new(0.5, 0)
    icon.Position = UDim2.new(0.5, 0, 0, 0)
    icon.Size = UDim2.new(0, HEAL_ICON_PX, 0, HEAL_ICON_PX)
    icon.Parent = billboard

    -- 맥동: "진행 중"임을 정적 아이콘보다 확실히 전달. 홀드가 1.5초라 두어 번 뛴다.
    local pulse = TweenService:Create(
        icon,
        TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        { ImageTransparency = 0.45 }
    )
    pulse:Play()

    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(1, 0, 0, BAR_PX)
    bg.Position = UDim2.new(0, 0, 1, -BAR_PX)   -- 빌보드 하단 정렬
    bg.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    bg.BackgroundTransparency = 0.3
    bg.BorderSizePixel = 0
    bg.Parent = billboard

    local bgCorner = Instance.new("UICorner")
    bgCorner.CornerRadius = UDim.new(1, 0)
    bgCorner.Parent = bg

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(120, 220, 120)
    fill.BorderSizePixel = 0
    fill.Parent = bg

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = fill

    progressBars[target] = {
        billboard = billboard,
        fill      = fill,
        pulse     = pulse,
    }
    return progressBars[target]
end

local function updateProgressBar(target, progress)
    local bar = createProgressBar(target)
    if bar and bar.fill then
        bar.fill.Size = UDim2.new(progress, 0, 1, 0)
    end
end

local function removeProgressBar(target)
    local bar = progressBars[target]
    if not bar then return end
    -- [REVIVE-HEALICON] 맥동 트윈부터 정리. 인스턴스가 사라지면 트윈도 멈추지만
    --   명시적으로 취소해 두는 편이 안전하다(끄는 코드는 켜는 코드와 같은 자리에).
    if bar.pulse then bar.pulse:Cancel() end
    if bar.billboard then bar.billboard:Destroy() end
    progressBars[target] = nil
end

-- ─────────────────────────────────────────────────────────────
-- 부활 후 무적 반짝임 (사용자 본인이 부활했을 때)
-- ─────────────────────────────────────────────────────────────
local function playInvulFlash(character)
    local hl = character:FindFirstChild("ReviveInvulHighlight")
    if hl then hl:Destroy() end
    local highlight = Instance.new("Highlight")
    highlight.Name = "ReviveInvulHighlight"
    highlight.FillColor = Color3.fromRGB(180, 255, 200)
    highlight.FillTransparency = 0.6
    highlight.OutlineColor = Color3.fromRGB(120, 255, 150)
    highlight.OutlineTransparency = 0
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = character

    -- 반짝임 효과: 1초간 깜박이며 사라짐
    task.spawn(function()
        local startTime = tick()
        while tick() - startTime < 1.0 and highlight.Parent do
            highlight.FillTransparency = 0.4 + math.abs(math.sin(tick() * 12)) * 0.4
            task.wait()
        end
        if highlight and highlight.Parent then highlight:Destroy() end
    end)
end

-- ─────────────────────────────────────────────────────────────
-- 가장 가까운 다운자 찾기 (반경 내, 클라이언트 측 — 프롬프트 표시용)
-- ─────────────────────────────────────────────────────────────
local function findNearestDowned(slack)
    local myChar = localPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil end

    local closest, closestDist = nil, math.huge
    for char, _ in pairs(downedCharacters) do
        if char and char.Parent and char ~= myChar then
            local hum = char:FindFirstChildOfClass("Humanoid")
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hum and hum.Health > 0 and hrp then
                local dist = (myRoot.Position - hrp.Position).Magnitude
                if dist <= REVIVE_DISTANCE + (slack or 0) and dist < closestDist then
                    closest = char
                    closestDist = dist
                end
            end
        end
    end
    return closest
end

-- ─────────────────────────────────────────────────────────────
-- 메인 루프: 프롬프트 표시 + UI 갱신
-- ─────────────────────────────────────────────────────────────
RunService.RenderStepped:Connect(function()
    local myChar = localPlayer.Character

    -- 본인이 다운 중인 경우: rescueInfo UI 갱신
    if myChar and myChar:GetAttribute("Downed") then
        hidePrompt()  -- 다운 중엔 부활자 프롬프트 안 보임
        local reviveInfo = activeRevives[myChar]
        if reviveInfo then
            local reviverName = reviveInfo.reviver and reviveInfo.reviver.Name or "동료"
            showRescueInfo(reviverName, reviveInfo.progress or 0)
        else
            hideRescueInfo()
        end
        return
    end
    hideRescueInfo()

    -- 본인이 살아있는 러너인 경우: 근처 다운자 검색 + 프롬프트 표시
    -- 태거이거나 다운 상태면 프롬프트 안 보임
    if localPlayer:GetAttribute("Role") == "Tagger" then
        hidePrompt()
        return
    end

    -- 이 검사는 매 프레임 돈다. 여유가 없으면 한 프레임만 범위를 벗어나도
    -- 아래 else 에서 홀드가 통째로 취소된다(게이지가 중간에 끊기는 원인이었음).
    -- 서버 REVIVE_HOLD_SLACK 과 같은 규약 — 시작 판정(beginHold)은 여유 없이 7 유지.
    local nearest = findNearestDowned(isHolding and REVIVE_HOLD_SLACK or 0)
    if nearest then
        -- 이미 다른 사람이 부활 시도 중이면 프롬프트 다르게 표시
        local existing = activeRevives[nearest]
        if existing and existing.reviver ~= myChar then
            showPrompt("(이미 시도 중)")
        else
            showPrompt(nearest.Name)
        end
    else
        hidePrompt()
        -- 근처 다운자가 사라졌는데 E를 누르고 있던 상태면 stop 보냄
        if isHolding then
            isHolding = false
            requestEvent:FireServer("stop")
        end
    end
end)

-- ─────────────────────────────────────────────────────────────
-- 입력: E 홀드 시작/종료 (모바일은 프롬프트 버튼 터치로 동일 로직 호출)
-- ─────────────────────────────────────────────────────────────
-- 홀드 시작/종료를 함수로 분리 — 키보드(E)와 터치 버튼이 같은 경로를 쓰게 한다.
-- 분리 전에는 InputBegan 안에 로직이 박혀 있어 모바일에서 부활이 아예 불가능했다.
local function beginHold()
    if isHolding then return end
    local myChar = localPlayer.Character
    if not myChar then return end
    if myChar:GetAttribute("Downed") then return end
    if localPlayer:GetAttribute("Role") == "Tagger" then return end

    -- 근처 다운자 있어야 시작
    local nearest = findNearestDowned()
    if not nearest then return end

    isHolding = true
    requestEvent:FireServer("start")
end

local function endHold()
    if isHolding then
        isHolding = false
        requestEvent:FireServer("stop")
    end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode ~= REVIVE_KEY then return end
    beginHold()
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
    if input.KeyCode ~= REVIVE_KEY then return end
    endHold()
end)

-- 모바일: 프롬프트 자체를 누를 수 있게 한다.
-- promptFrame 은 getPromptGui() 최초 호출 시 생성되므로 여기서 지연 연결.
task.spawn(function()
    while not promptFrame do task.wait(0.2) end
    local touchBtn = Instance.new("TextButton")
    touchBtn.Name = "TouchHoldButton"
    touchBtn.Size = UDim2.new(1, 0, 1, 0)
    touchBtn.BackgroundTransparency = 1
    touchBtn.Text = ""
    touchBtn.AutoButtonColor = false
    touchBtn.ZIndex = 5
    touchBtn.Parent = promptFrame

    touchBtn.MouseButton1Down:Connect(beginHold)
    touchBtn.MouseButton1Up:Connect(endHold)
    -- 버튼 밖으로 손가락이 빠져나가도 홀드가 끊기도록
    touchBtn.MouseLeave:Connect(endHold)
end)

-- ─────────────────────────────────────────────────────────────
-- 서버 이벤트 처리
-- ─────────────────────────────────────────────────────────────
stateEvent.OnClientEvent:Connect(function(eventType, target, ...)
    if eventType == "progress_started" then
        local reviver, duration = ...
        activeRevives[target] = {
            reviver  = reviver,
            progress = 0,
        }
        createProgressBar(target)
        updateProgressBar(target, 0)

    elseif eventType == "progress_update" then
        local progress = ...
        if activeRevives[target] then
            activeRevives[target].progress = progress
        end
        updateProgressBar(target, progress)

    elseif eventType == "progress_cancelled" then
        activeRevives[target] = nil
        removeProgressBar(target)
        -- 본인이 시도 중이었으면 isHolding 리셋
        if target then
            local myChar = localPlayer.Character
            if myChar and activeRevives[target] and activeRevives[target].reviver == myChar then
                isHolding = false
            end
        end

    elseif eventType == "revive_completed" then
        activeRevives[target] = nil
        removeProgressBar(target)

        -- 🔊 보호막 생성음. 각 클라가 자기 쪽에서 재생한다.
        -- ⚠️ [이력] 원래 서버(ReviveSystem)에서 Sound 를 만들어 Play() 했는데,
        --    서버 진단상 len=3.92 / playing=true 였는데도 클라에서 안 들렸다.
        --    (SoundService.RespectFilteringEnabled = true 환경)
        --    이 이벤트는 FireAllClients 로 모든 클라에 오므로 여기서 재생하면 전원이 듣는다.
        -- ⚠️ 가공 금지: PlaybackSpeed / EqualizerSoundEffect 를 걸었다가 소리가 죽었다.
        --    원본 그대로 재생한다.
        do
            local hrp = target and target:FindFirstChild("HumanoidRootPart")
            if hrp then
                local sfx = Instance.new("Sound")
                sfx.Name = "_ReviveShieldSfx"
                sfx.SoundId = "rbxassetid://133835353564397"
                sfx.Volume = 2               -- 이 게임 효과음 관례(1.4~3.5)의 중간
                sfx.RollOffMaxDistance = 90  -- 부활은 국지적 사건 — 전장 끝까지 들릴 필요 없음
                sfx.Parent = hrp
                sfx:Play()
                game:GetService("Debris"):AddItem(sfx, 5)
            end
        end

        -- 본인이 부활됐으면 무적 반짝임 효과
        if target == localPlayer.Character then
            playInvulFlash(target)
        end
    end
end)

-- ─────────────────────────────────────────────────────────────
-- 캐릭터 재생성 시 정리
-- ─────────────────────────────────────────────────────────────
localPlayer.CharacterAdded:Connect(function()
    isHolding = false
    -- 머리 위 바들 정리
    for target, _ in pairs(progressBars) do
        removeProgressBar(target)
    end
    activeRevives = {}
    hidePrompt()
    hideRescueInfo()
end)

print("✅ ReviveClient 활성화 (E 홀드로 부활,", REVIVE_DISTANCE, "stud 이내)")
