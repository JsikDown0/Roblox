local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- ── 모바일 대응 UIScale + 노치 회피 ────────────────────────────
do
	local _gui = script.Parent
	pcall(function() _gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)
	local _camera = workspace.CurrentCamera
	local _uiScale = _gui:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", _gui)
	local _BASE_W, _BASE_H = 1280, 720
	local function _update()
		local vp = _camera.ViewportSize
		local s = math.min((vp.X * 0.85) / _BASE_W, (vp.Y * 0.85) / _BASE_H, 1)
		_uiScale.Scale = math.max(s, 0.55)
	end
	_camera:GetPropertyChangedSignal("ViewportSize"):Connect(_update)
	_update()
end

local player = Players.LocalPlayer

local taggerInvenGui = script.Parent               -- TaggerInven ScreenGui
local canvas         = taggerInvenGui:WaitForChild("Canvas")
local main           = canvas:WaitForChild("Main")
local switchicon     = taggerInvenGui:WaitForChild("Switchicon")
local container      = main:WaitForChild("Container")
local tooltip        = main:WaitForChild("Tooltip")
local tooltipMain    = tooltip:WaitForChild("Main")
local closeBtn       = main:WaitForChild("Close")

-- ✅ checkmark 원본: TaggerInven 직속 (Canvas.Main 아님!)
local checkmarkSource = taggerInvenGui:FindFirstChild("checkmark")
if checkmarkSource then checkmarkSource.Visible = false end

-- _G 스텁
_G.openTaggerInven  = function() end
_G.closeTaggerInven = function() end

-- 초기 상태
canvas.Visible     = false
main.Visible       = true
switchicon.Visible = false

-- 하단 Equip 버튼 TextLabel
local bottomEquipBtn   = main:FindFirstChild("Equip")
local bottomEquipLabel = bottomEquipBtn
    and bottomEquipBtn:FindFirstChild("Main")
    and bottomEquipBtn.Main:FindFirstChildWhichIsA("TextLabel")

local getLoadout = ReplicatedStorage:WaitForChild("GetPlayerLoadout")
local setLoadout = ReplicatedStorage:WaitForChild("SetPlayerLoadout")

-- ── 레어리티 색상 ─────────────────────────────────────────────
local rarityColors = {
    Common    = Color3.fromRGB(200, 200, 200),
    Uncommon  = Color3.fromRGB(80,  200, 80),
    Rare      = Color3.fromRGB(80,  140, 230),
    Epic      = Color3.fromRGB(160, 80,  220),
    Legendary = Color3.fromRGB(255, 160, 0),
    Mythical  = Color3.fromRGB(255, 80,  120),
}

-- 등급별 UIGradient ColorSequence (Stroke 테두리)
local rarityGradient = {
    Normal    = ColorSequence.new(Color3.fromRGB(180, 180, 180), Color3.fromRGB(255, 255, 255)),
    Rare      = ColorSequence.new(Color3.fromRGB(40,  160, 40),  Color3.fromRGB(120, 255, 120)),
    Epic      = ColorSequence.new(Color3.fromRGB(120, 40,  200), Color3.fromRGB(200, 120, 255)),
    Legendary = ColorSequence.new({
        ColorSequenceKeypoint.new(0,    Color3.fromRGB(255, 200, 0)),
        ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 255, 160)),
        ColorSequenceKeypoint.new(0.5,  Color3.fromRGB(255, 130, 0)),
        ColorSequenceKeypoint.new(0.75, Color3.fromRGB(255, 230, 80)),
        ColorSequenceKeypoint.new(1,    Color3.fromRGB(255, 200, 0)),
    }),
}
local LOCKED_GRADIENT = ColorSequence.new(Color3.fromRGB(60, 60, 60), Color3.fromRGB(100, 100, 100))
-- Legendary 테두리 회전 애니메이션
local legendaryGrads = {}
local function startLegendaryGlow(grad)
    if not grad or legendaryGrads[grad] then return end
    legendaryGrads[grad] = true
    task.spawn(function()
        local rot = 0
        while grad and grad.Parent do
            rot = (rot + 3.09) % 360
            grad.Rotation = rot
            task.wait(0.03)
        end
        legendaryGrads[grad] = nil
    end)
end

local GREEN_GRADIENT = ColorSequence.new({
    ColorSequenceKeypoint.new(0,    Color3.fromRGB(68,  68,  195)),
    ColorSequenceKeypoint.new(0.21, Color3.fromRGB(0,   255, 0)),
    ColorSequenceKeypoint.new(0.92, Color3.fromRGB(133, 236, 95)),
    ColorSequenceKeypoint.new(1,    Color3.fromRGB(0,   255, 0)),
})
local RED_GRADIENT = ColorSequence.new({
    ColorSequenceKeypoint.new(0,    Color3.fromRGB(120, 20,  20)),
    ColorSequenceKeypoint.new(0.21, Color3.fromRGB(220, 40,  40)),
    ColorSequenceKeypoint.new(0.92, Color3.fromRGB(255, 80,  80)),
    ColorSequenceKeypoint.new(1,    Color3.fromRGB(200, 30,  30)),
})

local equippedItems      = {}
local templateMap        = {}
local currentTooltipItem = nil

-- ── 경고 UI ──────────────────────────────────────────────────
-- 기존 프레임이 있으면 항상 제거하고 새로 만듦 (누적 방지)
local oldWarning = main:FindFirstChild("_EquipWarning")
if oldWarning then oldWarning:Destroy() end

local warningTween  = nil
local warningThread = nil

local warningFrame = Instance.new("Frame")
warningFrame.Name = "_EquipWarning"
warningFrame.Size = UDim2.new(0.75, 0, 0, 60)
warningFrame.AnchorPoint = Vector2.new(0.5, 0)
warningFrame.Position = UDim2.new(0.5, 0, 0, 8)
warningFrame.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
warningFrame.BackgroundTransparency = 0.1
warningFrame.ZIndex = 20
warningFrame.Visible = false
warningFrame.Parent = main
Instance.new("UICorner", warningFrame).CornerRadius = UDim.new(0, 10)
local st = Instance.new("UIStroke", warningFrame)
st.Color = Color3.fromRGB(255, 100, 100); st.Thickness = 2
-- ⚠️ 아이콘 (왼쪽 고정)
local warnIcon = Instance.new("TextLabel", warningFrame)
warnIcon.Name = "_WarnIcon"
warnIcon.Size = UDim2.new(0, 40, 1, 0)
warnIcon.Position = UDim2.new(0, 8, 0, 0)
warnIcon.BackgroundTransparency = 1
warnIcon.Text = "⚠️"
warnIcon.TextSize = 20
warnIcon.Font = Enum.Font.GothamBold
warnIcon.ZIndex = 21
-- 메시지 텍스트 (아이콘 오른쪽)
local warningLabel = Instance.new("TextLabel", warningFrame)
warningLabel.Name = "_WarnMsg"
warningLabel.Size = UDim2.new(1, -56, 1, 0)
warningLabel.Position = UDim2.new(0, 48, 0, 0)
warningLabel.BackgroundTransparency = 1
warningLabel.Text = ""
warningLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
warningLabel.TextSize = 15
warningLabel.TextXAlignment = Enum.TextXAlignment.Left
warningLabel.Font = Enum.Font.GothamBold
warningLabel.ZIndex = 21

local function showEquipWarning(msg)
    if warningLabel then warningLabel.Text = msg or "Max 4 items can be equipped!" end
    if warningTween  then warningTween:Cancel() end
    if warningThread then task.cancel(warningThread) end
    warningFrame.BackgroundTransparency = 0.1
    warningFrame.Visible = true
    warningThread = task.delay(1.5, function()
        warningTween = TweenService:Create(warningFrame,
            TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {BackgroundTransparency = 1})
        warningTween:Play()
        warningTween.Completed:Connect(function()
            warningFrame.Visible = false
            warningFrame.BackgroundTransparency = 0.1
        end)
    end)
end

-- ── Tooltip 요소 ─────────────────────────────────────────────
local tooltipNameLabel, tooltipRarityLabel
local tidx = 0
for _, c in ipairs(tooltipMain:GetChildren()) do
    if c:IsA("TextLabel") then
        tidx += 1
        if tidx == 1 then tooltipNameLabel   = c end
        if tidx == 2 then tooltipRarityLabel = c end
    end
end

local tooltipEquip   = tooltipMain:FindFirstChild("Equip")
local tooltipSkin    = tooltipMain:FindFirstChild("Skin")
local tooltipClose2  = tooltipMain:FindFirstChild("Close2")
local equipTextLabel = tooltipEquip and tooltipEquip:FindFirstChildWhichIsA("TextLabel")
local equipGradient  = tooltipEquip and tooltipEquip:FindFirstChildWhichIsA("UIGradient")

local function equippedCount()
    local n = 0
    for _ in pairs(equippedItems) do n += 1 end
    return n
end

local function refreshBottomEquip()
    if bottomEquipLabel then
        bottomEquipLabel.Text = string.format("Equip (%d/4)", equippedCount())
    end
end

-- ── 체크마크 생성 ─────────────────────────────────────────────
-- Template 직속, ZIndex=4 (_ClickBtn=3보다 위 → 시각적으로 보임)
local function ensureCheckMark(template)
    if template:FindFirstChild("_CheckMark") then return end

    local check
    if checkmarkSource then
        check = checkmarkSource:Clone()  -- 원본 이미지 복제
    else
        -- 폴백: 이모지 TextLabel
        check = Instance.new("TextLabel")
        check.BackgroundColor3      = Color3.fromRGB(30, 170, 60)
        check.BackgroundTransparency = 0
        check.Text                  = "✔"
        check.TextColor3            = Color3.fromRGB(255, 255, 255)
        check.TextScaled            = true
        check.Font                  = Enum.Font.GothamBold
        Instance.new("UICorner", check).CornerRadius = UDim.new(0.3, 0)
    end

    check.Name        = "_CheckMark"
    check.Size        = UDim2.new(0.35, 0, 0.35, 0)
    check.AnchorPoint = Vector2.new(1, 1)
    check.Position    = UDim2.new(1, 0, 1, 0)   -- 슬롯 우측 하단
    check.ZIndex      = 4  -- ✅ _ClickBtn(3)보다 위, 확실히 보임
    check.Visible     = false
    check.Parent      = template  -- ✅ Template 직속
end

local function saveLoadout()
    local list = {}
    for name in pairs(equippedItems) do table.insert(list, name) end
    if #list == 0 then return end
    setLoadout:FireServer(list)
    print("✅ 로드아웃 저장:", table.concat(list, ", "))
end

local function refreshCheckMarks()
    for template, itemData in pairs(templateMap) do
        local check = template:FindFirstChild("_CheckMark")
        if check then
            check.Visible = equippedItems[itemData.name] == true
        end
    end
end

local function refreshTooltipButtons()
    if not currentTooltipItem then return end
    local isEquipped = equippedItems[currentTooltipItem.name] == true
    if equipTextLabel then equipTextLabel.Text = isEquipped and "Unequip" or "Equip" end
    if equipGradient  then equipGradient.Color = isEquipped and RED_GRADIENT or GREEN_GRADIENT end
end

local function showTooltip(itemData, isLocked, fromTemplate)
    currentTooltipItem = itemData
    if tooltipNameLabel then tooltipNameLabel.Text = itemData.displayName or itemData.name end
    if tooltipRarityLabel then
        tooltipRarityLabel.Text = itemData.rarity or ""
        local rColor = {
            Normal    = Color3.fromHex("#9d9d9d"),
            Rare      = Color3.fromHex("#4cd964"),
            Epic      = Color3.fromHex("#b44fff"),
            Legendary = Color3.fromHex("#ffd700"),
        }
        tooltipRarityLabel.TextColor3 = rColor[itemData.rarity] or Color3.fromHex("#9d9d9d")
    end
    if tooltipEquip then tooltipEquip.Visible = not isLocked end
    if tooltipSkin  then tooltipSkin.Visible  = not isLocked end
    refreshTooltipButtons()

    -- ✅ 클릭한 슬롯 위치 기반으로 툴팁 위치 계산
    if fromTemplate then
        -- AbsolutePosition/Size로 main 기준 상대 좌표 계산
        local mainAbs     = main.AbsolutePosition
        local mainSize    = main.AbsoluteSize
        local tAbs        = fromTemplate.AbsolutePosition
        local tSize       = fromTemplate.AbsoluteSize
        local tipSize     = tooltip.AbsoluteSize
        local slotCenterX = (tAbs.X - mainAbs.X + tSize.X * 0.5) / mainSize.X
        local slotCenterY = (tAbs.Y - mainAbs.Y + tSize.Y * 0.5) / mainSize.Y
        local slotW = tSize.X / mainSize.X
        local slotH = tSize.Y / mainSize.Y

        -- 툴팁 너비/높이 (Scale)
        local tipW = tipSize.X / mainSize.X
        local tipH = tipSize.Y / mainSize.Y

        -- X: 슬롯 오른쪽 끝에서 시작 (우측 배치)
        local posX = slotCenterX + slotW * 0.5 - tipW * 0.55
        if posX + tipW > 1.0 then
            posX = slotCenterX - slotW * 0.5 - tipW * 0.45
        end

        -- Y: 슬롯 중앙(절반)에서 툴팁 시작 → 하단 절반 차지
        local posY = slotCenterY
        posY = math.clamp(posY, 0.02, 1 - tipH - 0.02)

        tooltip.Position    = UDim2.new(posX, 0, posY, 0)
        tooltip.AnchorPoint = Vector2.new(0, 0)   -- 좌상단 기준
    end

    tooltip.Visible = true
end

if tooltipEquip then
    tooltipEquip.MouseButton1Click:Connect(function()
        if not currentTooltipItem then return end
        local name = currentTooltipItem.name
        if equippedItems[name] then
            if equippedCount() <= 1 then
                showEquipWarning("At least 1 item must be equipped!")
                return
            end
            equippedItems[name] = nil
        else
            if equippedCount() >= 4 then
                showEquipWarning()
                return
            end
            equippedItems[name] = true
        end
        saveLoadout()
        refreshCheckMarks()
        refreshTooltipButtons()
        refreshBottomEquip()
    end)
end


-- ── 보유 아이템 필터 토글 ─────────────────────────────────────
-- _G.ownedOnlyState 로 Tagger/Runner 간 공유
local function getOwned() return _G.ownedOnlyState == true end
local function setOwned(v) _G.ownedOnlyState = v end
local cachedAllItems = nil
local cachedHasPass  = false

local toggleFrame = main:FindFirstChild("_OwnedToggle")
local toggleFill  = toggleFrame and toggleFrame:FindFirstChild("_Fill")
local lblAll      = toggleFrame and toggleFrame:FindFirstChild("_LblAll")
local lblOwned    = toggleFrame and toggleFrame:FindFirstChild("_LblOwned")
local toggleBtn   = toggleFrame and toggleFrame:FindFirstChild("_ToggleBtn")

-- 모바일 대응: Scale 기반으로 크기 재설정
if toggleFrame then
	toggleFrame.Size     = UDim2.new(0.18, 0, 0.09, 0)
	toggleFrame.Position = UDim2.new(0.75, 0, 0.095, 0)
	if lblAll   then lblAll.TextScaled = true; lblAll.Text   = "All"   end
	if lblOwned then lblOwned.TextScaled = true; lblOwned.Text = "Owned" end
end
local TWEEN_TOGGLE = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function applyToggleVisual()
	if not toggleFill then return end
	local owned = getOwned()
	local targetPos = owned and UDim2.new(0.5, 0, 0, 0) or UDim2.new(0, 0, 0, 0)
	TweenService:Create(toggleFill, TWEEN_TOGGLE, {Position = targetPos}):Play()
	toggleFill.BackgroundColor3 = owned and Color3.fromRGB(50, 160, 255) or Color3.fromRGB(80, 80, 80)
	if lblAll   then lblAll.TextColor3   = owned and Color3.fromRGB(180,180,180) or Color3.fromRGB(255,255,255) end
	if lblOwned then lblOwned.TextColor3 = owned and Color3.fromRGB(255,255,255) or Color3.fromRGB(180,180,180) end
end

-- ── 슬롯 채우기 ──────────────────────────────────────────────
local function populateSlots(allItems, hasPass)
	local displayItems = allItems
	if getOwned() then
		displayItems = {}
		for _, item in ipairs(allItems) do
			local locked = item.locked or (item.premium and not hasPass)
			if not locked then
				table.insert(displayItems, item)
			end
		end
	end

    local templates = {}
    for _, c in ipairs(container:GetChildren()) do
        if c:IsA("Frame") and c.Name == "Template" then
            table.insert(templates, c)
        end
    end
    templateMap = {}

    for i, template in ipairs(templates) do
        local itemData  = displayItems[i]
        local mainFrame = template:FindFirstChild("Main")

        local old = template:FindFirstChild("_ClickBtn")
        if old then old:Destroy() end
        local oldCheck = template:FindFirstChild("_CheckMark")
        if oldCheck then oldCheck:Destroy() end


        ensureCheckMark(template)

        -- 아이템 없는 슬롯은 숨김 처리
        if not itemData then
            template.Visible = false
        else
            template.Visible = true
            templateMap[template] = itemData

            if mainFrame then
                local tIdx = 0
                for _, c in ipairs(mainFrame:GetChildren()) do
                    if c:IsA("TextLabel") then
                        tIdx += 1
                        if     tIdx == 1 then c.Text = "Lv 1"
                        elseif tIdx == 2 then c.Text = itemData.displayName or itemData.name
                        end
                    end
                end
            end

            local isLocked = itemData.locked or (itemData.premium and not hasPass)

            -- ✅ Locked 프레임: 소유 아이템이면 숨김, 잠금이면 표시
            local lockedFrame = template:FindFirstChild("Locked")
            if lockedFrame then
                lockedFrame.Visible = isLocked
            end

            local strokeFrame = template:FindFirstChild("Stroke")
            if strokeFrame then
                local uistroke = strokeFrame:FindFirstChildWhichIsA("UIStroke")
                if uistroke then
                    local grad = uistroke:FindFirstChildWhichIsA("UIGradient")
                    if grad then
                        grad.Color = isLocked and LOCKED_GRADIENT or (rarityGradient[itemData.rarity] or rarityGradient.Normal)
                        if not isLocked and itemData.rarity == "Legendary" then
                            startLegendaryGlow(grad)
                        else
                            grad.Rotation = 0
                        end
                    else
                        uistroke.Color = isLocked
                            and Color3.fromRGB(60, 60, 60)
                            or  (rarityColors[itemData.rarity] or rarityColors.Normal)
                    end
                end

                -- Stroke 안 ImageLabel → Glow에 중앙 정렬로 반영
                local iconLabel = strokeFrame:FindFirstChildWhichIsA("ImageLabel")
                local glow = mainFrame and mainFrame:FindFirstChild("Glow")
                if glow and not isLocked then
                    if iconLabel and iconLabel.Image ~= "" then
                        glow.Image             = iconLabel.Image
                        glow.ImageColor3       = Color3.fromRGB(255, 255, 255)
                        glow.ImageTransparency = 0
                        glow.Size              = UDim2.new(0.72, 0, 0.72, 0)
                        glow.Position          = UDim2.new(0.5, 0, 0.46, 0)
                        glow.AnchorPoint       = Vector2.new(0.5, 0.5)
                        glow.ScaleType         = Enum.ScaleType.Fit
                        iconLabel.Visible      = false
                    else
                        glow.ImageTransparency = 1
                    end
                end
            end

            local capturedItem   = itemData
            local capturedLocked = isLocked

            -- ✅ _ClickBtn: ZIndex=3 (체크마크=4보다 낮아서 체크마크가 위에 표시됨)
            local clickBtn = Instance.new("TextButton")
            clickBtn.Name               = "_ClickBtn"
            clickBtn.Size               = UDim2.new(1, 0, 1, 0)
            clickBtn.BackgroundTransparency = 1
            clickBtn.Text               = ""
            clickBtn.ZIndex             = 3
            clickBtn.Parent             = template
            clickBtn.MouseButton1Click:Connect(function()
                if capturedLocked then return end  -- 잠금 → 무반응
                showTooltip(capturedItem, capturedLocked, template)
            end)
        end
    end

    refreshCheckMarks()
    refreshBottomEquip()
end

local function loadData()
    local data = getLoadout:InvokeServer()
    if not data or not data.allItems then
        warn("TaggerInvenClient: 데이터 로드 실패")
        return
    end
    equippedItems = {}
    for _, name in ipairs(data.loadout or {}) do
        equippedItems[name] = true
    end
    -- 캐시 저장 (토글 재필터링에 사용)
    cachedAllItems = data.allItems
    cachedHasPass  = data.hasPass or false
    applyToggleVisual()
    populateSlots(cachedAllItems, cachedHasPass)
end

-- 토글 버튼 클릭 연결
if toggleBtn then
	toggleBtn.MouseButton1Click:Connect(function()
		setOwned(not getOwned())
		applyToggleVisual()
		if _G.syncRunnerToggle then _G.syncRunnerToggle() end  -- Runner 비주얼 동기화
		if cachedAllItems then
			tooltip.Visible    = false
			currentTooltipItem = nil
			populateSlots(cachedAllItems, cachedHasPass)
		end
	end)
end

-- 외부에서 Tagger 비주얼 동기화용
_G.syncTaggerToggle = applyToggleVisual


-- ── 열기 / 닫기 ──────────────────────────────────────────────
local function openInven()
    tooltip.Visible    = false
    currentTooltipItem = nil
    canvas.Visible     = true
    switchicon.Visible = true
    loadData()
end

local function closeInven()
    canvas.Visible     = false
    switchicon.Visible = false
    tooltip.Visible    = false
    currentTooltipItem = nil
    if warningThread then task.cancel(warningThread) end
    if warningFrame  then warningFrame.Visible = false end
    if blueGlow then blueGlow.Visible = false end
    local _skinUI = taggerInvenGui:FindFirstChild("skin ui")
    if _skinUI then _skinUI.Visible = false end
end

_G.openTaggerInven  = openInven
_G.closeTaggerInven = closeInven

closeBtn.MouseButton1Click:Connect(closeInven)
if tooltipClose2 then
    tooltipClose2.MouseButton1Click:Connect(function()
        tooltip.Visible    = false
        currentTooltipItem = nil
    end)
end

print("✅ TaggerInvenClient 준비! checkmark경로 수정 + Switchicon ZIndex=5")

-- ── Switchicon: Tagger ↔ Runner 전환 ─────────────────────────
local function openRunnerInven()
    local pg = game.Players.LocalPlayer:WaitForChild("PlayerGui")
    local newGui = pg:FindFirstChild("NewGui")
    local runnerInven = newGui and newGui:FindFirstChild("RunnerInven")
    if runnerInven then
        runnerInven.Canvas.Visible = true
    end
end

local function closeRunnerInven()
    local pg = game.Players.LocalPlayer:WaitForChild("PlayerGui")
    local newGui = pg:FindFirstChild("NewGui")
    local runnerInven = newGui and newGui:FindFirstChild("RunnerInven")
    if runnerInven then
        runnerInven.Canvas.Visible = false
    end
end

local blueGlow = taggerInvenGui:FindFirstChild("Blue_Glow")
-- Blue_Glow는 TaggerInven 직속 (Canvas 바깥이라 canvas.Visible에 영향 안 받음)

switchicon.MouseButton1Click:Connect(function()
    local pg = game.Players.LocalPlayer:WaitForChild("PlayerGui")
    local newGui = pg:FindFirstChild("NewGui")
    local runnerInven = newGui and newGui:FindFirstChild("RunnerInven")
    if not runnerInven then return end

    local taggerOpen = canvas.Visible
    local runnerOpen = runnerInven.Canvas.Visible

    if taggerOpen then
        -- Tagger → Runner 전환
        if blueGlow then blueGlow.Visible = true end
        canvas.Visible = false
        -- openRunnerInven()으로 데이터 로드까지 함께 처리
        local pg = game.Players.LocalPlayer:WaitForChild("PlayerGui")
        local ng = pg:FindFirstChild("NewGui")
        local ri = ng and ng:FindFirstChild("RunnerInven")
        if ri then
            local openFn = _G.openRunnerInven
            if openFn then
                openFn()
            else
                ri.Canvas.Visible    = true
                ri.Switchicon.Visible = true
            end
        end
    elseif runnerOpen then
        -- Runner → Tagger 전환
        if blueGlow then blueGlow.Visible = false end
        local pg = game.Players.LocalPlayer:WaitForChild("PlayerGui")
        local ng = pg:FindFirstChild("NewGui")
        local ri = ng and ng:FindFirstChild("RunnerInven")
        if ri then
            local closeFn = _G.closeRunnerInven
            if closeFn then closeFn() end
        end
        canvas.Visible = true
    end
end)

_G.openRunnerInven  = openRunnerInven
_G.closeRunnerInven = closeRunnerInven
print("✅ Switchicon 토글 연결 완료")

-- ── Skin UI 연결 ─────────────────────────────────────────────
local skinUI       = taggerInvenGui:FindFirstChild("skin ui")
local skinClose    = skinUI and skinUI:FindFirstChild("skin close")
local skinBar1     = skinUI and skinUI:FindFirstChild("skin bar")
local skinBar2     = skinUI and skinUI:FindFirstChild("skin bar2")
local skinEquip1   = skinBar1 and skinBar1:FindFirstChild("ImageButton")
local skinEquip2   = skinBar2 and skinBar2:FindFirstChild("ImageButton")

local getPlayerSkin = ReplicatedStorage:WaitForChild("GetPlayerSkin")
local setPlayerSkin = ReplicatedStorage:WaitForChild("SetPlayerSkin")

local currentSkinItem = nil  -- 현재 Skin UI에서 보고 있는 아이템 이름

local function updateSkinSlot(skinBar, equipBtn, skinData)
    if not skinBar or not skinData then return end
    -- skin bar 배경에 스킨 아이콘 표시 (ImageLabel이니까 Image 설정)
    -- skinBar 자체는 카드 배경이므로, 내부에 아이콘용 ImageLabel 추가
    local iconLabel = skinBar:FindFirstChild("_SkinIcon")
    if not iconLabel then
        iconLabel = Instance.new("ImageLabel")
        iconLabel.Name = "_SkinIcon"
        iconLabel.AnchorPoint = Vector2.new(0.5, 0.5)
        iconLabel.Position = UDim2.new(0.5, 0, 0.4, 0)
        iconLabel.Size = UDim2.new(1.05, 0, 0.825, 0)  -- 0.7/0.55의 1.5배
        iconLabel.BackgroundTransparency = 1
        iconLabel.ScaleType = Enum.ScaleType.Fit
        iconLabel.ZIndex = skinBar.ZIndex + 1
        iconLabel.Parent = skinBar
    end
    iconLabel.Image = skinData.icon or ""
    
    -- 스킨 이름 표시
    local nameLabel = skinBar:FindFirstChild("_SkinName")
    if not nameLabel then
        nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "_SkinName"
        nameLabel.AnchorPoint = Vector2.new(0.5, 0)
        nameLabel.Position = UDim2.new(0.5, 0, 0.02, 0)
        nameLabel.Size = UDim2.new(0.9, 0, 0.12, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        nameLabel.TextScaled = true
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.ZIndex = skinBar.ZIndex + 1
        nameLabel.Parent = skinBar
    end
    nameLabel.Text = skinData.displayName or ""
    
    -- 잠금 오버레이 (미보유시)
    local lockOverlay = skinBar:FindFirstChild("_LockOverlay")
    if not skinData.owned then
        if not lockOverlay then
            lockOverlay = Instance.new("Frame")
            lockOverlay.Name = "_LockOverlay"
            lockOverlay.AnchorPoint = Vector2.new(0.5, 0.5)
            lockOverlay.Position = UDim2.new(0.5, 0, 0.4, 0)
            lockOverlay.Size = UDim2.new(0.7, 0, 0.55, 0)
            lockOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
            lockOverlay.BackgroundTransparency = 0.5
            lockOverlay.ZIndex = skinBar.ZIndex + 2
            lockOverlay.Parent = skinBar
            Instance.new("UICorner", lockOverlay).CornerRadius = UDim.new(0.05, 0)
            
            local lockIcon = Instance.new("TextLabel")
            lockIcon.AnchorPoint = Vector2.new(0.5, 0.5)
            lockIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
            lockIcon.Size = UDim2.new(1, 0, 0.5, 0)
            lockIcon.BackgroundTransparency = 1
            lockIcon.Text = "🔒"
            lockIcon.TextScaled = true
            lockIcon.ZIndex = skinBar.ZIndex + 3
            lockIcon.Parent = lockOverlay
        end
        lockOverlay.Visible = true
    elseif lockOverlay then
        lockOverlay.Visible = false
    end
    
    -- ✅ Equip 버튼 장착 상태 표시
    if equipBtn then
        local btnLabel = equipBtn:FindFirstChild("_EquipLabel")
        if not btnLabel then
            btnLabel = Instance.new("TextLabel")
            btnLabel.Name = "_EquipLabel"
            btnLabel.AnchorPoint = Vector2.new(0.5, 0.5)
            btnLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
            btnLabel.Size = UDim2.new(1, 0, 1, 0)
            btnLabel.BackgroundTransparency = 1
            btnLabel.TextScaled = true
            btnLabel.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json")
            btnLabel.ZIndex = equipBtn.ZIndex + 1
            btnLabel.Parent = equipBtn
        end
        
        if not skinData.owned then
            btnLabel.Text = "🔒 Locked"
            btnLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
        elseif skinData.equipped then
            btnLabel.Text = "✅ Unequip"
        else
            btnLabel.Text = "Equip"
            btnLabel.TextColor3 = Color3.fromRGB(50, 50, 50)
        end
    end
end

local function refreshSkinUI(itemName)
    if not skinUI then return end
    currentSkinItem = itemName
    
    local skinList = getPlayerSkin:InvokeServer(itemName)
    
    -- 슬롯 1: 첫 번째 스킨
    if skinList and skinList[1] then
        updateSkinSlot(skinBar1, skinEquip1, skinList[1])
        if skinBar1 then skinBar1.Visible = true end
    elseif skinBar1 then
        skinBar1.Visible = false
    end
    
    -- 슬롯 2: 두 번째 스킨 (있으면)
    if skinList and skinList[2] then
        updateSkinSlot(skinBar2, skinEquip2, skinList[2])
        if skinBar2 then skinBar2.Visible = true end
    elseif skinBar2 then
        skinBar2.Visible = false
    end
end

local function openSkinUI(itemName)
    if not skinUI then return end
    tooltip.Visible = false
    refreshSkinUI(itemName)
    skinUI.Visible = true
    print("🎨 Skin UI 열림 - 아이템:", itemName)
end

local function closeSkinUI()
    if not skinUI then return end
    skinUI.Visible = false
    currentSkinItem = nil
    print("🎨 Skin UI 닫힘")
end

-- Skin 버튼 클릭 → Skin UI 열기 (비활성화: UnifiedInven이 스킨 UI를 담당)
-- if tooltipSkin then
--     tooltipSkin.MouseButton1Click:Connect(function()
--         if currentTooltipItem then
--             openSkinUI(currentTooltipItem.name)
--         end
--     end)
-- end

-- Skin UI Close 버튼
if skinClose then
    skinClose.MouseButton1Click:Connect(closeSkinUI)
end

-- Equip 버튼: 스킨 착용/해제
local function handleSkinEquip(slotIndex)
    if not currentSkinItem then return end
    local skinList = getPlayerSkin:InvokeServer(currentSkinItem)
    local skinData = skinList and skinList[slotIndex]
    if not skinData then return end
    
    if not skinData.owned then
        showEquipWarning("You don't own this skin!")
        return
    end
    
    if skinData.equipped then
        -- 해제
        setPlayerSkin:FireServer(currentSkinItem, nil)
    else
        -- 착용
        setPlayerSkin:FireServer(currentSkinItem, skinData.skinName)
    end
    
    -- UI 새로고침
    task.wait(0.1)
    refreshSkinUI(currentSkinItem)
end

if skinEquip1 then
    skinEquip1.MouseButton1Click:Connect(function() handleSkinEquip(1) end)
end
if skinEquip2 then
    skinEquip2.MouseButton1Click:Connect(function() handleSkinEquip(2) end)
end

-- _G.openSkinUI / closeSkinUI 등록 제거: 스킨 UI는 UnifiedInven으로 통합됨.
-- (이 구버전 TaggerInven의 빈 skin ui가 UnifiedInven 위에 겹쳐 스크롤 입력을 가로채는 문제 해결)
print("✅ TaggerInven Skin UI 연결 비활성화 (UnifiedInven으로 통합됨)")
